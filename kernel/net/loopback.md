# loopback device

 * いわゆる **lo**
 * デバイスドライバであり、実装は drivers/net/loopback.c に書いてある
 
UNIX domain socket との違いを追うためにソースを読む

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

```c
/*
 * The loopback device is special. There is only one instance
 * per network namespace.
 */
static void loopback_setup(struct net_device *dev)
{
	dev->mtu		= (16 * 1024) + 20 + 20 + 12;
	dev->hard_header_len	= ETH_HLEN;	/* 14	*/
	dev->addr_len		= ETH_ALEN;	/* 6	*/
	dev->tx_queue_len	= 0;
	dev->type		= ARPHRD_LOOPBACK;	/* 0x0001*/
	dev->flags		= IFF_LOOPBACK;
	dev->priv_flags	       &= ~IFF_XMIT_DST_RELEASE;
	dev->features 		= NETIF_F_SG | NETIF_F_FRAGLIST
		| NETIF_F_TSO
		| NETIF_F_NO_CSUM
		| NETIF_F_HIGHDMA
		| NETIF_F_LLTX
		| NETIF_F_NETNS_LOCAL
		| NETIF_F_VLAN_CHALLENGED;
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

## パケットの送信は

net_device_ops の **.ndo_start_xmit** を使う。

```c
static const struct net_device_ops loopback_ops = {
	.ndo_init      = loopback_dev_init,
	.ndo_start_xmit= loopback_xmit,
	.ndo_get_stats = loopback_get_stats,
};
```

## ところで xmit is なに?

**Transmit** の略。

## loopback_xmit の実装

loopback_xmit は下記の通り

 * IP層? から落ちてきた sk_buff を netif_rx に渡している
   * ふつーのデバイスドライバなら、デバイスのメモリに sk_buff の中身を渡して「送信」
   する実装をする箇所
   * loopback_xmit では netif_rx で input_pkt_queue ? に積みなおしするので、あたかも loopback で受信しているような動作になる
     * http://wiki.bit-hive.com/linuxkernelmemo/pg/%C1%F7%BC%F5%BF%AE の図にお世話になって理解できる

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

