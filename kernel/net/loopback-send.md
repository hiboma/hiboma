# loopback + sendto(2)

## ruby で UDP 飛ばす

```sh
ruby -rsocket -e 'p UDPSocket.new.send("aaaaa", 0, "127.0.0.1", 9999)';
```

strace とってみたら sendto(2) だった

```
sendto(3, "aaaaa", 5, 0, {sa_family=AF_INET, sin_port=htons(9999), sin_addr=inet_addr("127.0.0.1")}, 16) = 5
```

## send(2)

sys_send を呼ぶので、sendto(2) のラッパー扱い

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

	if (len > INT_MAX)
		len = INT_MAX;
	sock = sockfd_lookup_light(fd, &err, &fput_needed);
	if (!sock)
		goto out;

	iov.iov_base = buff;
	iov.iov_len = len;
	msg.msg_name = NULL;
	msg.msg_iov = &iov;
	msg.msg_iovlen = 1;
	msg.msg_control = NULL;
	msg.msg_controllen = 0;
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