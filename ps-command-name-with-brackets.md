# ps コマンドで `[ ]` 付きのプロセス名が表示される仕組み (CentOS 6 / Linux 2.6.32 時代の調査)

> **注意**: この文書は CentOS 6 (Linux 2.6.32 系) 環境で調査した内容を元にしています。Linux 5.18 以降ではカーネルの挙動が変わっている箇所があります。変更点については本文中で補足しています。

## 要約

`ps` コマンドは `/proc/$pid/cmdline` から値を取得できない場合に、`/proc/$pid/stat` の comm フィールド（`task_struct->comm`）を `[ ]` で囲んで表示します。カーネルスレッドの表示と似ているため混乱しやすいですが、ユーザ空間のプロセスでも同じ表示になるケースがあります。

---

## 現象

```
[vagrant@vagrant-centos6 ~]$ ./a.out
UID        PID  PPID  C STIME TTY          TIME CMD
vagrant   9660  9149  0 14:57 pts/0    00:00:00 [exe]
```

ps は `/proc/$pid/cmdline` から値を取れない状態の際に、 cmd, command の値を `[ ]` でくくった値を返します。

<!-- CC添削: カーネルスレッドと紛らわしい点を明記しました。[kworker/0:1] のようなカーネルスレッドも同じ表示形式であるため、一見しただけでは区別がつきません -->

### man に記載されている仕様

```
args       COMMAND  command with all its arguments as a string. Modifications to the arguments may be shown. The output in this column may contain spaces.
                    A process marked <defunct> is partly dead, waiting to be fully destroyed by its parent. Sometimes the process args will be unavailable; when
                    this happens, ps will instead print the executable name in brackets. (alias cmd, command). See also the comm format keyword, the -f option,
                    and the c option.
```

---

## 再現コード

