## getperrname

## -ENOTCONN = Transport endpoint is not connected

検証用コード

```perl
#!/usr/bin/perl

use strict;
use warnings;
use Socket;

socket(my $socket, PF_INET, SOCK_DGRAM, 0) or die $!;
my $iaddr     = inet_aton('8.8.8.8');
my $sock_addr = pack_sockaddr_in(53, $iaddr);
send($socket, '', 0, $sock_addr);
my $peername  = getpeername($socket) or die $!;
```

#### result

```
$ LANG=C perl getpeername.pl
Transport endpoint is not connected at getpeername.pl line 11.
```

### connec(2) を入れてみると出ない

```perl
#!/usr/bin/perl

use strict;
use warnings;
use Socket;

socket(my $socket, PF_INET, SOCK_DGRAM, 0) or die $!;
my $iaddr     = inet_aton('8.8.8.8');
my $sock_addr = pack_sockaddr_in(53, $iaddr);

connect($socket, $sock_addr) or die $!;

send($socket, '', 0, $sock_addr);
my $peername  = getpeername($socket) or die $!;
```

connect(2) してないと getpeername()  -ENOTCONN 返すぽいな

## UDP で connect(2) を呼んだ際の副作用

 * http://www.kt.rim.or.jp/~ksk/sock-faq/unix-socket-faq-ja-5.html
   * 受信できるデータグラムを限定できる
   * ICMPエラーを受信できる

との情報ほむほむ

## getpeername の ソースを読むぞ

 * linux-2.6.32-431.el6.x86_64

getpeername の実装は struct socket の .proto_ops->getname に委譲している

```c
/*
 *	Get the remote address ('name') of a socket object. Move the obtained
 *	name to user space.
 */

SYSCALL_DEFINE3(getpeername, int, fd, struct sockaddr __user *, usockaddr,
		int __user *, usockaddr_len)
{
	struct socket *sock;
	struct sockaddr_storage address;
	int len, err, fput_needed;

	sock = sockfd_lookup_light(fd, &err, &fput_needed);
	if (sock != NULL) {
		err = security_socket_getpeername(sock);
		if (err) {
			fput_light(sock->file, fput_needed);
			return err;
		}

		err =
		    sock->ops->getname(sock, (struct sockaddr *)&address, &len,
				       1);
		if (!err)
			err = move_addr_to_user((struct sockaddr *)&address, len, usockaddr,
						usockaddr_len);
		fput_light(sock->file, fput_needed);
	}
	return err;
}
```

AF_INET + SOCK_DGRAM の場合 proto_ops は inet_dgram_ops だった

```c
const struct proto_ops inet_dgram_ops = {
	.family		   = PF_INET,
	.owner		   = THIS_MODULE,
	.release	   = inet_release,
	.bind		   = inet_bind,
	.connect	   = inet_dgram_connect,
	.socketpair	   = sock_no_socketpair,
	.accept		   = sock_no_accept,
	.getname	   = inet_getname,
	.poll		   = udp_poll,
	.ioctl		   = inet_ioctl,
	.listen		   = sock_no_listen,
	.shutdown	   = inet_shutdown,
	.setsockopt	   = sock_common_setsockopt,
	.getsockopt	   = sock_common_getsockopt,
	.sendmsg	   = inet_sendmsg,
	.recvmsg	   = inet_recvmsg,
	.mmap		   = sock_no_mmap,
	.sendpage	   = inet_sendpage,
#ifdef CONFIG_COMPAT
	.compat_setsockopt = compat_sock_common_setsockopt,
	.compat_getsockopt = compat_sock_common_getsockopt,
#endif
};
EXPORT_SYMBOL(inet_dgram_ops);
```

inet_getname の実装は下記の通り

 * -ENOTCONN を返すのは一カ所
   * sk->sk_state で TCPF_CLOSE, TCPF_SYN_SENT かどうかを見てるけど これ TCP だよなぁ
   * UDP はどうなるんだろう? ( 1 << sk->sk_state ) が返すフラグがどうなるのかな?
```c
/*
 *	This does both peername and sockname.
 */
int inet_getname(struct socket *sock, struct sockaddr *uaddr,
			int *uaddr_len, int peer)
{
	struct sock *sk		= sock->sk;
	struct inet_sock *inet	= inet_sk(sk);
	struct sockaddr_in *sin	= (struct sockaddr_in *)uaddr;

	sin->sin_family = AF_INET;
	if (peer) {
         // connect(2) してたら inet->dport が定義されてそうだ
		if (!inet->dport ||
		    (((1 << sk->sk_state) & (TCPF_CLOSE | TCPF_SYN_SENT)) &&
		     peer == 1))
			return -ENOTCONN;
		sin->sin_port = inet->dport;
		sin->sin_addr.s_addr = inet->daddr;
	} else {
		__be32 addr = inet->rcv_saddr;
		if (!addr)
			addr = inet->saddr;
		sin->sin_port = inet->sport;
		sin->sin_addr.s_addr = addr;
	}
	memset(sin->sin_zero, 0, sizeof(sin->sin_zero));
	*uaddr_len = sizeof(*sin);
	return 0;
}
EXPORT_SYMBOL(inet_getname);
```

