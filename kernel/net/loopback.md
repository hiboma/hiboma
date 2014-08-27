# loopback device

ループバックデバイス

```c
lo        Link encap:Local Loopback  
          inet addr:127.0.0.1  Mask:255.0.0.0
          inet6 addr: ::1/128 Scope:Host
          UP LOOPBACK RUNNING  MTU:16436  Metric:1
          RX packets:0 errors:0 dropped:0 overruns:0 frame:0
          TX packets:0 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:0 (0.0 b)  TX bytes:0 (0.0 b)

$ ip link 
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 16436 qdisc noqueue state UNKNOWN 
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00

$ ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 16436 qdisc noqueue state UNKNOWN 
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
```

 * 127.0.0.1
 * **lo**
 * デバイスドライバであり、実装は drivers/net/loopback.c に書いてある
 
IPv4 + 127.0.0.1 と UNIX domain socket との違いを追うためにソースを読む

## see also

 * http://3daysblog.blogspot.jp/2012/02/ifconfig.html
 * http://www.rissi.co.jp/Latency_of_switches.html
 * http://images.slideplayer.us/7/1716402/slides/slide_4.jpg
 
## loopback デバイス の実体は struct net_device

loopback デバイスは struct net_device である。

 * struct net_device を初期化
 * struct net に **register_netdev**

でデバイスが登録される様子。 alloc_netdev (後述) に関数ポインタとして loopback_setup を渡すことで、初期化 + allocate できる API らしい。

**lo** デバイスは起動時(?)の net_dev_init で初期化される

```c
	/* The loopback device is special if any other network devices
	 * is present in a network namespace the loopback device must
	 * be present. Since we now dynamically allocate and free the
	 * loopback device ensure this invariant is maintained by
	 * keeping the loopback device as the first device on the
	 * list of network devices.  Ensuring the loopback devices
	 * is the first device that appears and the last network device
	 * that disappears.
	 */
	if (register_pernet_device(&loopback_net_ops))
		goto out;
```

#### loopback_setup の初期化

 * MTU のサイズを決めたり (16436)
   * なんのサイズ?
 * features にデバイスのサポートする/しない機能をセットしている

```c
/*
 * The loopback device is special. There is only one instance
 * per network namespace.
 */
static void loopback_setup(struct net_device *dev)
{
    /* MTU = 16436 */
	dev->mtu		= (16 * 1024) + 20 + 20 + 12;
	dev->hard_header_len	= ETH_HLEN;	/* 14	*/
	dev->addr_len		= ETH_ALEN;	/* 6	*/
	dev->tx_queue_len	= 0;
	dev->type		= ARPHRD_LOOPBACK;	/* 0x0001*/
    /* これ大事そう */
	dev->flags		= IFF_LOOPBACK;
	dev->priv_flags	       &= ~IFF_XMIT_DST_RELEASE;
	dev->features 		= NETIF_F_SG | NETIF_F_FRAGLIST /* Scatter/gather IO. ??? */
		| NETIF_F_TSO              /*  ??? */
		| NETIF_F_NO_CSUM          /* パケットのチェックサムを計算しない */
		| NETIF_F_HIGHDMA          /* highmemory で DMA できる ? */
		| NETIF_F_LLTX             /* LockLess TX - deprecated. Please */
		| NETIF_F_NETNS_LOCAL      /* Does not change network namespaces */
		| NETIF_F_VLAN_CHALLENGED; /* Device cannot handle VLAN packets */
	dev->ethtool_ops	= &loopback_ethtool_ops;
	dev->header_ops		= &eth_header_ops;
	dev->netdev_ops		= &loopback_ops;
	dev->destructor		= loopback_dev_free;
}
```

次に alloc_netdev と register_netdev をしているコード

 * alloc_netdev
   * kmalloc + GFP_KERNEL
 * dev_net_set
   * network namespace
 * register_netdev

```c
/* Setup and register the loopback device. */
static __net_init int loopback_net_init(struct net *net)
{
	struct net_device *dev;
	int err;

	err = -ENOMEM;
	dev = alloc_netdev(0, "lo", loopback_setup);
	if (!dev)
		goto out;

	dev_net_set(dev, net);
	err = register_netdev(dev);
	if (err)
		goto out_free_netdev;

	net->loopback_dev = dev;
	return 0;


out_free_netdev:
	free_netdev(dev);
out:
	if (net == &init_net)
		panic("loopback: Failed to register netdevice: %d\n", err);
	return err;
}
```

