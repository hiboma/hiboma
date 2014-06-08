# 5章 システムコール

### コールゲート

> コールゲートはx86 アーキテクチャのCPUに搭載されたセキュリティ機構である。CALL命令による呼び出しで上位の特権レベルのコードをあらかじめ登録されたものに限って実行することができる。

> ハードウェアは、あるリングから別のリングへの制御の移動を厳密に制限している。また、メモリアクセスも各リングのレベルに応じて制限している。予め設定されたエントリポイントを通して特別な gate 命令や call 命令を使って、より高い特権レベルのリングに制御を移す（これをコールゲート方式などと呼ぶ）。多くのOSでこれに類似したシステムコール方式を採用している。このようなハードウェアによる制限は偶然や故意によるセキュリティ違反からシステムを守るために設計されている。さらに、最も高い特権レベルのリングには特別な機能が与えられている。例えば、仮想記憶をバイパスして物理メモリ空間にアクセスするといったことが可能である。

`call ***` で特権レベルの高いコードを実行できるのかな

タスクゲートはよう分からん


## 5.1.3 システムコールのインターフェイス

 * POSIX は関数のインターフェイスだけ規定。実装方法は規定ない

```c
	int fd = open("/mp/test.txt", O_WRONLY|O_CREAT, 0755);
	if(fd == -1 ) {
		fprintf(stderr, "failed to open(2): errno = %d, %s\n",
			errno, strerror(errno));
		exit(1);
	}
```

### システムコール番号とエントリテーブル

 * /usr/include/asm/unistd_32.h
 * /usr/include/asm/unistd_64.h

に番号と名前の一覧が載っている。カーネルだと

 * arch/x86/kernel/syscall_table_32.S
 * arch/x86/include/asm/unistd_64.h

に一覧が載っている。

perror(3) で errno と対応するメッセージが見れる。MySQLの依存コマンドだけど。

```console
$ perror 1
OS error code   1:  Operation not permitted

$ perror 2
OS error code   2:  No such file or directory

$ perror 4
OS error code   4:  Interrupted system call

$ perror 3
OS error code   3:  No such process
```

## 5.1.5 シグナルによる割り込み(システムコールの再起動とアボート)

EINTR の話

 * sigaction(2) SA_RESTART