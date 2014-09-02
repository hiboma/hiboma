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

    /* struct addr をユーザ空間からコピー */
	if (addr) {
		err = move_addr_to_kernel(addr, addr_len, (struct sockaddr *)&address);
		if (err < 0)
			goto out_put;

        // フィールド msg_name は、 未接続のソケットでデータグラムの宛先アドレスを指定するのに使用される
        // (refs man 2 send http://linuxjm.sourceforge.jp/html/LDP_man-pages/man2/send.2.html )
		msg.msg_name = (struct sockaddr *)&address;
		msg.msg_namelen = addr_len;
	}

    /* O_NONBLOCK は MSG_DONTWAIT てなフラグに変わってとられる */
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

## sock_sendmsg

```c
int sock_sendmsg(struct socket *sock, struct msghdr *msg, size_t size)
{
	struct kiocb iocb;
	struct sock_iocb siocb;
	int ret;

	init_sync_kiocb(&iocb, NULL);
	iocb.private = &siocb;
	ret = __sock_sendmsg(&iocb, sock, msg, size);
	if (-EIOCBQUEUED == ret)
		ret = wait_on_sync_kiocb(&iocb);
	return ret;
}
```

## __sock_sendmsg

```c
static inline int __sock_sendmsg(struct kiocb *iocb, struct socket *sock,
				 struct msghdr *msg, size_t size)
{
	int err = security_socket_sendmsg(sock, msg, size);

	return err ?: __sock_sendmsg_nosec(iocb, sock, msg, size);
}
```

## __sock_sendmsg_nosec

```c
static inline int __sock_sendmsg_nosec(struct kiocb *iocb, struct socket *sock,
				       struct msghdr *msg, size_t size)
{
	struct sock_iocb *si = kiocb_to_siocb(iocb);

	sock_update_classid(sock->sk);

	sock_update_netprioidx(sock->sk);

	si->sock = sock;
	si->scm = NULL;
	si->msg = msg;
	si->size = size;

	return sock->ops->sendmsg(iocb, sock, msg, size);
}
```

ここまでが BSDソケット層? これ以降はプロトコルによって実装がことなる

# AF_INET + SOCK_DGRAM = UDP

UDP の struct proto は以下の通りに定義されている

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

## udp_sendmsg