loopback_net_init は冒頭の net_dev_init で呼び出される

## パケットの送信

net_device_ops の **.ndo_start_xmit** を使う。

```c
static const struct net_device_ops loopback_ops = {
	.ndo_init      = loopback_dev_init,
	.ndo_start_xmit= loopback_xmit,
	.ndo_get_stats = loopback_get_stats,
};
```

 http://3daysblog.blogspot.jp/2012/02/ifconfig.html によると、↑の三つのメソッドが必須ぽい

#### ところで xmit is なに?

**Transmit** の略。

## loopback_xmit の実装

loopback_xmit は下記の通り

 * IP層? から落ちてきた sk_buff を直接 netif_rx に渡している
   * ふつーのデバイスドライバなら物理デバイスに sk_buff の中身を渡して「送信」
   する実装をする箇所
   * ところが loopback_xmit では netif_rx を使って per_cpu の input_pkt_queue ? に積みなおしするので、自分で送信した sk_buff を loopback で受信しているような動作になる

これが loopback なゆえん

```c
/*
 * The higher levels take care of making this non-reentrant (it's
 * called with bh's disabled).
 */
static netdev_tx_t loopback_xmit(struct sk_buff *skb,
				 struct net_device *dev)
{
	struct pcpu_lstats *pcpu_lstats, *lb_stats;
	int len;

	skb_orphan(skb);

	skb->protocol = eth_type_trans(skb, dev);

	/* it's OK to use per_cpu_ptr() because BHs are off */
	pcpu_lstats = dev->ml_priv;
	lb_stats = per_cpu_ptr(pcpu_lstats, smp_processor_id());

	len = skb->len;
	if (likely(netif_rx(skb) == NET_RX_SUCCESS)) {
		lb_stats->bytes += len;
		lb_stats->packets++;
	} else
		lb_stats->drops++;

	return NETDEV_TX_OK;
}
```

netif_rx の動作は http://wiki.bit-hive.com/linuxkernelmemo/pg/%C1%F7%BC%F5%BF%AE の図にお世話になると理解できる

## loopback_get_stats

パケット送受信の統計値を返すメソッド

 * pcpu_lstats は loopback_dev_init で初期化されている
 * loopback デバイスでもパケットドロップが起こる可能性がある

```c
static struct net_device_stats *loopback_get_stats(struct net_device *dev)
{
	const struct pcpu_lstats *pcpu_lstats;
	struct net_device_stats *stats = &dev->stats;
	unsigned long bytes = 0;
	unsigned long packets = 0;
	unsigned long drops = 0;
	int i;

	pcpu_lstats = dev->ml_priv;
	for_each_possible_cpu(i) {
		const struct pcpu_lstats *lb_stats;

		lb_stats = per_cpu_ptr(pcpu_lstats, i);
		bytes   += lb_stats->bytes;
		packets += lb_stats->packets;
        /* パケットドロップ */
		drops   += lb_stats->drops;
	}
	stats->rx_packets = packets;
	stats->tx_packets = packets;
	stats->rx_dropped = drops;
	stats->rx_errors  = drops;
	stats->rx_bytes   = bytes;
	stats->tx_bytes   = bytes;
	return stats;
}
```

> loopback デバイスでもパケットドロップが起こる可能性がある

loopback_xmit で netif_rx にコケるとパケットドロップを起こす

```c
static netdev_tx_t loopback_xmit(struct sk_buff *skb,
				 struct net_device *dev)
{
//...

	if (likely(netif_rx(skb) == NET_RX_SUCCESS)) {
		lb_stats->bytes += len;
		lb_stats->packets++;
	} else
		lb_stats->drops++;

	return NETDEV_TX_OK;
```

### netif_rx でドロップ

netif_rx -> enqueue_to_backlog でコケたら loopback デバイスでもパケットドロップ、でいいんだろうか?

 * input_pkt_queue のキュー長さが netdev_max_backlog ( **net.core.netdev_max_backlog** ) を超えたらドロップされる (= キューイングされない)
 * デバイスに依らないキューなので、他のデバイスが猛烈にパケットを受信していたりしたらありえる?

