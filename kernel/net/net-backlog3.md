# /proc/net/soft_net と net.core.netdev_budget

 * http://www.tldp.org/HOWTO/KernelAnalysis-HOWTO-5.html
 * https://github.com/ryran/xsos/issues/108
 * http://takyaku.com/?p=629
 * https://nuclearcat.com/mediawiki/index.php/Intel_Gigabit_Performance#FIFO_buffer

らへんを取りまとめて書く 

## /proc/net/soft_net

`/proc/net/soft_net` は https://www.redhat.com/archives/rhl-list/2007-September/msg03735.html で整形して表示すると便利

```
$ sh test.sh         
cpu      total    dropped   squeezed  collision
  0 3381082968          0        113         41
  1 3909432306          0   20694888       4558
```

#### squeezed の数値の意味?

 * `net.core.netdev_budget` てなカウンタがあり、 softirq をやっつけると減る
 * `net.core.netdev_budget` を使い切ると `__get_cpu_var(netdev_rx_stat).time_squeeze++;` される

```c
static void net_rx_action(struct softirq_action *h)
{
	struct list_head *list = &__get_cpu_var(softnet_data).poll_list;
	unsigned long time_limit = jiffies + 2;
	int budget = netdev_budget;
	void *have;
	int select;
	struct rps_remote_softirq_cpus *rcpus;

	local_irq_disable();

	while (!list_empty(list)) {
		struct napi_struct *n;
		int work, weight;

		/* If softirq window is exhuasted then punt.
		 * Allow this to run for 2 jiffies since which will allow
		 * an average latency of 1.5/HZ.
		 */
		if (unlikely(budget <= 0 || time_after(jiffies, time_limit)))
			goto softnet_break;

//...            

softnet_break:
	__get_cpu_var(netdev_rx_stat).time_squeeze++;
	__raise_softirq_irqoff(NET_RX_SOFTIRQ);
	goto out;
}
```

#### squeezed を減らすには?

 * `net.core.netdev_budget` を増やす
   * softirq の使用率が上がる?

## NIC statistics

`ethtool -S <interface>` でいろいろ取れる。受信に関係する統計値を出した場合

```   
$ sudo /sbin/ethtool -S eth1
     rx_packets: 176715090074
     rx_bytes: 117684023437718
     rx_broadcast: 516798
     rx_multicast: 81461226941
     rx_errors: 2
     rx_length_errors: 2
     rx_over_errors: 0
     rx_crc_errors: 0
     rx_frame_errors: 0
     rx_no_buffer_count: 830920320
     rx_missed_errors: 1228956027
     rx_long_length_errors: 0
     rx_short_length_errors: 2
     rx_align_errors: 0
     rx_flow_control_xon: 0
     rx_flow_control_xoff: 0
     rx_long_byte_count: 117684023437718
     rx_csum_offload_good: 176697614429
     rx_csum_offload_errors: 0
     rx_header_split: 0
     alloc_rx_buff_failed: 2000
     rx_smbus: 0
     rx_dma_failed: 0
```

#### rx_no_buffer_count

```c
/* drivers/net/e1000e/ethtool.c */

static const struct e1000_stats e1000_gstrings_stats[] = {
//...
	E1000_NETDEV_STAT("rx_errors", rx_errors),
//...
	E1000_STAT("rx_no_buffer_count", stats.rnbc),
```

```c
/* drivers/net/e1000/e1000_ethtool.c */

static const struct e1000_stats e1000_gstrings_stats[] = {
//...
	{ "rx_no_buffer_count", E1000_STAT(stats.rnbc) },
```

rx_no_buffer_count = rnbc をカウントするのは、ハードウェア(Ethernetカード?) なので、実装が無い。レジスタから読んでるぽいコードはある

```c
	adapter->stats.rnbc += er32(RNBC);
```

#### rx_no_buffer_count が増え続けてて困ってる事例

refs http://sourceforge.net/p/e1000/mailman/message/22640719/ 

```
On a moderate traffic rx_no_buffer_count remains constant, but on
heavy traffic rx_no_buffer_count keeps increasing.

     rx_no_buffer_count: 4094038
     rx_no_buffer_count: 4094038
     rx_no_buffer_count: 4094038
     rx_no_buffer_count: 4105305
     rx_no_buffer_count: 4195585
     rx_no_buffer_count: 4285861
     rx_no_buffer_count: 4376386

while rx_no_buffer_count increases, ksoftirqd goes in saturation at
one of the cores.
```

 * rx_no_buffer_count が増加している間、 ksoftirqd がCPU使いまくり
 * `/sbin/ethtool -g <interface> rx <N>` で増加させるとよいとのこと

#### rx_missed_errors:

> This error can mean many things. Including not enough bus bandwidth, host is too busy (try to enable flow-control), PBA buffer too small.

#### `ifconfig <interface>` の数値とどう違うのか?

 * ifconfig の **dropped** は `__get_cpu_var(netdev_rx_stat).dropped++;` [refs](https://github.com/hiboma/hiboma/blob/master/kernel/net/net-backlog.md) である

```
$ /sbin/ifconfig eth1
eth1      Link encap:Ethernet  HWaddr ***********
          inet addr:192.168.**.***  Bcast:192.168.*.***  Mask:255.255.255.0
          inet6 addr: **************************** Scope:Link
          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
          RX packets:176715630438 errors:2 dropped:1228956027 overruns:0 frame:2
          TX packets:88349116734 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:1000 
          RX bytes:116977383432813 (106.3 TiB)  TX bytes:85829051863672 (78.0 TiB)
          Interrupt:177 Memory:fb6e0000-fb700000 
```

## Ring parameters for eth*

 * `rx_no_buffer_count` の数値が増えていた場合は、 RX の `ring` サイズを上げろとな
   * via https://nuclearcat.com/mediawiki/index.php/Intel_Gigabit_Performance

```
$ sudo /sbin/ethtool -g eth0
Ring parameters for eth0:
Pre-set maximums:
RX:		4096
RX Mini:	0
RX Jumbo:	0
TX:		4096
Current hardware settings:
RX:		256
RX Mini:	0
RX Jumbo:	0
TX:		256
```   