```c
int udp_sendmsg(struct kiocb *iocb, struct sock *sk, struct msghdr *msg,
		size_t len)
{
	struct inet_sock *inet = inet_sk(sk);
	struct udp_sock *up = udp_sk(sk);
	int ulen = len;
	struct ipcm_cookie ipc;
	struct rtable *rt = NULL;
	int free = 0;
	int connected = 0;
	__be32 daddr, faddr, saddr;
	__be16 dport;
	u8  tos;
	int err, is_udplite = IS_UDPLITE(sk);
	int corkreq = up->corkflag || msg->msg_flags&MSG_MORE;
	int (*getfrag)(void *, char *, int, int, int, struct sk_buff *);
	struct sk_buff *skb;
	struct ip_options_data opt_copy;

    /* メッセージサイズがデカ杉ナリよ */
	if (len > 0xFFFF)
		return -EMSGSIZE;

	/*
	 *	Check the flags.
	 */

    /* UDP では帯域外データをサポートしない */
	if (msg->msg_flags & MSG_OOB) /* Mirror BSD error message compatibility */
		return -EOPNOTSUPP;

	ipc.opt = NULL;
	ipc.shtx.flags = 0;

	getfrag = is_udplite ? udplite_getfrag : ip_generic_getfrag;

	if (up->pending) {
		/*
		 * There are pending frames.
		 * The socket lock must be held while it's corked.
		 */
		lock_sock(sk);
		if (likely(up->pending)) {
			if (unlikely(up->pending != AF_INET)) {
				release_sock(sk);
				return -EINVAL;
			}
			goto do_append_data;
		}
		release_sock(sk);
	}
	ulen += sizeof(struct udphdr);

	/*
	 *	Get and verify the address.
	 */
     // AF_INET な場合 msg_name には struct sock_addr_in が入っている */
	if (msg->msg_name) {

        // アドレスのバリデーション
		struct sockaddr_in * usin = (struct sockaddr_in *)msg->msg_name;
		if (msg->msg_namelen < sizeof(*usin))
			return -EINVAL;
		if (usin->sin_family != AF_INET) {
			if (usin->sin_family != AF_UNSPEC)
				return -EAFNOSUPPORT;
		}

        // 送信先ターゲットの IP
		daddr = usin->sin_addr.s_addr;
        // 送信先ターゲットの ポート
		dport = usin->sin_port;
        // 0 番は不正ナリよ
        // dport の上限みてないよね???
		if (dport == 0)
			return -EINVAL;
	} else {

        // connect して TCP_ESTABLISHED 済みでない場合に struct address を省略して
        // sendmsg を呼び出すことができるぽい
		if (sk->sk_state != TCP_ESTABLISHED)
			return -EDESTADDRREQ;
		daddr = inet->daddr;
		dport = inet->dport;
		/* Open fast path for connected socket.
		   Route will not be used, if at least one option is set.
		 */
		connected = 1;
	}

    // うーん???
    // NULL である可能性は?
	ipc.addr = inet->saddr;

	ipc.oif = sk->sk_bound_dev_if;
	err = sock_tx_timestamp(msg, sk, &ipc.shtx);
	if (err)
		return err;

    // 制御情報がうんたら
	if (msg->msg_controllen) {
		err = ip_cmsg_send(sock_net(sk), msg, &ipc);
		if (err)
			return err;
		if (ipc.opt)
			free = 1;
		connected = 0;
	}
	if (!ipc.opt) {
		struct ip_options *inet_opt;

		rcu_read_lock();
		inet_opt = rcu_dereference(inet->opt);
		if (inet_opt) {
			memcpy(&opt_copy, inet_opt,
			       sizeof(*inet_opt) + inet_opt->optlen);
			ipc.opt = &opt_copy.opt;
		}
		rcu_read_unlock();
	}

    // ソースアドレス
	saddr = ipc.addr;

    // 送信先アドレス
	ipc.addr = faddr = daddr;

    // ???
	if (ipc.opt && ipc.opt->srr) {
		if (!daddr)
			return -EINVAL;
		faddr = ipc.opt->faddr;
		connected = 0;
	}

    // ???
	tos = RT_TOS(inet->tos);
	if (sock_flag(sk, SOCK_LOCALROUTE) ||
	    (msg->msg_flags & MSG_DONTROUTE) ||
	    (ipc.opt && ipc.opt->is_strictroute)) {
		tos |= RTO_ONLINK;
		connected = 0;
	}

    // マルチキャスト
	if (ipv4_is_multicast(daddr)) {
		if (!ipc.oif)
			ipc.oif = inet->mc_index;
		if (!saddr)
			saddr = inet->mc_addr;
		connected = 0;
	}

	if (connected)
		rt = (struct rtable *)sk_dst_check(sk, 0);

    // ルーティングテーブルが無かったらルーティング先を決める
    //
    // struct flowi はマクロでアクセサが定義されているので、読む際に注意
    //
    //     #define fl4_dst		nl_u.ip4_u.daddr
    //     #define fl4_src		nl_u.ip4_u.saddr
    //     #define fl4_tos		nl_u.ip4_u.tos
    //     #define fl4_scope	nl_u.ip4_u.scope
    //
	if (rt == NULL) {
		struct flowi fl = { .oif = ipc.oif,
				    .mark = sk->sk_mark,
				    .nl_u = { .ip4_u =
					      { .daddr = faddr,
						.saddr = saddr,
						.tos = tos } },
				    .proto = sk->sk_protocol,
				    .flags = inet_sk_flowi_flags(sk),
				    .uli_u = { .ports =
					       { .sport = inet->sport,
						 .dport = dport } } };
		struct net *net = sock_net(sk);

		security_sk_classify_flow(sk, &fl);
        // ここでルーティングテーブルが決定される
		err = ip_route_output_flow(net, &rt, &fl, sk, 1);
		if (err) {
			if (err == -ENETUNREACH)
				IP_INC_STATS_BH(net, IPSTATS_MIB_OUTNOROUTES);
			goto out;
		}

		err = -EACCES;
		if ((rt->rt_flags & RTCF_BROADCAST) &&
		    !sock_flag(sk, SOCK_BROADCAST))
			goto out;
		if (connected)
			sk_dst_set(sk, dst_clone(&rt->u.dst));
	}

	if (msg->msg_flags&MSG_CONFIRM)
		goto do_confirm;
back_from_confirm:

    // ip_route_output_flow で決まった ソースアドレス
	saddr = rt->rt_src;

    // ??? 
	if (!ipc.addr)
        // ルーティングテーブルから送信先アドレスを決める
		daddr = ipc.addr = rt->rt_dst;

	/* Lockless fast path for the non-corking case. */
	if (!corkreq) {
		skb = ip_make_skb(sk, getfrag, msg->msg_iov, ulen,
				  sizeof(struct udphdr), &ipc, &rt,
				  msg->msg_flags);
		err = PTR_ERR(skb);

        // ここで UDPパケット (skb) を飛ばす
		if (skb && !IS_ERR(skb))
			err = udp_send_skb(skb, daddr, dport);
		goto out;
	}

    // ここからはペンヂングするケースの場合
	lock_sock(sk);
	if (unlikely(up->pending)) {
		/* The socket is already corked while preparing it. */
		/* ... which is an evident application bug. --ANK */
		release_sock(sk);

		LIMIT_NETDEBUG(KERN_DEBUG "udp cork app bug 2\n");
		err = -EINVAL;
		goto out;
	}
	/*
	 *	Now cork the socket to pend data.
	 */
    // cork する条件が分からん。ペンディングしておく
	inet->cork.fl.fl4_dst = daddr;
	inet->cork.fl.fl_ip_dport = dport;
	inet->cork.fl.fl4_src = saddr;
	inet->cork.fl.fl_ip_sport = inet->sport;
	up->pending = AF_INET;

do_append_data:
	up->len += ulen;
	err = ip_append_data(sk, getfrag, msg->msg_iov, ulen,
			sizeof(struct udphdr), &ipc, &rt,
			corkreq ? msg->msg_flags|MSG_MORE : msg->msg_flags);
	if (err)
		udp_flush_pending_frames(sk);
	else if (!corkreq)
		err = udp_push_pending_frames(sk);
	else if (unlikely(skb_queue_empty(&sk->sk_write_queue)))
		up->pending = 0;
	release_sock(sk);

out:
	ip_rt_put(rt);
	if (free)
		kfree_ip_options(ipc.opt);
	if (!err)
		return len;
	/*
	 * ENOBUFS = no kernel mem, SOCK_NOSPACE = no sndbuf space.  Reporting
	 * ENOBUFS might not be good (it's not tunable per se), but otherwise
	 * we don't have a good statistic (IpOutDiscards but it can be too many
	 * things).  We could add another new stat but at least for now that
	 * seems like overkill.
	 */
	if (err == -ENOBUFS || test_bit(SOCK_NOSPACE, &sk->sk_socket->flags)) {
		UDP_INC_STATS_USER(sock_net(sk),
				UDP_MIB_SNDBUFERRORS, is_udplite);
	}
	return err;

do_confirm:
	dst_confirm(&rt->u.dst);
	if (!(msg->msg_flags&MSG_PROBE) || len)
		goto back_from_confirm;
	err = 0;
	goto out;
}
EXPORT_SYMBOL(udp_sendmsg);
```

