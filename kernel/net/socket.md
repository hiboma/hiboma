
 * AF_UNIX + SOCK_STREAM
 * AF_UNIX + SOCK_DGRAM
 * AF_UNIX + SOCK_SEQPACKET
 

  type     | usage
-----------|---------------------
struct proto_ops | sock->ops->method()


## AF_UNIX + SOCK_STREAM

```
static const struct proto_ops unix_stream_ops = {
	.family =	PF_UNIX,
	.owner =	THIS_MODULE,
	.release =	unix_release,
	.bind =		unix_bind,
	.connect =	unix_stream_connect,
	.socketpair =	unix_socketpair,
	.accept =	unix_accept,
	.getname =	unix_getname,
	.poll =		unix_poll,
	.ioctl =	unix_ioctl,
	.listen =	unix_listen,
	.shutdown =	unix_shutdown,
	.setsockopt =	sock_no_setsockopt,
	.getsockopt =	sock_no_getsockopt,
	.sendmsg =	unix_stream_sendmsg,
	.recvmsg =	unix_stream_recvmsg,
	.mmap =		sock_no_mmap,
	.sendpage =	sock_no_sendpage,
};
```

## AF_UNIX + SOCK_DGRAM

```
static const struct proto_ops unix_dgram_ops = {
	.family =	PF_UNIX,
	.owner =	THIS_MODULE,
	.release =	unix_release,
	.bind =		unix_bind,
	.connect =	unix_dgram_connect,
	.socketpair =	unix_socketpair,
	.accept =	sock_no_accept,
	.getname =	unix_getname,
	.poll =		unix_dgram_poll,
	.ioctl =	unix_ioctl,
	.listen =	sock_no_listen,
	.shutdown =	unix_shutdown,
	.setsockopt =	sock_no_setsockopt,
	.getsockopt =	sock_no_getsockopt,
	.sendmsg =	unix_dgram_sendmsg,
	.recvmsg =	unix_dgram_recvmsg,
	.mmap =		sock_no_mmap,
	.sendpage =	sock_no_sendpage,
};
```

## AF_UNIX + SOCK_SEQPACKET?

```
static const struct proto_ops unix_seqpacket_ops = {
	.family =	PF_UNIX,
	.owner =	THIS_MODULE,
	.release =	unix_release,
	.bind =		unix_bind,
	.connect =	unix_stream_connect,
	.socketpair =	unix_socketpair,
	.accept =	unix_accept,
	.getname =	unix_getname,
	.poll =		unix_dgram_poll,
	.ioctl =	unix_ioctl,
	.listen =	unix_listen,
	.shutdown =	unix_shutdown,
	.setsockopt =	sock_no_setsockopt,
	.getsockopt =	sock_no_getsockopt,
	.sendmsg =	unix_seqpacket_sendmsg,
	.recvmsg =	unix_seqpacket_recvmsg,
	.mmap =		sock_no_mmap,
	.sendpage =	sock_no_sendpage,
};
```

