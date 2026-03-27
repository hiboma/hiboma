# macOS で `ps` コマンドによる環境変数の露出を抑制する方法

> This report was generated with [Claude Code](https://claude.ai/code) (Claude Opus 4.6)

## 概要

macOS では `ps` コマンドにより、同一ユーザーの別プロセスからプロセスの環境変数を閲覧できます。root は全ユーザーのプロセス情報を取得できますが、これは通常の権限行使です。環境変数にシークレット（API キー、データベースパスワードなど）を格納している場合、同一ユーザーの別プロセスや侵害されたアカウントからシークレットが読み取られる可能性があります。

本レポートでは、この問題の技術的背景と緩和策をまとめます。

## `ps` で環境変数を表示するオプション

macOS の `ps` で環境変数を表示する方法を整理します。

### `-E` オプション（推奨）

```bash
ps -E -ww -p $$
```

man ps(1) より:

> **-E** Display the environment as well. This does not reflect changes in the environment after process launch.

`-E` が環境変数を表示するための正式なオプションです。プロセス起動時の環境変数が表示されます。起動後に `unsetenv()` 等で変更しても、`ps -E` の出力には反映されません。

### `-e` オプション（レガシーモードとの差異に注意）

`-e` の挙動は macOS のモードによって異なります。

| モード | `-e` の意味 |
|---|---|
| 現行（POSIX 準拠） | `-A` と同一。全プロセスを表示します。環境変数は表示しません |
| レガシーモード | `-E` と同一。環境変数を表示します |

レガシーモードは `compat(5)` で制御されます。混乱を避けるため、環境変数の表示には明示的に `-E` を使用します。

### `-w` オプション（出力幅の制御）

```bash
ps -E -w      # 132 カラム幅で表示
ps -E -ww     # カラム幅の制限なし（環境変数を全て表示する場合に必要）
```

`-w` を1回指定すると132カラム、2回指定（`-ww`）するとカラム幅の制限がなくなります。環境変数は長いため、`-ww` との組み合わせが実用的です。

### Linux の `ps -E` との違い

Linux（procps-ng）の `ps` は BSD スタイルのオプション `e` で環境変数を表示します。

```bash
# Linux
ps eww -p $$     # BSD スタイル: e = 環境変数表示, ww = 幅無制限

# macOS
ps -E -ww -p $$  # -E = 環境変数表示, -ww = 幅無制限
```

macOS で `ps -E` と入力した場合、BSD スタイルのオプション解釈により環境変数が表示されるケースがありますが、macOS の man ps(1) に記載された正式な方法は `-E` です。

## 技術的背景

### macOS における `ps` の実装

- macOS の `ps` は `/proc` ファイルシステムではなく、`sysctl` の `KERN_PROCARGS2` 経由でプロセス情報を取得します
- Linux の `/proc/<pid>/environ` のようにファイルパーミッションで制御する仕組みが macOS には存在しません
- 同一ユーザーのプロセスの環境変数が閲覧可能です。root は全ユーザーのプロセス情報を取得できます

`ps` コマンドのソースコード（`adv_cmds/ps/print.c` の `getproclline()` 関数）は、`sysctl()` を `{ CTL_KERN, KERN_PROCARGS2, pid }` で呼び出してプロセスの引数と環境変数を取得しています。

- ps コマンドのソース: https://github.com/apple-oss-distributions/adv_cmds/tree/main/ps

#### `ps -E` で環境変数が表示されないケース

`KERN_PROCARGS2` に環境変数が含まれていても、`ps -E -ww` で表示されない場合があります。これは `ps` のユーザランド実装（`getproclline()` のパーサー）に起因します。

`getproclline()` の環境変数表示ループには「連続する2つの `\0` を検出したらパースを停止する」ロジックがあります。

```c
// adv_cmds/ps/print.c — getproclline() の環境変数ループ
for (; cp < &procargs[size]; cp++) {
    if (*cp == '\0') {
        if (np != NULL) {
            if (&np[1] == cp) {
                // Two '\0' characters in a row → stop parsing
                break;
            }
            *np = ' ';
        }
        np = cp;
    }
}
```

プロセスが起動後に `argv` 領域を書き換えて空文字列（NUL 1バイト）にした場合、argv の終端と NUL パディングが連続 NUL として検出され、環境変数に到達する前にパースが打ち切られます。

##### 実例: ruby-lsp プロセス

ruby-lsp は `argc=5` で起動した後に `argv[1]`〜`argv[4]` をクリアしています。`KERN_PROCARGS2` のデータ構造は以下の通りです。

```
argc=5
exec_path: .../.rbenv/versions/x.x.x/bin/ruby\0
argv[0]: .../.rbenv/versions/x.x.x/bin/ruby-lsp\0
argv[1]: \0              ← 空文字列（起動後にクリアされた）
argv[2]: \0
argv[3]: \0
argv[4]: \0
\0\0\0...(NUL パディング)...\0
RBENV_VERSION=x.x.x\0   ← 環境変数（ここに到達しない）
```

`ps -E -ww` では環境変数が表示されませんが、`sysctl(KERN_PROCARGS2)` を直接呼ぶプログラムでは環境変数が読み取れます。

```bash
# ps -E -ww では環境変数が表示されない
$ ps -E -ww -p <PID>
  PID TTY           TIME CMD
12345 ttys011    0:03.91 /Users/&lt;USER&gt;/.rbenv/versions/x.x.x/bin/ruby-lsp

# sysctl を直接呼ぶと環境変数が読める
$ ./read_env <PID>
argc: 5
env[0]: RBENV_VERSION=x.x.x
env[1]: MANWIDTH=80
...
Total env vars found: 75
```

`ps -E` で環境変数が見えないからといって、`KERN_PROCARGS2` 経由で環境変数が保護されているわけではありません。

### SIP による環境変数の読み取り制限（CS_RESTRICT）

macOS 11 Big Sur 以降、SIP (System Integrity Protection) が有効な環境では、**`CS_RESTRICT` フラグが設定されたプロセスの環境変数はカーネルレベルで非表示になります**。

#### 観察: `ps eww` で環境変数が見えるプロセスと見えないプロセス

```bash
# /usr/bin/perl — SIP 保護パス配下。環境変数は表示されない
$ /usr/bin/perl -e 'sleep 1000' &
$ ps eww -p $!
  PID   TT  STAT      TIME COMMAND
12345 s014  S+     0:00.01 perl -e sleep 1000

# ~/.rbenv/ 配下の ruby — SIP 保護対象外。環境変数が全て表示される
$ ~/.rbenv/versions/x.x.x/bin/ruby -e 'sleep 100' &
$ ps eww -p $!
  PID   TT  STAT      TIME COMMAND
12346 s014  S+     0:00.04 /Users/&lt;USER&gt;/.rbenv/versions/x.x.x/bin/ruby -e sleep 100 TERM=xterm-256color HOME=/Users/foo ...
```

| バイナリのパス | 環境変数の表示 | 理由 |
|---|---|---|
| `/usr/bin/perl` | 表示されない | SIP 保護パス配下のバイナリ。`CS_RESTRICT` フラグが設定されています |
| `~/.local/bin/claude` | 表示される | SIP 保護対象外のパスです |
| `~/.rbenv/versions/x.x.x/bin/ruby` | 表示される | SIP 保護対象外のパスです |

SIP の保護対象パス（`/usr/bin/`, `/bin/`, `/usr/sbin/`, `/sbin/`）にある Apple 署名済みバイナリの多くには `CS_RESTRICT` フラグが設定されています。ただし、すべてではありません。`CS_RESTRICT` はバイナリのパスではなく、AMFI (Apple Mobile File Integrity) が exec 時にバイナリのコード署名属性を評価して動的に付与するフラグです。たとえば `/usr/bin/python3` は SIP 保護パス配下ですが `CS_RESTRICT` は設定されていません。

#### XNU カーネルソースにおける実装

環境変数の読み取り制限は、XNU カーネルの `bsd/kern/kern_sysctl.c` にある `sysctl_procargsx()` 関数で実装されています。

```c
// bsd/kern/kern_sysctl.c — sysctl_procargsx()

#define SYSCTL_PROCARGS_READ_ENVVARS_ENTITLEMENT \
    "com.apple.private.read-environment-variables"

bool omit_env_vars = true;

#if DEVELOPMENT || DEBUG
    omit_env_vars = false;
#endif

if (p == current_proc() ||
    !cs_restricted(p) ||
#if CONFIG_CSR
    csr_check(CSR_ALLOW_UNRESTRICTED_DTRACE) == 0 ||
#endif
    IOCurrentTaskHasEntitlement(SYSCTL_PROCARGS_READ_ENVVARS_ENTITLEMENT))
{
    omit_env_vars = false;
}
```

環境変数が**表示される**（`omit_env_vars = false`）条件は以下のいずれかを満たす場合です:

1. DEVELOPMENT または DEBUG ビルドのカーネルである
2. 呼び出し元が対象プロセス自身である（`p == current_proc()`）
3. 対象プロセスに `CS_RESTRICT` フラグが設定されていない（`!cs_restricted(p)`）
4. SIP の `CSR_ALLOW_UNRESTRICTED_DTRACE` が許可されている
5. 呼び出し元が `com.apple.private.read-environment-variables` エンタイトルメントを持つ

逆に言えば、リリース版カーネル上で、SIP が有効かつ `CS_RESTRICT` フラグが付いたプロセスの環境変数を、別プロセスから `KERN_PROCARGS2` 経由で取得することはできません。

#### 関連するソースコードと定数

| ファイル | 関数・定数 | 役割 |
|---|---|---|
| `bsd/kern/kern_sysctl.c` | `sysctl_procargsx()` | 環境変数フィルタリングの本体です |
| `bsd/kern/kern_sysctl.c` | `sysctl_doprocargs2()` | `KERN_PROCARGS2` のハンドラです |
| `bsd/kern/kern_cs.c` | `cs_restricted()` | `CS_RESTRICT` フラグの確認を行います |
| `osfmk/kern/cs_blobs.h` | `CS_RESTRICT = 0x00000800` | フラグの定数定義です |
| `bsd/sys/csr.h` | `CSR_ALLOW_UNRESTRICTED_DTRACE` | SIP のフラグ定義です |

XNU ソース: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c

#### 導入時期

xnu-3247（El Capitan 10.11）の `sysctl_procargsx()` には `omit_env_vars` ロジックが存在しません。xnu-7195（macOS 11 Big Sur）で導入されたと推定されます。

### 結論

macOS には `CS_RESTRICT` フラグと SIP による環境変数の読み取り制限がカーネルレベルで実装されています。ただし、この保護は AMFI が `CS_RESTRICT` フラグを付与した一部の Apple 署名済みバイナリに限定されます。SIP 保護パス配下であっても `CS_RESTRICT` が設定されないバイナリ（`/usr/bin/python3` 等）が存在します。サードパーティのバイナリやユーザーがインストールしたバイナリには `CS_RESTRICT` フラグが設定されないため、`ps -E` で閲覧することを防ぐことはできません。緩和策を組み合わせて対応する必要があります。

## 緩和策

### 1. 環境変数にシークレットを渡さない（推奨）

最も確実な方法です。代替手段を以下に示します。

#### ファイル経由で渡す

シークレットをファイルに書き、`chmod 600` で保護し、アプリケーション側でファイルから読み取ります。

```bash
echo "secret-value" > /path/to/secret
chmod 600 /path/to/secret
my-app --password-file=/path/to/secret
```

#### stdin 経由で渡す

パイプや heredoc でプロセスの標準入力にシークレットを渡します。

```bash
echo "secret-value" | my-app --password-stdin
```

#### macOS Keychain を利用する

`security` コマンドや Keychain Services API を使います。

```bash
# 追加
security add-generic-password -s "my-app" -a "api-key" -w "secret-value" login.keychain-db

# 取得（-w でパスワード文字列のみ出力）
DB_PASSWORD=$(security find-generic-password -s "my-app" -a "api-key" -w)

# ファイルディスクリプタ経由で渡す（ps に露出しない）
exec 3<<< "$DB_PASSWORD"
my-app --password-fd=3
```

#### シークレットマネージャを利用する

1Password CLI、HashiCorp Vault などのシークレットマネージャから実行時に取得します。

### 1Password CLI `op run` の注意点

`op run --env-file=.env` は `.env` ファイル中のシークレット参照（`op://vault/item/field`）を 1Password から解決し、子プロセスの環境変数として渡します。

```bash
# .env の内容
# DB_PASSWORD=op://Private/database/password

op run --env-file=.env -- my-app
```

`op run` が提供する価値は「`.env` ファイルにシークレットの平文を保存しない」ことです。しかし、**子プロセスの環境変数としてシークレットが渡される仕組みは変わらないため、同一ユーザーの別プロセスから `ps -E -ww` でシークレットを読み取ることができます**。

```bash
# 別のターミナルから確認すると、解決済みのシークレットが見える
ps -E -ww -p <子プロセスのPID>
```

`op run` 自体のプロセスにはシークレットがコマンドライン引数に現れないため、`ps` の引数欄（`COMMAND` 列）には露出しません。露出するのは子プロセスの環境変数です。

`op run` を使う場合でも、`ps -E` による露出を防ぐには、環境変数ではなくファイルや stdin 経由でシークレットを渡す方式への切り替えが必要です。`unsetenv()` はユーザ空間の `getenv()` には有効ですが、`ps -E` が参照する `KERN_PROCARGS2` のスナップショットには影響しません（後述）。

### 2. プロセス起動後に環境変数を消す

アプリケーション側で起動直後に環境変数を読み取り、メモリ上に保持した後 `unsetenv()` で削除します。

```c
#include <stdlib.h>
#include <string.h>

const char *env = getenv("SECRET_KEY");
if (env == NULL) {
    // SECRET_KEY が設定されていない場合のエラーハンドリング
}
char *secret = strdup(env);
unsetenv("SECRET_KEY");

// 以降は secret 変数を使う
// 使い終わったら明示的に消去する
// memset ではなく memset_s を使う。memset は直後の free とともにコンパイラの
// 最適化（デッドストア削除）で省略される可能性がある
memset_s(secret, strlen(secret), 0, strlen(secret));
free(secret);
```

#### `ps -E` に対する効果

**`unsetenv()` は `ps -E` に対して無効です。** `ps -E` が参照する `KERN_PROCARGS2` は、カーネルがプロセスの exec 時に保存した引数・環境変数のスナップショットです。プロセスのユーザ空間で `unsetenv()` を呼んでも、カーネル側のスナップショットは変更されません。

man ps(1) にも以下の記述があります:

> -E Display the environment as well. **This does not reflect changes in the environment after process launch.**

`unsetenv()` が有効なのは、アプリケーション自身が `getenv()` で自プロセスの環境変数を読む場合や、`fork`/`exec` で子プロセスに環境変数を引き継がせない場合に限られます。

### ~~3. `security.bsd.see_other_uids` で他ユーザーのプロセスを非表示にする~~

**`security.bsd.see_other_uids` は FreeBSD 固有の sysctl パラメータであり、macOS (XNU) には実装されていません。** macOS 15 Sequoia で `sysctl security.bsd.see_other_uids` を実行すると `unknown oid` エラーになります。macOS では `security.bsd` 名前空間自体が存在しません。

### 3. Endpoint Security フレームワーク

~~macOS の Endpoint Security フレームワークを使い `proc_info` 系のシステムコールを監視・制限することは理論上可能ですが、MDM 配布の System Extension として実装する必要があり、一般的な対策とは言えません。~~

Endpoint Security フレームワークには `sysctl(KERN_PROCARGS2)` の呼び出しを監視・制限するイベントタイプ（`ES_EVENT_TYPE_AUTH_PROC_INFO` 等）は存在しません。exec, fork, open 等のイベントは監視できますが、任意の sysctl 呼び出しをフックする機能は提供されていないため、この方法では環境変数の読み取りを制限できません。

### 4. sandbox (Seatbelt) による sysctl 読み取り制限

sandbox profile で `KERN_PROCARGS2` の sysctl 呼び出しをブロックできます。ただし、これは**読み取る側**のプロセスを制限する仕組みであり、読み取られる側を保護する仕組みではありません。

XNU カーネルの `sysctl_root()` (`bsd/kern/kern_newsysctl.c`) では、個別ハンドラ呼び出しの前に MACF (Mandatory Access Control Framework) 経由で sandbox のチェックが行われます。

```c
// bsd/kern/kern_newsysctl.c — sysctl_root()
#if CONFIG_MACF
if (!from_kernel) {
    error = mac_system_check_sysctlbyname(kauth_cred_get(),
        namestring, name, namelen,
        req->oldptr, req->oldlen, req->newptr, req->newlen);
    if (error) {
        goto dropref;
    }
}
#endif
```

sandbox profile では `sysctl-read` オペレーションで制御します。

```scheme
;; sysctl-read を deny すると KERN_PROCARGS2 の読み取りがブロックされる
(version 1)
(deny default)
(allow sysctl-read (sysctl-name "kern.ostype"))  ;; 必要なもののみ許可
```

`sysctl(KERN_PROCARGS2)` と `proc_pidinfo()` は異なるチェックパスを通るため、制限するオペレーションが異なります。

| アクセス方法 | MACF フック | sandbox オペレーション |
|---|---|---|
| `sysctl(KERN_PROCARGS2)` | `mac_system_check_sysctlbyname()` | `sysctl-read` |
| `proc_pidinfo()` | `mac_proc_check_proc_info()` | `process-info-pidinfo` |

`(deny process-info*)` のみでは sysctl 経由の `KERN_PROCARGS2` アクセスはブロックされません。`(deny sysctl-read)` が必要です。

### 5. VM ベースのコンテナ (Docker / Colima) による分離

macOS の Docker は Linux VM の中でコンテナを実行します。ホスト macOS の `KERN_PROCARGS2` は macOS カーネルのプロセステーブルのみを参照するため、VM 内のプロセス情報には一切アクセスできません。

```
ホスト macOS
  └─ ps -E -ww → macOS カーネルの KERN_PROCARGS2 のみ参照
  └─ com.docker.backend (VM プロセス。内部のコンテナ情報は見えない)
      └─ Linux VM (別カーネル)
          └─ コンテナプロセス (SECRET=xxx) ← ホストからは不可視
```

macOS には Linux の PID namespace のようなカーネルレベルのプロセス名前空間分離機構は存在しません。VM ベースのコンテナ実行環境が、macOS において環境変数の分離を実現する最も確実な方法です。

### macOS 15 での検証

macOS 15 (Sequoia) で、SIP 保護パス外の独自ビルドバイナリに対して `KERN_PROCARGS2` 経由の環境変数読み取りを検証しました。

```bash
# /tmp/claude/sleeper を MY_SECRET=... で起動し、別プロセスから読み取り
$ /tmp/claude/read_env <sleeper の PID>
env[76]: MY_SECRET=this_is_a_secret_value
Total env vars found: 87
```

| 対象バイナリ | CS_RESTRICT | 環境変数の読み取り |
|---|---|---|
| `/tmp/claude/sleeper` (独自ビルド、`adhoc,linker-signed`) | なし | **87件すべて読み取り可能** |
| `/bin/zsh` (SIP 保護パス内) | あり | **0件（カーネルが除外）** |

macOS 15 でも `sysctl_procargsx()` の `omit_env_vars` ロジックに変更はなく、`CS_RESTRICT` フラグが設定されていないバイナリの環境変数は従来通り他プロセスから読み取り可能です。

### Linux namespace との比較

| 観点 | Linux PID namespace | macOS sandbox | macOS VM (Docker) |
|---|---|---|---|
| カーネルの分離 | 同一カーネル内の論理分離 | 同一カーネル内のポリシー制御 | 別カーネル（物理分離） |
| 環境変数の遮断 | namespace 外からは不可視 | `sysctl-read` deny で制限可能 | ホストから完全に不可視 |
| root による読み取り | namespace を越えてアクセス可能 | sandbox は root でも適用される | ホスト root でもアクセス不可 |
| 保護の方向 | 被保護プロセスを隔離 | 読み取り側を制限 | 被保護プロセスを隔離 |

## Keychain Services API

macOS Keychain は `ps -E` 対策として有効な手段です。以下に API の詳細を記載します。

### アイテムの種類

| クラス | 定数 | 用途 |
|---|---|---|
| Generic Password | `kSecClassGenericPassword` | 任意のシークレット（API キー、トークンなど） |
| Internet Password | `kSecClassInternetPassword` | URL に紐づく認証情報 |
| Certificate | `kSecClassCertificate` | X.509 証明書 |
| Key | `kSecClassKey` | 暗号鍵 |
| Identity | `kSecClassIdentity` | 証明書 + 秘密鍵のペア |

### C API（Security.framework）による CRUD 操作

#### アイテムの追加

```c
#include <Security/Security.h>

OSStatus add_secret(const char *service, const char *account, const char *secret) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFStringRef service_str = CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8);
    CFStringRef account_str = CFStringCreateWithCString(NULL, account, kCFStringEncodingUTF8);
    CFDataRef secret_data = CFDataCreate(NULL, (const UInt8 *)secret, strlen(secret));

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, service_str);
    CFDictionarySetValue(query, kSecAttrAccount, account_str);
    CFDictionarySetValue(query, kSecValueData, secret_data);
    CFDictionarySetValue(query, kSecAttrAccessible,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly);

    OSStatus status = SecItemAdd(query, NULL);
    CFRelease(secret_data);
    CFRelease(account_str);
    CFRelease(service_str);
    CFRelease(query);
    return status;
}
```

#### アイテムの取得

```c
OSStatus get_secret(const char *service, const char *account,
                    char *buf, size_t buf_len) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFStringRef service_str = CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8);
    CFStringRef account_str = CFStringCreateWithCString(NULL, account, kCFStringEncodingUTF8);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, service_str);
    CFDictionarySetValue(query, kSecAttrAccount, account_str);
    CFDictionarySetValue(query, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(query, kSecMatchLimit, kSecMatchLimitOne);

    CFDataRef result = NULL;
    OSStatus status = SecItemCopyMatching(query, (CFTypeRef *)&result);

    if (status == errSecSuccess && result != NULL) {
        CFIndex len = CFDataGetLength(result);
        if ((size_t)len < buf_len) {
            memcpy(buf, CFDataGetBytePtr(result), len);
            buf[len] = '\0';
        }
        CFRelease(result);
    }

    CFRelease(account_str);
    CFRelease(service_str);
    CFRelease(query);
    return status;
}
```

#### アイテムの更新

```c
OSStatus update_secret(const char *service, const char *account,
                       const char *new_secret) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFStringRef service_str = CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8);
    CFStringRef account_str = CFStringCreateWithCString(NULL, account, kCFStringEncodingUTF8);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, service_str);
    CFDictionarySetValue(query, kSecAttrAccount, account_str);

    CFMutableDictionaryRef attrs = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDataRef secret_data = CFDataCreate(NULL, (const UInt8 *)new_secret, strlen(new_secret));
    CFDictionarySetValue(attrs, kSecValueData, secret_data);

    OSStatus status = SecItemUpdate(query, attrs);
    CFRelease(secret_data);
    CFRelease(account_str);
    CFRelease(service_str);
    CFRelease(attrs);
    CFRelease(query);
    return status;
}
```

#### アイテムの削除

```c
OSStatus delete_secret(const char *service, const char *account) {
    CFMutableDictionaryRef query = CFDictionaryCreateMutable(
        NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CFStringRef service_str = CFStringCreateWithCString(NULL, service, kCFStringEncodingUTF8);
    CFStringRef account_str = CFStringCreateWithCString(NULL, account, kCFStringEncodingUTF8);

    CFDictionarySetValue(query, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(query, kSecAttrService, service_str);
    CFDictionarySetValue(query, kSecAttrAccount, account_str);

    OSStatus status = SecItemDelete(query);
    CFRelease(account_str);
    CFRelease(service_str);
    CFRelease(query);
    return status;
}
```

### Swift API

```swift
import Security
import Foundation

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case itemNotFound
    case decodingFailed
}

struct KeychainHelper {
    static func save(service: String, account: String, data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func load(service: String, account: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeychainError.itemNotFound }
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else { throw KeychainError.decodingFailed }
        return data
    }

    static func delete(service: String, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
```

### `security` コマンドによる操作

```bash
# 追加
security add-generic-password \
    -s "my-app" \
    -a "api-key" \
    -w "secret-value-here" \
    -T "" \
    login.keychain-db

# 取得（-w でパスワード文字列のみ出力）
security find-generic-password \
    -s "my-app" \
    -a "api-key" \
    -w

# 削除
security delete-generic-password \
    -s "my-app" \
    -a "api-key"
```

### アクセス制御（kSecAttrAccessible）

| 定数 | 意味 |
|---|---|
| `kSecAttrAccessibleWhenUnlocked` | デバイスがアンロック中のみアクセス可能。バックアップに含まれます |
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | 同上。バックアップに含まれません |
| `kSecAttrAccessibleAfterFirstUnlock` | 再起動後最初のアンロック以降アクセス可能。バックグラウンド処理向けです |
| `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | 同上。バックアップに含まれません |

### キーチェーンの種類

| キーチェーン | パス | 用途 |
|---|---|---|
| login | `~/Library/Keychains/login.keychain-db` | ユーザーごとのデフォルト。ログイン時に自動アンロックされます |
| System | `/Library/Keychains/System.keychain` | システム全体で共有。root 権限が必要です |
| カスタム | 任意のパス | `SecKeychainCreate` で独自に作成できます |

### 主要なエラーコード

| 定数 | 値 | 意味 |
|---|---|---|
| `errSecSuccess` | 0 | 成功 |
| `errSecItemNotFound` | -25300 | アイテムが存在しません |
| `errSecDuplicateItem` | -25299 | 同じアイテムが既に存在します |
| `errSecAuthFailed` | -25293 | 認証失敗（キーチェーンがロック中など） |
| `errSecInteractionNotAllowed` | -25308 | ユーザー操作が必要だが許可されていません |

## 緩和策のまとめ

| 方法 | `ps -E` への効果 | 実装コスト |
|---|---|---|
| シークレットをファイル経由で渡す | 有効 | 低 |
| stdin 経由で渡す | 有効 | 低 |
| Keychain / シークレットマネージャ | 有効 | 中 |
| sandbox profile で `sysctl-read` を deny | 有効（読み取り側の制限） | 中 |
| VM ベースのコンテナ (Docker / Colima) | 有効（完全な分離） | 中 |
| SIP + CS_RESTRICT | 有効（`CS_RESTRICT` 付きバイナリのみ。独自バイナリには適用されない） | なし |
| 起動後に `unsetenv()` | **無効**（KERN_PROCARGS2 のスナップショットは変更されない） | 低 |
| ~~`security.bsd.see_other_uids=0`~~ | **macOS には存在しない**（FreeBSD 固有） | — |

## 参考リソース

### XNU カーネルソース

- [kern_sysctl.c — sysctl_procargsx()](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c) — 環境変数フィルタリングの実装箇所です
- [kern_cs.c — cs_restricted()](https://github.com/apple/darwin-xnu/blob/main/bsd/kern/kern_cs.c) — `CS_RESTRICT` フラグの判定を行います
- [adv_cmds/ps](https://github.com/apple-oss-distributions/adv_cmds/tree/main/ps) — macOS の `ps` コマンドのソースコードです

### Apple 公式ドキュメント

- [About System Integrity Protection](https://support.apple.com/en-us/102149)

### 技術記事

- [macOS's System Integrity Protection sanitizes your environment](https://briandfoy.github.io/macos-s-system-integrity-protection-sanitizes-your-environment/) — SIP が環境変数に与える影響の解説です
- [System Integrity Protection: The misunderstood setting](https://khronokernel.com/macos/2022/12/09/SIP.html) — SIP の各フラグの詳細な解説です
- [DYLD_INSERT_LIBRARIES injection in macOS — CS_RESTRICT の解説](https://theevilbit.github.io/posts/dyld_insert_libraries_dylib_injection_in_macos_osx_deep_dive/) — `CS_RESTRICT` フラグと DYLD の制限について解説しています
- [Endangered Technique: Using Environment Variables to Find Escaped Processes](https://medium.com/@captaindomestic/endangered-technique-using-environment-variables-to-find-escaped-processes-64eb7ff70602) — `KERN_PROCARGS2` の環境変数制限がセキュリティツールに与える影響を解説しています

### 関連する Issue / バグレポート

- [Emacs bug#48548](https://lists.gnu.org/archive/html/bug-gnu-emacs/2021-05/msg01652.html) — macOS でプロセス属性が取得できない問題の報告です
- [psutil #2189](https://github.com/giampaolo/psutil/issues/2189) — macOS での `cmdline()` が `NoSuchProcess` を返す問題です
- [Go #60047](https://github.com/golang/go/issues/60047) — `KERN_PROCARGS2` sysctl のバグ回避に関する議論です