unix.stackexchange.com にも [同種の質問](http://unix.stackexchange.com/questions/110595/)が投稿されています。 また[再現コード](http://unix.stackexchange.com/questions/110595/why-do-forked-processes-sometimes-appear-with-brackets-around-their-name-in-p?answertab=active#tab-top) が投稿されているので実行してみます。

```c
int main(int argc, char *argv[]) {
  if (argc) execve("/proc/self/exe",0,0);
  else system("ps -fp $PPID");
}
```

### 実行結果

```
[vagrant@vagrant-centos6 ~]$ ./a.out
UID        PID  PPID  C STIME TTY          TIME CMD
vagrant   9660  9149  0 14:57 pts/0    00:00:00 [exe]
```

一見するとカーネルスレッドと似ているのでややこしいです。

### 再現コードの動作解説

<!-- CC添削: 再現コードが *なぜ* この表示になるかの仕組みを追記しました -->

1. **初回実行時** (`argc != 0`): `execve("/proc/self/exe", 0, 0)` を呼びます
   - `/proc/self/exe` は自プロセスの実行ファイルへのシンボリックリンクです
   - 第2引数 `argv=NULL`、第3引数 `envp=NULL` で execve を呼ぶため、新しいプロセスイメージは引数なしで起動します
2. **execve 後の再実行時** (`argc == 0`): `system("ps -fp $PPID")` を呼びます
   - `argv=NULL` で execve したため `argc` は `0` になります
   - `$PPID` は親プロセス（元のシェル）の PID を指します

### `[exe]` の `exe` はどこから来るのか

<!-- CC添削: [exe] の名前の由来を追記しました。/proc/self/exe のリンク先ではなく、パス文字列の basename であることがポイントです -->

カーネルの `begin_new_exec()` 関数内で `task->comm` が以下のように設定されます:

```c
__set_task_comm(me, kbasename(bprm->filename), true);
```

`bprm->filename` は execve に渡されたパス文字列そのもの（`"/proc/self/exe"`）です。シンボリックリンクは解決されません。`kbasename("/proc/self/exe")` は `"exe"` を返すため、`task->comm` は `"exe"` になります。ps は cmdline が空なので comm にフォールバックし、`[exe]` と表示します。

### Linux 5.18 以降ではこの再現コードは動作しません

<!-- CC添削: 元の調査は CentOS 6（カーネル 2.6.32 系）で実施されたものです。Linux 5.18 以降でカーネルの挙動が変わっているため、注意書きを追記しました -->

Linux 5.18 のコミット [`dcd46d897adb`](https://github.com/torvalds/linux/commit/dcd46d897adb70d63e025f175a00a89797d31a43) で、**argv が空の場合にカーネルが空文字列 `""` を `argv[0]` として自動注入する** 修正が入りました。

```c
/* do_execveat_common() 内 */
if (bprm->argc == 0) {
    retval = copy_string_kernel("", bprm);
    if (retval < 0)
        goto out_free;
    bprm->argc = 1;
}
```

この修正により `argc` は常に 1 以上になるため、再現コードの `if (argc)` は常に真となり、`execve` が無限ループします。この修正は **CVE-2021-4034 (PwnKit)** への対策です。Polkit の `pkexec` が `argc=0` の場合に `argv[1]`（メモリレイアウト上 `envp[0]` と重なる）を読み書きすることで、ローカル権限昇格が可能でした。

---

## `/proc/$pid/cmdline` が空になる条件

<!-- CC添削: 元の記述では「fork か exec の途中」と疑問形で書かれていましたが、カーネルソースに基づいて正確な条件を列挙しました -->

カーネル関数 `proc_pid_cmdline_read()` → `get_task_cmdline()` → `get_mm_cmdline()` の呼び出しチェーンで、以下の条件で cmdline は空を返します。

| 条件 | 理由 | カーネル内の判定箇所 |
|---|---|---|
| **カーネルスレッド** | `mm_struct` が NULL です。`PF_KTHREAD` フラグにより `get_task_mm()` が NULL を返します | `get_task_mm()` |
| **ゾンビプロセス** (Z 状態) | `exit_mm()` で mm が解放済みです | `get_task_mm()` |
| **execve 実行途中** (一時的) | `arg_start`/`arg_end` が未設定、または新しいアドレス空間がまだ構築されていません | `get_mm_cmdline()` で `env_end == 0` の判定 |
| **`argv=NULL` で execve したプロセス** | 引数文字列がスタックにコピーされず `arg_start == arg_end` になります | `get_mm_cmdline()` で `arg_start >= arg_end` の判定 |
| **`prctl(PR_SET_MM_ARG_START/END)` で意図的にクリア** | ユーザ空間から arg 範囲を変更できます | `get_mm_cmdline()` で `arg_start >= arg_end` の判定 |

<!-- CC添削: 元の記述にあった「fork の途中」は正確ではありません。fork 直後は親の mm_struct が COW コピーされるため、cmdline は親と同じ値が見えます。空になるのは exec の途中です -->

### `get_mm_cmdline()` の空判定コード

```c
/* fs/proc/base.c */

/* プロセスがまだ十分に初期化されていない */
if (env_end == 0)
    return 0;

/* cmdline データが存在しない */
if (arg_start >= arg_end)
    return 0;
```

---

## `[ ]` をつける箇所はどこか? ps (procps-ng) の実装を追う

<!-- CC添削: 元の記述に pp->cmdline と pp->cmd の取得元の違いを追記しました。これが [ ] 表示の仕組みを理解する鍵です -->

### pp->cmdline と pp->cmd の違い

| フィールド | 取得元 | 内容 |
|---|---|---|
| `pp->cmdline` | `/proc/$pid/cmdline` | `execve(2)` に渡された `argv[]` の全要素です |
| `pp->cmd` | `/proc/$pid/stat` の 2番目のフィールド | カーネルの `task_struct->comm` に対応します。最大 15 文字（`TASK_COMM_LEN - 1`）に切り詰められたバイナリの basename です |

### ESC フラグの定義

```c
#define ESC_ARGS     0x1  // cmdline (引数) の使用を試みます
#define ESC_BRACKETS 0x2  // cmd を使用する場合 [ ] で囲みます
#define ESC_DEFUNCT  0x4  // ゾンビプロセスの場合 <defunct> を付加します
```

### `escape_command` 関数

`ESC_BRACKETS` を追いかけていくと `escape_command` にたどり着きます。ここで `[ ]` が付きます。

```c
int escape_command(char *restrict const outbuf, const proc_t *restrict const pp, int bytes, int *cells, unsigned flags){
  int overhead = 0;
  int end = 0;

  /* cmdline から値をとれたらそれを返す */
  if(flags & ESC_ARGS){
    const char **lc = (const char**)pp->cmdline;
    if(lc && *lc) return escape_strlist(outbuf, lc, bytes, cells);
  }

  /* cmdline から値をとれない場合 */

  /* ESC_BRACKETS フラグがたっていれば [ ] でエスケープする */
  if(flags & ESC_BRACKETS){
    overhead += 2;
  }
  if(flags & ESC_DEFUNCT){
    if(pp->state=='Z') overhead += 10;    // chars in " <defunct>"
    else flags &= ~ESC_DEFUNCT;
  }
  if(overhead + 1 >= *cells){  // if no room for even one byte of the command name
    // you'd damn well better have _some_ space
//    outbuf[0] = '-';  // Oct23
    outbuf[1] = '\0';
    return 1;
  }
  if(flags & ESC_BRACKETS){
    outbuf[end++] = '[';
  }
  *cells -= overhead;
  end += escape_str(outbuf+end, pp->cmd, bytes-overhead, cells);

  // Hmmm, do we want "[foo] <defunct>" or "[foo <defunct>]"?
  if(flags & ESC_BRACKETS){
    outbuf[end++] = ']';
  }
  if(flags & ESC_DEFUNCT){
    memcpy(outbuf+end, " <defunct>", 10);
    end += 10;
  }
  outbuf[end] = '\0';
  return end;  // bytes, not including the NUL
}
```

### 動作フローのまとめ

<!-- CC添削: escape_command のフローを図示しました -->

```
escape_command() が呼ばれる
  │
  ├─ pp->cmdline が非 NULL → cmdline をそのまま表示（[ ] なし）
  │
  └─ pp->cmdline が NULL → pp->cmd にフォールバック
       │
       ├─ ESC_BRACKETS → [cmd] の形式で表示
       │
       └─ ESC_DEFUNCT かつ state == 'Z' → [cmd] <defunct> の形式で表示
```

---

## `[ ]` 付きで表示されるケースの全パターン

<!-- CC添削: 元の記述では言及されていなかったパターンを網羅的に追記しました -->

| パターン | 表示例 | 原因 |
|---|---|---|
| **カーネルスレッド** | `[kworker/0:0]`, `[ksoftirqd/0]` | mm_struct が NULL のため cmdline が空です |
| **ゾンビプロセス** | `[some_cmd] <defunct>` | `exit_mm()` で mm が解放済みです。`ESC_DEFUNCT` で ` <defunct>` が付加されます |
| **execve 実行途中** (一時的) | `[prog_name]` | exec の過程で一時的に cmdline が空になる瞬間があります |
| **argv=NULL で execve** | `[exe]` | 引数がスタックにコピーされず cmdline が空です |
| **prctl で cmdline をクリア** | `[process_name]` | `prctl(PR_SET_MM_ARG_START/END)` で arg 範囲を操作した場合です |

---

## セキュリティ上の注意: プロセスの偽装

<!-- CC添削: [ ] 表示がカーネルスレッドの偽装に悪用される可能性について追記しました。セキュリティ調査で重要な観点です -->

悪意あるプロセスがカーネルスレッドを偽装して `[]` 表示にすることが可能です:

```bash
# 実行ファイル名自体に [] を含める
cp /bin/sleep "/tmp/[kworkerd]"
"/tmp/[kworkerd]" 3600 &
```

この場合 cmdline は空ではなく `[kworkerd] 3600` のように表示されますが、引数なしで起動すれば本物のカーネルスレッドと区別がつきにくくなります。

### 偽装の検出方法

| 確認対象 | コマンド例 | カーネルスレッドの場合 | 偽装プロセスの場合 |
|---|---|---|---|
| メモリマップ | `cat /proc/<PID>/maps` | 空 | ライブラリがマップされています |
| 実行ファイルのリンク | `ls -l /proc/<PID>/exe` | リンクが存在しません | 実行ファイルへのリンクが存在します |
| 親プロセス | `ps -o ppid= -p <PID>` | 2 (kthreadd) | 通常 2 以外です |

---

## 参考ソース・参考資料

### カーネルソース

| ファイル | 関数・定義 | 内容 |
|---|---|---|
| [`fs/proc/base.c`](https://github.com/torvalds/linux/blob/master/fs/proc/base.c) | `proc_pid_cmdline_read()`, `get_task_cmdline()`, `get_mm_cmdline()` | `/proc/$pid/cmdline` の read ハンドラです |
| [`kernel/fork.c`](https://github.com/torvalds/linux/blob/master/kernel/fork.c) | `get_task_mm()` | `PF_KTHREAD` フラグのチェックにより、カーネルスレッドに対して NULL を返します |
| [`fs/exec.c`](https://github.com/torvalds/linux/blob/master/fs/exec.c) | `do_execveat_common()`, `begin_new_exec()` | execve の実装です。`task->comm` の設定、argv 空チェック (5.18+) を含みます |
| [`mm/memory.c`](https://github.com/torvalds/linux/blob/master/mm/memory.c) | `access_remote_vm()` | プロセスメモリからの読み取りを行います |

### procps-ng ソース

| ファイル | 関数・定義 | 内容 |
|---|---|---|
| [`library/escape.c`](https://gitlab.com/procps-ng/procps/-/blob/master/library/escape.c) (v4.x) / `proc/escape.c` (v3.x) | `escape_command()` | `[ ]` の付加、`<defunct>` の付加を行う関数です |
| [`library/escape.h`](https://gitlab.com/procps-ng/procps/-/blob/master/library/escape.h) | `ESC_BRACKETS`, `ESC_ARGS`, `ESC_DEFUNCT` | エスケープフラグの定義です |
| [`library/readproc.c`](https://gitlab.com/procps-ng/procps/-/blob/master/library/readproc.c) | `fill_cmdline_cvt()` | `/proc/$pid/cmdline` が空の場合に `ESC_BRACKETS \| ESC_DEFUNCT` で `escape_command()` を呼びます |

### コミット・CVE

| 参照 | 内容 |
|---|---|
| [`dcd46d897adb`](https://github.com/torvalds/linux/commit/dcd46d897adb70d63e025f175a00a89797d31a43) | Linux 5.18: argv が空の場合に空文字列を自動注入する修正です |
| [CVE-2021-4034 (PwnKit)](https://blog.qualys.com/vulnerabilities-threat-research/2022/01/25/pwnkit-local-privilege-escalation-vulnerability-discovered-in-polkits-pkexec-cve-2021-4034) | `argc=0` を悪用した Polkit pkexec のローカル権限昇格脆弱性です |
| [LWN: Handling argc==0 in the kernel](https://lwn.net/Articles/882799/) | argv 空チェック導入の議論経緯です |

### 外部資料

| 参照 | 内容 |
|---|---|
| [unix.stackexchange.com #110595](http://unix.stackexchange.com/questions/110595/) | 再現コードの出典です |
| [ps(1) man page](https://man7.org/linux/man-pages/man1/ps.1.html) | ps コマンドのマニュアルです |
| [proc(5) man page](https://man7.org/linux/man-pages/man5/proc.5.html) | `/proc` ファイルシステムのマニュアルです |
```