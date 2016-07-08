# /dev/net/tun tx_fifo_errors

Here is a ifconfig output of some TAP device. `TX` `overruns` is count 2.

ifconfig をみると TAP device で `TX overruns` が 2 にカウントされています

```
$ ifconfig tap-foo-bar
tap-foo-bar Link encap:Ethernet  HWaddr FE:16:3E:02:1D:3E  
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:14909559 errors:0 dropped:0 overruns:0 frame:0
          TX packets:100684736 errors:0 dropped:0 overruns:2 carrier:0
          collisions:0 txqueuelen:500 
          RX bytes:3098355371 (2.8 GiB)  TX bytes:17207322574 (16.0 GiB)
```

## ???

 * What is `TX overruns` of a TAP device?
   * TAPデバイスで TX overruns ってなんだっけ?
 * Where does `TX overruns` count up of TAP device ?
   * TAPデバイスで TX overruns がカウントアップされるのはどこ?

### linux-2.6.32-504.el6.x86_64/drivers/net/tun.c

In Linux kernel, `TX overruns` is treated as `tx_fifo_errors`.

TX overrun の値は、カーネルでは `tx_fifo_errors` の数値です

```c
/* Net device start xmit */
static netdev_tx_t tun_net_xmit(struct sk_buff *skb, struct net_device *dev)
{
	struct tun_struct *tun = netdev_priv(dev);
	struct tun_file *tfile = tun->tfile;

	DBG(KERN_INFO "%s: tun_net_xmit %d\n", tun->dev->name, skb->len);

	/* Drop packet if interface is not attached */
	if (!tfile)
		goto drop;

	/* Drop if the filter does not like it.
	 * This is a noop if the filter is disabled.
	 * Filter can be enabled only for the TAP devices. */
	if (!check_filter(&tun->txflt, skb))
		goto drop;

	if (skb_queue_len(&tfile->socket.sk->sk_receive_queue)
	    tun>= dev->tx_queue_len) {
		if (!(tun->flags & TUN_ONE_QUEUE)) {
			/* Normal queueing mode. */
			/* Packet scheduler handles dropping of further packets. */
			netif_stop_queue(dev);

			/* We won't see all dropped packets individually, so overrun
			 * error is more appropriate. */
			dev->stats.tx_fifo_errors++;
		} else {
			/* Single queue mode.
			 * Driver handles dropping of all packets itself. */
			goto drop;
		}
	}

	/* Orphan the skb - required as we might hang on to it
	 * for indefinite time. */
	skb_orphan(skb);

	/* Enqueue packet */
	skb_queue_tail(&tfile->socket.sk->sk_receive_queue, skb);
	dev->trans_start = jiffies;

	/* Notify and wake up reader process */
	if (tfile->flags & TUN_FASYNC)
		kill_fasync(&tfile->fasync, SIGIO, POLL_IN);
	wake_up_interruptible_poll(&tfile->socket.wait, POLLIN |
				   POLLRDNORM | POLLRDBAND);
	return NETDEV_TX_OK;

drop:
	dev->stats.tx_dropped++;
	kfree_skb(skb);
	return NETDEV_TX_OK;
}
```

 * TUN/TAP use as socket implementation.
   * TUN/TAP は socket 実装を利用しています。
 * If queue length of `sk_receive_queue` over tx_queue_len of net_device (= TAP device),  tx_fifo_errors` will be incremented and then call `netif_stop_queue`
   * `sk_receive_queue` のキュー長が struct net_device (TAPデバイス) の `tx_queue_len` を超えると、 tx_fifo_errors がインクリメントされます

```
	if (skb_queue_len(&tfile->socket.sk->sk_receive_queue)
	    tun>= dev->tx_queue_len) {
		if (!(tun->flags & TUN_ONE_QUEUE)) {
			/* Normal queueing mode. */
			/* Packet scheduler handles dropping of further packets. */
			netif_stop_queue(dev);

			/* We won't see all dropped packets individually, so overrun
			 * error is more appropriate. */
			dev->stats.tx_fifo_errors++;
```

## netif_stop_queue ???

> https://osdn.jp/projects/linux-kernel-docs/wiki/internal24-221-各種操作関数群
>
> netif_stop_queue()関数
> 出力を停止する(net_deviceの状態にLINK_STATE_XOFFビットを	立てる)にする)。	ネットワークインターフェイスがdownしたときだけでなく、	ドライバの送信バッファがフルになったときのフロー制御にも利用される。

`netif_stop_queue` is used when interface down, for congestion controll when send buffer of the network driver is full.

```c
/**
 *	netif_stop_queue - stop transmitted packets
 *	@dev: network device
 *
 *	Stop upper layers calling the device hard_start_xmit routine.
 *	Used for flow control when transmit resources are unavailable.
 */
static inline void netif_stop_queue(struct net_device *dev)
{
	netif_tx_stop_queue(netdev_get_tx_queue(dev, 0));
}
```

`netif_stop_queue` set `__QUEUE_STATE_XOFF` bit of `struct netdev_queue.state` on.

```
static inline void netif_tx_stop_queue(struct netdev_queue *dev_queue)
{
	set_bit(__QUEUE_STATE_XOFF, &dev_queue->state);
}

static inline int netif_tx_queue_stopped(const struct netdev_queue *dev_queue)
{
	return test_bit(__QUEUE_STATE_XOFF, &dev_queue->state);
}
``

## What will happen if __QUEUE_STATE_XOFF bit on ?

__QUEUE_STATE_XOFF ビットがたっていると何がおこるでしょうか?

`netpoll_send_skb_on_dev` で `netif_tx_queue_stopped` が true な場合、 udelay(USEC_PER_POLL) でパケット送信を遅延させます

```c
/* call with IRQ disabled */
void netpoll_send_skb_on_dev(struct netpoll *np, struct sk_buff *skb,
			     struct net_device *dev)
{
	int status = NETDEV_TX_BUSY;
	unsigned long tries;
	const struct net_device_ops *ops = dev->netdev_ops;
	/* It is up to the caller to keep npinfo alive. */
	struct netpoll_info *npinfo;

	WARN_ON_ONCE(!irqs_disabled());

	npinfo = rcu_dereference_bh(np->dev->npinfo);
	if (!npinfo || !netif_running(dev) || !netif_device_present(dev)) {
		__kfree_skb(skb);
		return;
	}

	/* don't get messages out of order, and no recursion */
	if (skb_queue_len(&npinfo->txq) == 0 && !netpoll_owner_active(dev)) {
		struct netdev_queue *txq;

		txq = netdev_pick_tx(dev, skb);

		/* try until next clock tick */
		for (tries = jiffies_to_usecs(1)/USEC_PER_POLL;
		     tries > 0; --tries) {
			if (__netif_tx_trylock(txq)) {
				if (!netif_tx_queue_stopped(txq)) {
					dev->priv_flags |= IFF_IN_NETPOLL;
					status = ops->ndo_start_xmit(skb, dev);
					dev->priv_flags &= ~IFF_IN_NETPOLL;
					if (status == NETDEV_TX_OK)
						txq_trans_update(txq);
				}
				__netif_tx_unlock(txq);

				if (status == NETDEV_TX_OK)
					break;

			}

			/* tickle device maybe there is some cleanup */
			netpoll_poll(np);

            // sleep 50usec  
			udelay(USEC_PER_POLL);
		}

		WARN_ONCE(!irqs_disabled(),
			"netpoll_send_skb_on_dev(): %s enabled interrupts in poll (%pF)\n",
			dev->name, ops->ndo_start_xmit);

	}

	if (status != NETDEV_TX_OK) {
		skb_queue_tail(&npinfo->txq, skb);
		schedule_delayed_work(&npinfo->tx_work,0);
	}
}
```

## struct net_device_ops tap_netdev_ops

```
static const struct net_device_ops tap_netdev_ops = {
	.ndo_uninit		= tun_net_uninit,
	.ndo_open		= tun_net_open,
	.ndo_stop		= tun_net_close,
	.ndo_start_xmit		= tun_net_xmit,
	.ndo_change_mtu		= tun_net_change_mtu,
	.ndo_set_multicast_list	= tun_net_mclist,
	.ndo_set_mac_address	= eth_mac_addr,
	.ndo_validate_addr	= eth_validate_addr,
#ifdef CONFIG_NET_POLL_CONTROLLER
	.ndo_poll_controller	= tun_poll_controller,
#endif
};
```

## struct tun_struct

```
struct tun_struct {
	struct tun_file		*tfile;
	unsigned int 		flags;
	uid_t			owner;
	gid_t			group;

	struct net_device	*dev;
	struct tap_filter       txflt;

	int			vnet_hdr_sz;
	int			sndbuf;
	void			*security;
#ifdef TUN_DEBUG
	int debug;
#endif
};


## tun_file

```
process -> /dev/net/fun -> tun_struct -> TAP net_device -> real device ???`
               \
                \...socket queue [][][][][][]
```

```
/* A tun_file connects an open character device to a tuntap netdevice. It
 * also contains all socket related strctures (except sock_fprog and tap_filter)
 * to serve as one transmit queue for tuntap device. The sock_fprog and
 * tap_filter were kept in tun_struct since they were used for filtering for the
 * netdevice not for a specific queue (at least I didn't see the reqirement for
 * this).
 */
struct tun_file {
	struct sock sk;
	struct socket socket;
	atomic_t count;
	struct tun_struct *tun;
	struct net *net;
	struct fasync_struct *fasync;
	/* only used for fasnyc */
	unsigned int flags;
};
```