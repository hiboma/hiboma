# loopback + sendto(2)

## ruby で UDP 飛ばす

AF_INET で loopback address にパケットを飛ばします

```sh
ruby -rsocket -e 'p UDPSocket.new.send("aaaaa", 0, "127.0.0.1", 9999)';
```

send(2) を呼び出すのかと strace とってみたら sendto(2) だった!

```
socket(PF_INET, SOCK_DGRAM, IPPROTO_IP) = 3
sendto(3, "aaaaa", 5, 0, {sa_family=AF_INET, sin_port=htons(9999), sin_addr=inet_addr("127.0.0.1")}, 16) = 5
```

## send(2)

sys_send を呼びだしているので sendto(2) のラッパー扱い

```c
/*
 *	Send a datagram down a socket.
 */

SYSCALL_DEFINE4(send, int, fd, void __user *, buff, size_t, len,
		unsigned, flags)
{
	return sys_sendto(fd, buff, len, flags, NULL, 0);
}
```

## sendto(2)

```c
/*
 *	Send a datagram to a given address. We move the address into kernel
 *	space and check the user space data area is readable before invoking
 *	the protocol.
 */

SYSCALL_DEFINE6(sendto, int, fd, void __user *, buff, size_t, len,
		unsigned, flags, struct sockaddr __user *, addr,
		int, addr_len)
{
	struct socket *sock;
	struct sockaddr_storage address;
	int err;
	struct msghdr msg;
	struct iovec iov;
	int fput_needed;

    /* 長さの上限あるよー */
	if (len > INT_MAX)
		len = INT_MAX;

    /* fd -> struct file -> struct sock の変換 */
	sock = sockfd_lookup_light(fd, &err, &fput_needed);
	if (!sock)
		goto out;

    /* struct iovec ベクタにバッファの中身を寄せる */
    //    struct iovec
    //{
    //	void __user *iov_base;	/* BSD uses caddr_t (1003.1g requires void *) */
    //	__kernel_size_t iov_len; /* Must be size_t (1003.1g) */
    //};
    //
	iov.iov_base = buff;
	iov.iov_len = len;
	msg.msg_name = NULL;
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;
	msg.msg_control = NULL; // 制御情報。うーん
	msg.msg_controllen = 0; // 制御情報の長さ
	msg.msg_namelen = 0;
	if (addr) {
		err = move_addr_to_kernel(addr, addr_len, (struct sockaddr *)&address);
		if (err < 0)
			goto out_put;
		msg.msg_name = (struct sockaddr *)&address;
		msg.msg_namelen = addr_len;
	}
	if (sock->file->f_flags & O_NONBLOCK)
		flags |= MSG_DONTWAIT;
	msg.msg_flags = flags;
	err = sock_sendmsg(sock, &msg, len);

out_put:
	fput_light(sock->file, fput_needed);
out:
	return err;
}
```