# vti tx_carrier_errors

 * vti0 `errs`    59 
 * vti0 `carrier` 59
 * vti1 `errs`   280
 * vti1 `errs`   280

Here is a `/proc/net/dev` snapshot of some VyOS VPN

```
$ cat /proc/net/dev
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
  vti0: 2585149477912 2520061641    0    0    0     0          0         0 428688344945 1836442339   59    0    0     0      59          0
  vti1: 20343428031771 20704797251    0    0    0     0          0         0 3538387799300 15293395309  280    0    0     0     280          0
  eth0: 24734084448798 23354204056    0 4735195    0     0          0         0 3998468669079 17298271810    0    0    0     0       0          0
  eth1: 2853672119248 17173742239    0 4710985    0     0          0         0 23269452532747 23290001083    0    0    0     0       0          0
    lo: 1340616044 18288320    0    0    0     0          0         0 1340616044 18288320    0    0    0     0       0          0
ip_vti0:       0       0    0    0    0     0          0         0        0       0    0    0    0     0       0          0
```

`carrier` is counted as `tx_carrier_errors` in Linux Kernel.

## vti_xmit

`tx_carrier_errors` is incremented at 3 points.

```c
static netdev_tx_t vti_xmit(struct sk_buff *skb, struct net_device *dev,
			    struct flowi *fl)
{
	struct ip_tunnel *tunnel = netdev_priv(dev);
	struct ip_tunnel_parm *parms = &tunnel->parms;
	struct dst_entry *dst = skb_dst(skb);
	struct net_device *tdev;	/* Device to other host */
	int err;

    # (1)
	if (!dst) {
		dev->stats.tx_carrier_errors++; 
		goto tx_error_icmp;
	}

    # (2)
	dst_hold(dst);
	dst = xfrm_lookup(tunnel->net, dst, fl, NULL, 0);
	if (IS_ERR(dst)) {
		dev->stats.tx_carrier_errors++;
		goto tx_error_icmp;
	}

    # (3)
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
```

```
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
```

## ip_tunnel_xmit

```
void ip_tunnel_xmit(struct sk_buff *skb, struct net_device *dev,
		    const struct iphdr *tnl_params, u8 protocol)
{
	struct ip_tunnel *tunnel = netdev_priv(dev);
	const struct iphdr *inner_iph;
	struct flowi4 fl4;
	u8     tos, ttl;
	__be16 df;
	struct rtable *rt;		/* Route to the other host */
	unsigned int max_headroom;	/* The extra header space needed */
	__be32 dst;
	int err;
	bool connected;

	inner_iph = (const struct iphdr *)skb_inner_network_header(skb);
	connected = (tunnel->parms.iph.daddr != 0);

	dst = tnl_params->daddr;
	if (dst == 0) {
		/* NBMA tunnel */

		if (skb_dst(skb) == NULL) {
			dev->stats.tx_fifo_errors++;
			goto tx_error;
		}

		if (skb->protocol == htons(ETH_P_IP)) {
			rt = skb_rtable(skb);
			dst = rt_nexthop(rt, inner_iph->daddr);
		}
#if IS_ENABLED(CONFIG_IPV6)
		else if (skb->protocol == htons(ETH_P_IPV6)) {
			const struct in6_addr *addr6;
			struct neighbour *neigh;
			bool do_tx_error_icmp;
			int addr_type;

			neigh = dst_neigh_lookup(skb_dst(skb),
						 &ipv6_hdr(skb)->daddr);
			if (neigh == NULL)
				goto tx_error;

			addr6 = (const struct in6_addr *)&neigh->primary_key;
			addr_type = ipv6_addr_type(addr6);

			if (addr_type == IPV6_ADDR_ANY) {
				addr6 = &ipv6_hdr(skb)->daddr;
				addr_type = ipv6_addr_type(addr6);
			}

			if ((addr_type & IPV6_ADDR_COMPATv4) == 0)
				do_tx_error_icmp = true;
			else {
				do_tx_error_icmp = false;
				dst = addr6->s6_addr32[3];
			}
			neigh_release(neigh);
			if (do_tx_error_icmp)
				goto tx_error_icmp;
		}
#endif
		else
			goto tx_error;

		connected = false;
	}

	tos = tnl_params->tos;
	if (tos & 0x1) {
		tos &= ~0x1;
		if (skb->protocol == htons(ETH_P_IP)) {
			tos = inner_iph->tos;
			connected = false;
		} else if (skb->protocol == htons(ETH_P_IPV6)) {
			tos = ipv6_get_dsfield((const struct ipv6hdr *)inner_iph);
			connected = false;
		}
	}

	init_tunnel_flow(&fl4, protocol, dst, tnl_params->saddr,
			 tunnel->parms.o_key, RT_TOS(tos), tunnel->parms.link);

	if (ip_tunnel_encap(skb, tunnel, &protocol, &fl4) < 0)
		goto tx_error;

	rt = connected ? tunnel_rtable_get(tunnel, 0, &fl4.saddr) : NULL;

	if (!rt) {
		rt = ip_route_output_key(tunnel->net, &fl4);

		if (IS_ERR(rt)) {
			dev->stats.tx_carrier_errors++;
			goto tx_error;
		}
		if (connected)
			tunnel_dst_set(tunnel, &rt->dst, fl4.saddr);
	}
```