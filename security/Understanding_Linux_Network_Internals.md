
# CHPTER 10 Frame Reception

## Queues

 * デバイスごとに queue を持つ
   * ingress queue

```c
/* This structure contains an instance of an RX queue. */
struct netdev_rx_queue {
	struct rps_map *rps_map;
	struct rps_dev_flow_table *rps_flow_table;
	struct kobject kobj;
	struct net_device *dev;
} ____cacheline_aligned_in_smp;
```   
   * egress  queue
   * queue はデバイスへのポインタを持つ
   * バッファは skb_buffer へのポインタを持つ
```c   
struct sk_buff {
	/* These two members must be first. */
	struct sk_buff		*next;
	struct sk_buff		*prev;

	struct sock		*sk;
	ktime_t			tstamp;
	struct net_device	*dev;
```   

 * loopback device は queue (ingress, egress) が無い
   * ローカルのメモリ内でのデータ転送なのでキューが無くてもよいのだろう
 * loopback device は失敗しないので、再送時の requeue もいらない
   