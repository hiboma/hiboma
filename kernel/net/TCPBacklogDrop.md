# TCPBacklogDrop

defined in linux-2.6.32-504.el6.x86_64/net/ipv4/pro.c

```
static const struct snmp_mib snmp4_net_list[] = {
// ...
	SNMP_MIB_ITEM("TCPBacklogDrop", LINUX_MIB_TCPBACKLOGDROP),
```

TCPBacklogDrop can be read from /proc/net/netstat

```
$ grep TcpExt /proc/net/netstat | awk '{ print $75 }'
TCPBacklogDrop
0
```

## When incremented?

```c
int tcp_v4_rcv(struct sk_buff *skb)
{

//...

	if (!sock_owned_by_user(sk)) {
#ifdef CONFIG_NET_DMA
		struct tcp_sock *tp = tcp_sk(sk);
		if (!tp->ucopy.dma_chan && tp->ucopy.pinned_list)
			tp->ucopy.dma_chan = dma_find_channel(DMA_MEMCPY);
		if (tp->ucopy.dma_chan)
			ret = tcp_v4_do_rcv(sk, skb);
		else
#endif
		{
			if (!tcp_prequeue(sk, skb))
				ret = tcp_v4_do_rcv(sk, skb);
		}
	} else if (unlikely(sk_add_backlog(sk, skb,
					   sk->sk_rcvbuf + sk->sk_sndbuf))) {
		bh_unlock_sock(sk);
		NET_INC_STATS_BH(net, LINUX_MIB_TCPBACKLOGDROP);
		goto discard_and_relse;
	}

...

discard_it:
	/* Discard frame. */
	kfree_skb(skb);
	return 0;

discard_and_relse:
	sock_put(sk);
	goto discard_it;

...

```

#### sk_add_backlog

```c
/* The per-socket spinlock must be held here. */
static inline __must_check int sk_add_backlog(struct sock *sk, struct sk_buff *skb,
					      unsigned int limit)
{
	if (sk_rcvqueues_full(sk, skb, limit))
		return -ENOBUFS;

	__sk_add_backlog(sk, skb);
	sk_extended(sk)->sk_backlog.len += skb->truesize;
	return 0;
}
```

#### sk_rcvqueues_full

```c
/*
 * Take into account size of receive queue and backlog queue
 * Do not take into account this skb truesize,
 * to allow even a single big packet to come.
 */
static inline bool sk_rcvqueues_full(const struct sock *sk, const struct sk_buff *skb,
				     unsigned int limit)
{
	unsigned int qsize = sk_extended(sk)->sk_backlog.len +
			     atomic_read(&sk->sk_rmem_alloc);

	return qsize > limit;
}
```

#### __sk_add_backlog

```
/* OOB backlog add */
static inline void __sk_add_backlog(struct sock *sk, struct sk_buff *skb)
{
	if (!sk->sk_backlog.tail) {
		sk->sk_backlog.head = sk->sk_backlog.tail = skb;
	} else {
		sk->sk_backlog.tail->next = skb;
		sk->sk_backlog.tail = skb;
	}
	skb->next = NULL;
}
```

```c
static const struct net_protocol tcp_protocol = {
	.handler =	tcp_v4_rcv,
	.err_handler =	tcp_v4_err,
	.no_policy =	1,
	.netns_ok =	1,
};
```