----

# IPルーティング

## ip_route_output_flow

## __ip_route_output_key

 * `rt_caching(net)` で ルーティングテーブルのキャッシュを参照するかどうかを決定
 * キャッシュを見ない場合は ip_route_output_slow

```c
int __ip_route_output_key(struct net *net, struct rtable **rp,
			  const struct flowi *flp)
{
	unsigned hash;
	struct rtable *rth;

	if (!rt_caching(net))
		goto slow_output;

    // 宛先アドレス、ソースアドレス、インタフェースのインデックス値、 ??? でハッシュ値取る
	hash = rt_hash(flp->fl4_dst, flp->fl4_src, flp->oif, rt_genid(net));

	rcu_read_lock_bh();

    // rt_hash_table = rtable のキャッシュ = ルーティングのキャッシュ
    // RCU で保護しながら探索
	for (rth = rcu_dereference(rt_hash_table[hash].chain); rth;
		rth = rcu_dereference(rth->u.dst.rt_next)) {
		if (rth->fl.fl4_dst == flp->fl4_dst &&
		    rth->fl.fl4_src == flp->fl4_src &&
		    rth->fl.iif == 0 &&
		    rth->fl.oif == flp->oif &&
		    rth->fl.mark == flp->mark &&
		    !((rth->fl.fl4_tos ^ flp->fl4_tos) &
			    (IPTOS_RT_MASK | RTO_ONLINK)) &&
		    net_eq(dev_net(rth->u.dst.dev), net) &&
		    !rt_is_expired(rth)) {
            // ???
			dst_use(&rth->u.dst, jiffies);
            // キャッシュヒットの統計
            // /proc/net/stat/rt_cache で参照できる
			RT_CACHE_STAT_INC(out_hit);
			rcu_read_unlock_bh();
			*rp = rth;
			return 0;
		}
        // キャッシュ探索した回数の統計
        // /proc/net/stat/rt_cache で参照できる
		RT_CACHE_STAT_INC(out_hlist_search);
	}
	rcu_read_unlock_bh();

slow_output:
	return ip_route_output_slow(net, rp, flp);
}
``` 

