# /proc/net/dev

``c
 *	Called from the PROCfs module. This now uses the new arbitrary sized
 *	/proc/net interface to create /proc/net/dev
 */
static int dev_seq_show(struct seq_file *seq, void *v)
{
	if (v == SEQ_START_TOKEN)
		seq_puts(seq, "Inter-|   Receive                            "
			      "                    |  Transmit\n"
			      " face |bytes    packets errs drop fifo frame "
			      "compressed multicast|bytes    packets errs "
			      "drop fifo colls carrier compressed\n");
	else
		dev_seq_printf_stats(seq, v);
	return 0;
}
```

```c
static void dev_seq_printf_stats(struct seq_file *seq, struct net_device *dev)
{
	struct rtnl_link_stats64 temp;
	const struct rtnl_link_stats64 *stats = dev_get_stats(dev, &temp);

	seq_printf(seq, "%6s: %7llu %7llu %4llu %4llu %4llu %5llu %10llu %9llu "
		   "%8llu %7llu %4llu %4llu %4llu %5llu %7llu %10llu\n",
		   dev->name, stats->rx_bytes, stats->rx_packets,
		   stats->rx_errors,
		   stats->rx_dropped + stats->rx_missed_errors,
		   stats->rx_fifo_errors,
		   stats->rx_length_errors + stats->rx_over_errors +
		    stats->rx_crc_errors + stats->rx_frame_errors,
		   stats->rx_compressed, stats->multicast,
		   stats->tx_bytes, stats->tx_packets,
		   stats->tx_errors, stats->tx_dropped,
		   stats->tx_fifo_errors, stats->collisions,
		   stats->tx_carrier_errors +
		    stats->tx_aborted_errors +
		    stats->tx_window_errors +
		    stats->tx_heartbeat_errors,
		   stats->tx_compressed);
}
```

```c
/**
 *	dev_get_stats	- get network device statistics
 *	@dev: device to get statistics from
 *	@storage: place to store stats
 *
 *	Get network statistics from device. Return @storage.
 *	The device driver may provide its own method by setting
 *	dev->netdev_ops->get_stats64 or dev->netdev_ops->get_stats;
 *	otherwise the internal statistics structure is used.
 */
struct rtnl_link_stats64 *dev_get_stats(struct net_device *dev,
					struct rtnl_link_stats64 *storage)
{
	const struct net_device_ops *ops = dev->netdev_ops;

	if (ops->ndo_get_stats64) {
		memset(storage, 0, sizeof(*storage));
		ops->ndo_get_stats64(dev, storage);
	} else if (ops->ndo_get_stats) {
		netdev_stats_to_stats64(storage, ops->ndo_get_stats(dev));
	} else {
		netdev_stats_to_stats64(storage, &dev->stats);
	}
	storage->rx_dropped += atomic_long_read(&dev->rx_dropped);
	return storage;
}
EXPORT_SYMBOL(dev_get_stats);

```

## ip_vti tx_errors

static netdev_tx_t vti_xmit(struct sk_buff *skb, struct net_device *dev,
			    struct flowi *fl)
{
	struct ip_tunnel *tunnel = netdev_priv(dev);
	struct ip_tunnel_parm *parms = &tunnel->parms;
	struct dst_entry *dst = skb_dst(skb);
	struct net_device *tdev;	/* Device to other host */
	int err;

	if (!dst) {
		dev->stats.tx_carrier_errors++;
		goto tx_error_icmp;
	}

	dst_hold(dst);
	dst = xfrm_lookup(tunnel->net, dst, fl, NULL, 0);
	if (IS_ERR(dst)) {
		dev->stats.tx_carrier_errors++;
		goto tx_error_icmp;
	}

	if (!vti_state_check(dst->xfrm, parms->iph.daddr, parms->iph.saddr)) {
		dev->stats.tx_carrier_errors++;
		dst_release(dst);
		goto tx_error_icmp;
	}

	tdev = dst->dev;

	if (tdev == dev) {
		dst_release(dst);
		dev->stats.collisions++;
		goto tx_error;
	}

	if (tunnel->err_count > 0) {
		if (time_before(jiffies,
				tunnel->err_time + IPTUNNEL_ERR_TIMEO)) {
			tunnel->err_count--;
			dst_link_failure(skb);
		} else
			tunnel->err_count = 0;
	}

	skb_scrub_packet(skb, !net_eq(tunnel->net, dev_net(dev)));
	skb_dst_set(skb, dst);
	skb->dev = skb_dst(skb)->dev;

	err = dst_output(skb);
	if (net_xmit_eval(err) == 0)
		err = skb->len;
	iptunnel_xmit_stats(err, &dev->stats, dev->tstats);
	return NETDEV_TX_OK;

tx_error_icmp:
	dst_link_failure(skb);
tx_error:
	dev->stats.tx_errors++;
	kfree_skb(skb);
	return NETDEV_TX_OK;
}


/* This function assumes it is being called from dev_queue_xmit()
 * and that skb is filled properly by that function.
 */
static netdev_tx_t vti_tunnel_xmit(struct sk_buff *skb, struct net_device *dev)
{
	struct ip_tunnel *tunnel = netdev_priv(dev);
	struct flowi fl;

	memset(&fl, 0, sizeof(fl));

	switch (skb->protocol) {
	case htons(ETH_P_IP):
		xfrm_decode_session(skb, &fl, AF_INET);
		memset(IPCB(skb), 0, sizeof(*IPCB(skb)));
		break;
	case htons(ETH_P_IPV6):
		xfrm_decode_session(skb, &fl, AF_INET6);
		memset(IP6CB(skb), 0, sizeof(*IP6CB(skb)));
		break;
	default:
		dev->stats.tx_errors++;
		dev_kfree_skb(skb);
		return NETDEV_TX_OK;
	}

	/* override mark with tunnel output key */
	fl.flowi_mark = be32_to_cpu(tunnel->parms.o_key);

	return vti_xmit(skb, dev, &fl);
}
