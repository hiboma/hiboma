# UNIX Domain Socket

## AF_UNIX + SOCK_STREAM

 * connect(2) して unix_recvq_full で溢れたソケットの数は `LISTENING の ref count - 2` で出る
 * CONNECTING は sk_receive_queue に入ったけれど accept(2) されていない ソケット
   * inode がふられていない
 
```
unix  7      [ ACC ]     STREAM     LISTENING     67612  /tmp/unix.sock
unix  2      [ ]         STREAM     CONNECTING    0      /tmp/unix.sock
unix  2      [ ]         STREAM     CONNECTED     67614  /tmp/unix.sock
```

```c
static int unix_stream_connect(struct socket *sock, struct sockaddr *uaddr,
			       int addr_len, int flags)
{

// ...

	if (unix_recvq_full(other)) {
		err = -EAGAIN;
		if (!timeo)
			goto out_unlock;

		timeo = unix_wait_for_peer(other, timeo);

		err = sock_intr_errno(timeo);
		if (signal_pending(current))
			goto out;
		sock_put(other);
		goto restart;
	}
```

## connect(2) と setsockopt(2) の SO_SNDTIMEO

setsockopt で SO_SNDTIMEO を指定すると connect のタイムアウトを指定できる

 * setsockopt は sk->sk_sndtimeo の数値

#### 検証用クライアント

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
#include <stdbool.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <err.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>

int main()
{
	int sock;
	struct sockaddr_un addr;
	bzero(&addr, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strcpy(addr.sun_path, "/tmp/unix.sock");

	sock = socket(PF_UNIX, SOCK_STREAM, 0);
	if (sock == -1) {
		perror("socket");
		exit(1);
	}

	struct timeval tv;
	tv.tv_sec  = 100.;
	tv.tv_usec = 0;

	if (setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (char *)&tv, sizeof(tv))) {
		perror("setsockopt");
	};

	/* バックログ (sock->sk_recvqueue が溢れている際に) ブロックする */
	if (connect(sock, (struct sockaddr *)&addr, sizeof(addr))) {
		perror("connect");
		exit(1);
	}

	fprintf(stderr, "connected\n");

	char buffer[128];
	if (recv(sock, buffer, 128, 0) == -1) {
		perror("recv");
	}
	
	exit(0);
}
```

#### 適当なサーバ

```c
#if 0
#!/bin/bash
CFLAGS="-O2 -std=gnu99 -W -Wall -fPIE -D_FORTIFY_SOURCE=2"
o=`basename $0`
o=".${o%.*}"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#include <stdio.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/types.h>
#include <unistd.h>
#include <string.h>

int main(void)
{
	struct sockaddr_un address;
	int socket_fd;
	
	socket_fd = socket(PF_UNIX, SOCK_STREAM, 0);
	if(socket_fd < 0) {
		printf("socket() failed\n");
		return 1;
	}

	unlink("/tmp/unix.sock");

	/* start with a clean address structure */
	memset(&address, 0, sizeof(struct sockaddr_un));

	address.sun_family = AF_UNIX;
	snprintf(address.sun_path, 50, "/tmp/unix.sock");

	if(bind(socket_fd, (struct sockaddr *)&address, sizeof(struct sockaddr_un)) != 0) {			printf("bind() failed\n");
		return 1;
	}

	/* backlog + 1 をブロックする */
	if(listen(socket_fd, 0) != 0) {
		printf("listen() failed\n");
		return 1;
	}

	struct sockaddr_un client;
	socklen_t addrlen;
	memset(&client, 0, sizeof(struct sockaddr_un));
		
	accept(socket_fd, (struct sockaddr *)&client, &addrlen);
	
	pause();
	return 0;
}
```