## connect(2)

BSD -> AF_INET

```c
int inet_dgram_connect(struct socket *sock, struct sockaddr * uaddr,
		       int addr_len, int flags)
{
	struct sock *sk = sock->sk;

	if (uaddr->sa_family == AF_UNSPEC)
		return sk->sk_prot->disconnect(sk, flags);

	if (!inet_sk(sk)->num && inet_autobind(sk))
		return -EAGAIN;
	return sk->sk_prot->connect(sk, (struct sockaddr *)uaddr, addr_len);
}
EXPORT_SYMBOL(inet_dgram_connect);
```

BSD -> AF_INET -> UDP

```c
struct proto udp_prot = {
	.name		   = "UDP",
	.owner		   = THIS_MODULE,
	.close		   = udp_lib_close,
	.connect	   = ip4_datagram_connect,
	.disconnect	   = udp_disconnect,
	.ioctl		   = udp_ioctl,
	.destroy	   = udp_destroy_sock,
	.setsockopt	   = udp_setsockopt,
	.getsockopt	   = udp_getsockopt,
	.sendmsg	   = udp_sendmsg,
	.recvmsg	   = udp_recvmsg,
	.sendpage	   = udp_sendpage,
	.backlog_rcv	   = __udp_queue_rcv_skb,
	.hash		   = udp_lib_hash,
	.unhash		   = udp_lib_unhash,
	.get_port	   = udp_v4_get_port,
	.memory_allocated  = &udp_memory_allocated,
	.sysctl_mem	   = sysctl_udp_mem,
	.sysctl_wmem	   = &sysctl_udp_wmem_min,
	.sysctl_rmem	   = &sysctl_udp_rmem_min,
	.obj_size	   = sizeof(struct udp_sock),
	.slab_flags	   = SLAB_DESTROY_BY_RCU,
	.h.udp_table	   = &udp_table,
#ifdef CONFIG_COMPAT
	.compat_setsockopt = compat_udp_setsockopt,
	.compat_getsockopt = compat_udp_getsockopt,
#endif
};
EXPORT_SYMBOL(udp_prot);
```

```c
int ip4_datagram_connect(struct sock *sk, struct sockaddr *uaddr, int addr_len)
{
	struct inet_sock *inet = inet_sk(sk);
	struct sockaddr_in *usin = (struct sockaddr_in *) uaddr;
	struct rtable *rt;
	__be32 saddr;
	int oif;
	int err;


	if (addr_len < sizeof(*usin))
		return -EINVAL;

	if (usin->sin_family != AF_INET)
		return -EAFNOSUPPORT;

    // 送信キューを空にする
    // struct dst_entry (sk->sk_dst_cache) を NULL にする
    // ルーティンブテーブル?
    // http://www.mars.dti.ne.jp/~otk/bak/200110-linuxkernel24.pdf
	sk_dst_reset(sk);

	oif = sk->sk_bound_dev_if;
	saddr = inet->saddr;
	if (ipv4_is_multicast(usin->sin_addr.s_addr)) {
		if (!oif)
			oif = inet->mc_index;
		if (!saddr)
			saddr = inet->mc_addr;
	}

    // ip_route_output_flow
    // __xfrm_lookup
	err = ip_route_connect(&rt, usin->sin_addr.s_addr, saddr,
			       RT_CONN_FLAGS(sk), oif,
			       sk->sk_protocol,
			       inet->sport, usin->sin_port, sk, 1);
	if (err) {
		if (err == -ENETUNREACH)
			IP_INC_STATS_BH(sock_net(sk), IPSTATS_MIB_OUTNOROUTES);
		return err;
	}

	if ((rt->rt_flags & RTCF_BROADCAST) && !sock_flag(sk, SOCK_BROADCAST)) {
		ip_rt_put(rt);
		return -EACCES;
	}
	if (!inet->saddr)
		inet->saddr = rt->rt_src;	/* Update source address */
	if (!inet->rcv_saddr)
		inet->rcv_saddr = rt->rt_src;

    // dst の addr と port をセット
	inet->daddr = rt->rt_dst;
	inet->dport = usin->sin_port;

    // UDP なのに TCP_ESTABLISHED だ！
	sk->sk_state = TCP_ESTABLISHED;
	inet->id = jiffies;

    // sk->sk_dst_cache を更新
	sk_dst_set(sk, &rt->u.dst);
	return(0);
}

EXPORT_SYMBOL(ip4_datagram_connect);
```