## ip_route_output_slow

rtable を探索する

```c
/*
 * Major route resolver routine.
 */

static int ip_route_output_slow(struct net *net, struct rtable **rp,
				const struct flowi *oldflp)
{
	u32 tos	= RT_FL_TOS(oldflp);
	struct flowi fl = { .nl_u = { .ip4_u =
				      { .daddr = oldflp->fl4_dst,
					.saddr = oldflp->fl4_src,
					.tos = tos & IPTOS_RT_MASK,
					.scope = ((tos & RTO_ONLINK) ?
						  RT_SCOPE_LINK :
						  RT_SCOPE_UNIVERSE),
				      } },
			    .mark = oldflp->mark,
			    .iif = net->loopback_dev->ifindex,
			    .oif = oldflp->oif };
	struct fib_result res;
	unsigned flags = 0;
	struct net_device *dev_out = NULL;
	int free_res = 0;
	int err;


	res.fi		= NULL;
#ifdef CONFIG_IP_MULTIPLE_TABLES
	res.r		= NULL;
#endif

	/* udp_sendmsg の saddr のこと */
	if (oldflp->fl4_src) {
		err = -EINVAL;
		if (ipv4_is_multicast(oldflp->fl4_src) ||
		    ipv4_is_lbcast(oldflp->fl4_src) ||
		    ipv4_is_zeronet(oldflp->fl4_src))
			goto out;

		/* I removed check for oif == dev_out->oif here.
		   It was wrong for two reasons:
		   1. ip_dev_find(net, saddr) can return wrong iface, if saddr
		      is assigned to multiple interfaces.
		   2. Moreover, we are allowed to send packets with saddr
		      of another iface. --ANK
		 */

		if (oldflp->oif == 0
		    && (ipv4_is_multicast(oldflp->fl4_dst) ||
			oldflp->fl4_dst == htonl(0xFFFFFFFF))) {
			/* It is equivalent to inet_addr_type(saddr) == RTN_LOCAL */
			dev_out = ip_dev_find(net, oldflp->fl4_src);
			if (dev_out == NULL)
				goto out;

			/* Special hack: user can direct multicasts
			   and limited broadcast via necessary interface
			   without fiddling with IP_MULTICAST_IF or IP_PKTINFO.
			   This hack is not just for fun, it allows
			   vic,vat and friends to work.
			   They bind socket to loopback, set ttl to zero
			   and expect that it will work.
			   From the viewpoint of routing cache they are broken,
			   because we are not allowed to build multicast path
			   with loopback source addr (look, routing cache
			   cannot know, that ttl is zero, so that packet
			   will not leave this host and route is valid).
			   Luckily, this hack is good workaround.
			 */

			fl.oif = dev_out->ifindex;
			goto make_route;
		}

		if (!(oldflp->flags & FLOWI_FLAG_ANYSRC)) {
			/* It is equivalent to inet_addr_type(saddr) == RTN_LOCAL */
			dev_out = ip_dev_find(net, oldflp->fl4_src);
			if (dev_out == NULL)
				goto out;
			dev_put(dev_out);
			dev_out = NULL;
		}
	}


	if (oldflp->oif) {
		dev_out = dev_get_by_index(net, oldflp->oif);
		err = -ENODEV;
		if (dev_out == NULL)
			goto out;

		/* RACE: Check return value of inet_select_addr instead. */
		if (__in_dev_get_rtnl(dev_out) == NULL) {
			dev_put(dev_out);
			goto out;	/* Wrong error code */
		}

		if (ipv4_is_local_multicast(oldflp->fl4_dst) ||
		    oldflp->fl4_dst == htonl(0xFFFFFFFF)) {
			if (!fl.fl4_src)
				fl.fl4_src = inet_select_addr(dev_out, 0,
							      RT_SCOPE_LINK);
			goto make_route;
		}
		if (!fl.fl4_src) {
			if (ipv4_is_multicast(oldflp->fl4_dst))
				fl.fl4_src = inet_select_addr(dev_out, 0,
							      fl.fl4_scope);
			else if (!oldflp->fl4_dst)
				fl.fl4_src = inet_select_addr(dev_out, 0,
							      RT_SCOPE_HOST);
		}
	}

	/* udp_sendmsg での daddr のこと */
	/* fl4_src も fl4_dst も無い状態ってどんなん呼び出し? */
	if (!fl.fl4_dst) {
		fl.fl4_dst = fl.fl4_src;
		if (!fl.fl4_dst)
			fl.fl4_dst = fl.fl4_src = htonl(INADDR_LOOPBACK);
		if (dev_out)
			dev_put(dev_out);
		dev_out = net->loopback_dev;
		dev_hold(dev_out);
		fl.oif = net->loopback_dev->ifindex;
		res.type = RTN_LOCAL;
		flags |= RTCF_LOCAL;

        // ルーティングテーブル作る
		goto make_route;
	}

	/* ここで探す */
	if (fib_lookup(net, &fl, &res)) {
		res.fi = NULL;
		if (oldflp->oif) {
			/* Apparently, routing tables are wrong. Assume,
			   that the destination is on link.

			   WHY? DW.
			   Because we are allowed to send to iface
			   even if it has NO routes and NO assigned
			   addresses. When oif is specified, routing
			   tables are looked up with only one purpose:
			   to catch if destination is gatewayed, rather than
			   direct. Moreover, if MSG_DONTROUTE is set,
			   we send packet, ignoring both routing tables
			   and ifaddr state. --ANK


			   We could make it even if oif is unknown,
			   likely IPv6, but we do not.
			 */

			if (fl.fl4_src == 0)
				fl.fl4_src = inet_select_addr(dev_out, 0,
							      RT_SCOPE_LINK);
			res.type = RTN_UNICAST;
			goto make_route;
		}
		if (dev_out)
			dev_put(dev_out);
		err = -ENETUNREACH;
		goto out;
	}
	free_res = 1;

	// loopback アドレスを選択する際のルーティング
	if (res.type == RTN_LOCAL) {
		if (!fl.fl4_src)
			fl.fl4_src = fl.fl4_dst;
		if (dev_out)
			dev_put(dev_out);
		dev_out = net->loopback_dev;
		dev_hold(dev_out);
		fl.oif = dev_out->ifindex;
		if (res.fi)
			fib_info_put(res.fi);
		res.fi = NULL;
		flags |= RTCF_LOCAL;
		goto make_route;
	}

#ifdef CONFIG_IP_ROUTE_MULTIPATH
	if (res.fi->fib_nhs > 1 && fl.oif == 0)
		fib_select_multipath(&fl, &res);
	else
#endif
	if (!res.prefixlen && res.type == RTN_UNICAST && !fl.oif)
		fib_select_default(net, &fl, &res);

	if (!fl.fl4_src)
		fl.fl4_src = FIB_RES_PREFSRC(res);

	if (dev_out)
		dev_put(dev_out);
	dev_out = FIB_RES_DEV(res);
	dev_hold(dev_out);
	fl.oif = dev_out->ifindex;


make_route:
	err = ip_mkroute_output(rp, &res, &fl, oldflp, dev_out, flags);


	if (free_res)
		fib_res_put(&res);
	if (dev_out)
		dev_put(dev_out);
out:	return err;
}
```

 * 探索結果が RTN_LOCAL なら loopback インタフェースを dev_out ( fl.oif )に選択する
 * ip_mkroute_output で rtable をキャッシュする

