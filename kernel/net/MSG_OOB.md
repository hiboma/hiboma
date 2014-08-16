# MSG_OOB

## Message Out Of Band Data

利用方法が謎なやつ

```c
#include <sys/types.h>
#include <sys/socket.h>

ssize_t recv(int sockfd, void *buf, size_t len, int flags);

ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
                 struct sockaddr *src_addr, socklen_t *addrlen);

ssize_t recvmsg(int sockfd, struct msghdr *msg, int flags);
```

man recv の説明に下記の通り

```
MSG_OOB
このフラグは、通常のデータ・ストリームでは受信できない 帯域外 (out-of-band) データの受信を要求する。 プロトコルによっては、 通常のデータ・キューの先頭に速達データを置くものがあるが、 そのようなプロトコルではこのフラグは使用できない。
```

## UDP の場合

送信で EOPNOTSUPP を返す。受信でもシカトされてそう

```c
int udp_sendmsg(struct kiocb *iocb, struct sock *sk, struct msghdr *msg,
		size_t len)
{

//...
	if (msg->msg_flags & MSG_OOB) /* Mirror BSD error message compatibility */
		return -EOPNOTSUPP;
```
