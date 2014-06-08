# 5章 システムコール

 * http://suneetsaini.blogspot.jp/2011/11/linux-system-call-operation-in-both.html
   * ここの図解が良さそう。 Linuxカーネル本と似てるne ...

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

    write(fd, "hoge", 4);
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

 * sigaction(2) と SA_RESTART でシグナルハンドラをセットしていてシグナルを受けた際の挙動の話
   * EINTR を返すか、システムコールを自動で再開するか否か
   * ERESTARTSYS

#### 検証用コード

別のセッションで `nc -l 8000` 等で適当なサーバを作って、下記のコードで繋いで検証する

 * SA_RESTART が有効だと SIGINT で割り込みを入れても recv(2) が自動で再開する
 * SA_RESTART が無効だと recv(2) が EINTR を返して終了する

strace で観測すると ↓ な感じになる 。 脇道だけど [sigreturn(2)](http://linuxjm.sourceforge.jp/html/LDP_man-pages/man2/sigreturn.2.html) なるシステムコールを知る

```
--- SIGINT (Interrupt) @ 0 (0) ---
rt_sigreturn(0x2)                       = 45
recvfrom(3, 0x7fff4b4f1460, 51, 0, 0, 0) = ? ERESTARTSYS (To be restarted)
--- SIGINT (Interrupt) @ 0 (0) ---
rt_sigreturn(0x2)                       = 45
recvfrom(3, 0x7fff4b4f1460, 51, 0, 0, 0) = ? ERESTARTSYS (To be restarted)
--- SIGINT (Interrupt) @ 0 (0) ---
rt_sigreturn(0x2)                       = 45
recvfrom(3, 
```

```c
 #if 0
#!/bin/bash
CFLAGS="-O2 -std=gnu99 -W -Wall -fPIE -D_FORTIFY_SOURCE=2"
o=`basename $0`
o=".${o%.*}"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

void handler_sighup(int __attribute__((__unused__)) sig)
{
	// unused の warning 止めるには これでも ok らしい
	// (void)sig;
}

int main(int argc, char *argv[])
{
	int sock;
	struct sockaddr_in sockaddr;
	char buffer[50+1];
	int port = 8000;

	if (argc == 2)
		port = atoi(argv[1]);
	
	memset(&sock, 0,sizeof(sock));

	sock = socket(AF_INET, SOCK_STREAM, 0);
	if (sock == -1) {
		perror("socket");
		exit(1);
	}

	sockaddr.sin_family = AF_INET;
	sockaddr.sin_port   = htons(port);
	inet_aton("127.0.0.1", &sockaddr.sin_addr);

	if (connect(sock, (struct sockaddr *)&sockaddr, sizeof(sockaddr))) {
		perror("connect");
		exit(2);
	}

	struct sigaction act;
	sigemptyset(&act.sa_mask);
	act.sa_handler = handler_sighup;
	act.sa_flags  |= SA_RESTART;
	if (sigaction(SIGINT, &act, NULL) == -1) {
		perror("sigaction");
		exit(3);
	}

	for(;;) {
		int ret;
		ret = recv(sock, buffer, 50+1, 0);

		if (ret == -1) {
			perror("recv");
			exit(4);
		}
		else if (ret == 0 ) {
			puts("closed");
			break;
		}
		else {
			printf("%s\n", buffer);
		}
	}
	
	exit(0);
}
```