## ip_mkroute_output

```c
static int ip_mkroute_output(struct rtable **rp,
			     struct fib_result *res,
			     const struct flowi *fl,
			     const struct flowi *oldflp,
			     struct net_device *dev_out,
			     unsigned flags)
{
	struct rtable *rth = NULL;
	int err = __mkroute_output(&rth, res, fl, oldflp, dev_out, flags);
	unsigned hash;
	if (err == 0) {
		hash = rt_hash(oldflp->fl4_dst, oldflp->fl4_src, oldflp->oif,
			       rt_genid(dev_net(dev_out)));
		err = rt_intern_hash(hash, rth, rp, NULL);
	}

	return err;
}
```

### __mkroute_output

```c
static int __mkroute_output(struct rtable **result,
			    struct fib_result *res,
			    const struct flowi *fl,
			    const struct flowi *oldflp,
			    struct net_device *dev_out,
			    unsigned flags)
{
	struct rtable *rth;
	struct in_device *in_dev;
	u32 tos = RT_FL_TOS(oldflp);
	int err = 0;

	if (fl->fl4_dst == htonl(0xFFFFFFFF))
		res->type = RTN_BROADCAST;
	else if (ipv4_is_multicast(fl->fl4_dst))
		res->type = RTN_MULTICAST;
	else if (ipv4_is_lbcast(fl->fl4_dst) || ipv4_is_zeronet(fl->fl4_dst))
		return -EINVAL;

	if (dev_out->flags & IFF_LOOPBACK)
		flags |= RTCF_LOCAL;

//...

	if (flags & RTCF_LOCAL) {
		rth->u.dst.input = ip_local_deliver;
		rth->rt_spec_dst = fl->fl4_dst;
	}
```

