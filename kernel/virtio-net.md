## virtioのドライバーAPI で struct virtio_driver を登録

  * register_virtio_driver
  * unregister_virtio_driver

## virtio_driver の .probe で net_device の初期化

```c
	struct net_device *dev;
	struct virtnet_info *vi;

	/* Allocate ourselves a network device with room for our info */
	dev = alloc_etherdev(sizeof(struct virtnet_info));
	if (!dev)
		return -ENOMEM;

	dev->netdev_ops = &virtnet_netdev;
	dev->features = NETIF_F_HIGHDMA;
```

net_device .netdev_ops は net_device_ops 

```c
static const struct net_device_ops virtnet_netdev = {
	.ndo_open            = virtnet_open,
	.ndo_stop   	     = virtnet_close,
	.ndo_start_xmit      = start_xmit,
	.ndo_validate_addr   = eth_validate_addr,
	.ndo_set_mac_address = virtnet_set_mac_address,
	.ndo_set_rx_mode     = virtnet_set_rx_mode,
	.ndo_change_mtu	     = virtnet_change_mtu,
	.ndo_vlan_rx_add_vid = virtnet_vlan_rx_add_vid,
	.ndo_vlan_rx_kill_vid = virtnet_vlan_rx_kill_vid,
#ifdef CONFIG_NET_POLL_CONTROLLER
	.ndo_poll_controller = virtnet_netpoll,
#endif
};
```

## net_device の 登録は register_dev

```c
	err = register_netdev(dev);
	if (err) {
		pr_debug("virtio_net: registering device failed\n");
		goto free_vqs;
	}
```

## virtio と virtio-net

virtio は下位のドライバを抽象化している

 * IRQ は取り扱わない
   * virtio_pci に任せてる? 

## 下位ドライバで使える機能を virtio_has_feature で取ってvirioの挙動を変える

```c
	/* If we can receive ANY GSO packets, we must allocate large ones. */
	if (virtio_has_feature(vdev, VIRTIO_NET_F_GUEST_TSO4)
	    || virtio_has_feature(vdev, VIRTIO_NET_F_GUEST_TSO6)
	    || virtio_has_feature(vdev, VIRTIO_NET_F_GUEST_ECN))
		vi->big_packets = true;
```

## struct ethtool_ops

ethtool 用?

```c
	SET_ETHTOOL_OPS(dev, &virtnet_ethtool_ops);
```

## NAPI

NAPI に polling のメソッドを追加

```c
	netif_napi_add(dev, &vi->napi, virtnet_poll, napi_weight);
````    


 * virtnet_poll
 * -> receive_buf (パケットマージしたりとか)
 * -> netif_receive_skb
   * -> enqueue_to_backlog
   * -> __netif_receive_skb
```c
/**
 *	netif_receive_skb - process receive buffer from network
 *	@skb: buffer to process
 *
 *	netif_receive_skb() is the main receive data processing function.
 *	It always succeeds. The buffer may be dropped during processing
 *	for congestion control or by the protocol layers.
 *
 *	This function may only be called from softirq context and interrupts
 *	should be enabled.
 *
 *	Return values (usually ignored):
 *	NET_RX_SUCCESS: no congestion
 *	NET_RX_DROP: packet was dropped
 */
int netif_receive_skb(struct sk_buff *skb)
{
	struct rps_dev_flow voidflow, *rflow = &voidflow;
	int cpu, ret;

	cpu = get_rps_cpu(skb->dev, skb, &rflow);

        // RPSで複数のCPUが割り当てられている時
	if (cpu >= 0)
                // キューイングしてNAPI
                // 他のCPUの softirq ?
		ret = enqueue_to_backlog(skb, cpu, &rflow->last_qtail);
	else
		// package_type のハンドラを呼んでプロトコル処理
		ret = __netif_receive_skb(skb);

	return ret;
}
EXPORT_SYMBOL(netif_receive_skb);
```