```c
 * enqueue_to_backlog is called to queue an skb to a per CPU backlog
 * queue (may be a remote CPU queue).
 */
static int enqueue_to_backlog(struct sk_buff *skb, int cpu,
			      unsigned int *qtail)
{
	struct softnet_data *queue;
	unsigned long flags;

	queue = &per_cpu(softnet_data, cpu);

	local_irq_save(flags);
	__get_cpu_var(netdev_rx_stat).total++;

	spin_lock(&queue->input_pkt_queue.lock);

    /* ここで比較 */
	if (queue->input_pkt_queue.qlen <= netdev_max_backlog) {
		if (queue->input_pkt_queue.qlen) {
enqueue:
			__skb_queue_tail(&queue->input_pkt_queue, skb);
			*qtail = queue->input_queue_head +
				 queue->input_pkt_queue.qlen;

			spin_unlock_irqrestore(&queue->input_pkt_queue.lock,
			    flags);
			return NET_RX_SUCCESS;
		}

		/* Schedule NAPI for backlog device */
		if (napi_schedule_prep(&queue->backlog)) {
			if (cpu != smp_processor_id()) {
				struct rps_remote_softirq_cpus *rcpus =
				    &__get_cpu_var(rps_remote_softirq_cpus);

				cpu_set(cpu, rcpus->mask[rcpus->select]);
				__raise_softirq_irqoff(NET_RX_SOFTIRQ);
			} else
				____napi_schedule(queue, &queue->backlog);
		}
		goto enqueue;
	}

	spin_unlock(&queue->input_pkt_queue.lock);

   /* ドロップよ〜ん */
	__get_cpu_var(netdev_rx_stat).dropped++;
	local_irq_restore(flags);

	kfree_skb(skb);
	return NET_RX_DROP;
}
```

## ルーティング

```c
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

//...

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
		goto make_route;
	}
```

`rth->u.dst.dev	= net->loopback_dev;` のコードが 127.0.0.1 へルーティングしているコードに見える ... 宛先のデバイスを loopback にしているだけなのかな。分からん

```c
static int ip_route_input_slow(struct sk_buff *skb, __be32 daddr, __be32 saddr,
			       u8 tos, struct net_device *dev)
{

//...

local_input:
     /* struct dst_ops の割り当て */
	rth = dst_alloc(&ipv4_dst_ops);
	if (!rth)
		goto e_nobufs;

	rth->u.dst.output= ip_rt_bug;
	rth->u.dst.obsolete = -1;
	rth->rt_genid = rt_genid(net);

	atomic_set(&rth->u.dst.__refcnt, 1);
	rth->u.dst.flags= DST_HOST;
	if (IN_DEV_CONF_GET(in_dev, NOPOLICY))
		rth->u.dst.flags |= DST_NOPOLICY;
	rth->fl.fl4_dst	= daddr;
	rth->rt_dst	= daddr;
	rth->fl.fl4_tos	= tos;
	rth->fl.mark    = skb->mark;
	rth->fl.fl4_src	= saddr;
	rth->rt_src	= saddr;
#ifdef CONFIG_NET_CLS_ROUTE
	rth->u.dst.tclassid = itag;
#endif
	rth->rt_iif	=
	rth->fl.iif	= dev->ifindex;
	rth->u.dst.dev	= net->loopback_dev;
	dev_hold(rth->u.dst.dev);
    /* 参照カウントをインクリメント */
	rth->idev	= in_dev_get(rth->u.dst.dev);
	rth->rt_gateway	= daddr;
	rth->rt_spec_dst= spec_dst;
	rth->u.dst.input= ip_local_deliver;
	rth->rt_flags 	= flags|RTCF_LOCAL;
	if (res.type == RTN_UNREACHABLE) {
		rth->u.dst.input= ip_error;
		rth->u.dst.error= -err;
		rth->rt_flags 	&= ~RTCF_LOCAL;
	}
	rth->rt_type	= res.type;
	hash = rt_hash(daddr, saddr, fl.iif, rt_genid(net));
	err = rt_intern_hash(hash, rth, NULL, skb);
	goto done;

no_route:
    /* 統計値をカウント */
	RT_CACHE_STAT_INC(in_no_route);
	spec_dst = inet_select_addr(dev, 0, RT_SCOPE_UNIVERSE);
	res.type = RTN_UNREACHABLE;
	if (err == -ESRCH)
		err = -ENETUNREACH;
	goto local_input;
```