## fib_lookup

```c
int fib_lookup(struct net *net, struct flowi *flp, struct fib_result *res)
{
	struct fib_lookup_arg arg = {
		.result = res,
	};
	int err;

	err = fib_rules_lookup(net->ipv4.rules_ops, flp, 0, &arg);
	res->r = arg.rule;

	return err;
}
```

## fib_rules_lookup

```c
int fib_rules_lookup(struct fib_rules_ops *ops, struct flowi *fl,
		     int flags, struct fib_lookup_arg *arg)
{
	struct fib_rule *rule;
	int err;

	rcu_read_lock();

    /* マッチする fib_rule を探す ??? */
	list_for_each_entry_rcu(rule, &ops->rules_list, list) {
jumped:
		if (!fib_rule_match(rule, ops, fl, flags))
			continue;

		if (rule->action == FR_ACT_GOTO) {
			struct fib_rule *target;

			target = rcu_dereference(rule->ctarget);
			if (target == NULL) {
				continue;
			} else {
				rule = target;
				goto jumped;
			}
		} else if (rule->action == FR_ACT_NOP)
			continue;
		else
            /* fib_rule に応じた action を呼び出す */
			err = ops->action(rule, fl, flags, arg);

		if (err != -EAGAIN) {
			fib_rule_get(rule);
			arg->rule = rule;
			goto out;
		}
	}

	err = -ESRCH;
out:
	rcu_read_unlock();

	return err;
}
```

#### fib_rules_lookup で使われるメソッド群

```c
static struct fib_rules_ops fib4_rules_ops_template = {
	.family		= AF_INET,
	.rule_size	= sizeof(struct fib4_rule),
	.addr_size	= sizeof(u32),
	.action		= fib4_rule_action,
	.match		= fib4_rule_match,
	.configure	= fib4_rule_configure,
	.compare	= fib4_rule_compare,
	.fill		= fib4_rule_fill,
	.default_pref	= fib_default_rule_pref,
	.nlmsg_payload	= fib4_rule_nlmsg_payload,
	.flush_cache	= fib4_rule_flush_cache,
	.nlgroup	= RTNLGRP_IPV4_RULE,
	.policy		= fib4_rule_policy,
	.owner		= THIS_MODULE,
};
```

