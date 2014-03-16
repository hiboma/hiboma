# CHAPTER 9


# CHAPTER 10 Frame Reception

## CHAPTER 9のおさらい

割り込みハンドラ から softirq までの流れ

 * do_IRQ でネットワークドライバの割り込みハンドラを起動
 * frame のデータを sk_buffer にコピー
   * DMAが使えるなら(普通使える) データを指すポインタを初期化するだけでよい
 * 上位プロトコル処理用に skb->protcol などを初期化
 * NET_RX_SOSTIRQ で sotirq を出す

## Queues

 * デバイスごとに queue を持つ
   * ingress queue
   * egress queue
   * queue はデバイスへのポインタを持つ
```c
// うーん どれだろう

struct netdev_queue {
/*
 * read mostly part
 */
	struct net_device	*dev;
	struct Qdisc		*qdisc;
	unsigned long		state;
	struct Qdisc		*qdisc_sleeping;
/*
 * write mostly part
 */
	spinlock_t		_xmit_lock ____cacheline_aligned_in_smp;
	int			xmit_lock_owner;
	/*
	 * please use this field instead of dev->trans_start
	 */
	unsigned long		trans_start;
	unsigned long		tx_bytes;
	unsigned long		tx_packets;
	unsigned long		tx_dropped;
} ____cacheline_aligned_in_smp;

/* This structure contains an instance of an RX queue. */
struct netdev_rx_queue {
	struct rps_map *rps_map;
	struct rps_dev_flow_table *rps_flow_table;
	struct kobject kobj;
	struct net_device *dev;
} ____cacheline_aligned_in_smp;

struct netdev_tx_queue_extended {
	struct netdev_queue	*q;
	struct kobject		kobj;
};
```
  * バッファは sk_buffer へのポインタを持つ
```c   
struct sk_buff {
	/* These two members must be first. */
	struct sk_buff		*next;
	struct sk_buff		*prev;

	struct sock		*sk;
	ktime_t			tstamp;
	struct net_device	*dev;
```   

loopback device
 * queue (ingress, egress) が無い
   * ローカルのメモリ内でのデータ転送なのでキューが無くてもよいのだろう
 * loopback device は失敗しないので、再送時の requeue もいらない
   