```c
static int fib4_rule_action(struct fib_rule *rule, struct flowi *flp,
			    int flags, struct fib_lookup_arg *arg)
{
	int err = -EAGAIN;
	struct fib_table *tbl;

	switch (rule->action) {
	case FR_ACT_TO_TBL:
		break;

	case FR_ACT_UNREACHABLE:
		err = -ENETUNREACH;
		goto errout;

	case FR_ACT_PROHIBIT:
		err = -EACCES;
		goto errout;

	case FR_ACT_BLACKHOLE:
	default:
		err = -EINVAL;
		goto errout;
	}

	if ((tbl = fib_get_table(rule->fr_net, rule->table)) == NULL)
		goto errout;

    // fn_hash_lookup or fn_trie_lookup; で探す
	err = tbl->tb_lookup(tbl, flp, (struct fib_result *) arg->result);
	if (err > 0)
		err = -EAGAIN;
errout:
	return err;
}
```

## fib_semantic_match

----

# IPルーティング決定後

## udp_send_skb

```c
static int udp_send_skb(struct sk_buff *skb, __be32 daddr, __be32 dport)
{
	struct sock *sk = skb->sk;
	struct inet_sock *inet = inet_sk(sk);
	struct udphdr *uh;
	struct rtable *rt = (struct rtable *)skb_dst(skb);
	int err = 0;
	int is_udplite = IS_UDPLITE(sk);
	int offset = skb_transport_offset(skb);
	int len = skb->len - offset;
	__wsum csum = 0;

	/*
	 * Create a UDP header
	 */
	uh = udp_hdr(skb);
	uh->source = inet->sport;
	uh->dest = dport;
	uh->len = htons(len);
	uh->check = 0;

    /* チェックサムをごそごそする */
	if (is_udplite)  				 /*     UDP-Lite      */
		csum = udplite_csum(skb);

	else if (sk->sk_no_check == UDP_CSUM_NOXMIT) {   /* UDP csum disabled */

		skb->ip_summed = CHECKSUM_NONE;
		goto send;

	} else if (skb->ip_summed == CHECKSUM_PARTIAL) { /* UDP hardware csum */

		udp4_hwcsum(skb, rt->rt_src, daddr);
		goto send;

	} else
		csum = udp_csum(skb);

	/* add protocol-dependent pseudo-header */
	uh->check = csum_tcpudp_magic(rt->rt_src, daddr, len,
				      sk->sk_protocol, csum);
	if (uh->check == 0)
		uh->check = CSUM_MANGLED_0;

send:
	err = ip_send_skb(skb);
	if (err) {
		if (err == -ENOBUFS && !inet->recverr) {
			UDP_INC_STATS_USER(sock_net(sk),
					   UDP_MIB_SNDBUFERRORS, is_udplite);
			err = 0;
		}
	} else
		UDP_INC_STATS_USER(sock_net(sk),
				   UDP_MIB_OUTDATAGRAMS, is_udplite);
	return err;
}
```

## ip_send_skb

```c
int ip_send_skb(struct sk_buff *skb)
{
	struct net *net = sock_net(skb->sk);
	int err;

	err = ip_local_out(skb);
	if (err) {
		if (err > 0)
			err = net_xmit_errno(err);
		if (err)
            /* IPパケットの送信でコケた回数 */
			IP_INC_STATS(net, IPSTATS_MIB_OUTDISCARDS);
	}

	return err;
}
```

## ip_local_out

```c
int ip_local_out(struct sk_buff *skb)
{
	int err;

	err = __ip_local_out(skb);
	if (likely(err == 1))
		err = dst_output(skb);

	return err;
}
EXPORT_SYMBOL_GPL(ip_local_out);
```

## __ip_local_out

 * nf_hook の NF_INET_LOCAL_OUT をかます

```c
int __ip_local_out(struct sk_buff *skb)
{
	struct iphdr *iph = ip_hdr(skb);

	iph->tot_len = htons(skb->len);

    /* IP ヘッダのチェックサム計算 */
	ip_send_check(iph);
	return nf_hook(PF_INET, NF_INET_LOCAL_OUT, skb, NULL, skb_dst(skb)->dev,
		       dst_output);
}
```

## dst_output

```c
/* Output packet to network from transport.  */
static inline int dst_output(struct sk_buff *skb)
{
	// struct dst_entry * の .output 
	return skb_dst(skb)->output(skb);
}
```

## dst_output .output => ip_output ?

## ip_finish_output

