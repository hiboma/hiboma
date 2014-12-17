# /proc/net/softnet_stat

```
cpu	 total    dropped   squeezed  collision
  0 3423809108          0        113         41
  1 2139571893          0   20723966	   4610
```

 * dropped が増えたら?
   * `queue->input_pkt_queue.qlen <= netdev_max_backlog` な状態
   * netdev_max_backlog が足らない
 * squeezed が増えたら?
   * `budget <= 0 || time_after(jiffies, time_limit)`
   * softirq が netdev_budget を使い切っている

## 実装

```c
static void __net_exit dev_proc_net_exit(struct net *net)
{
	wext_proc_exit(net);

	proc_net_remove(net, "ptype");
	proc_net_remove(net, "softnet_stat");
	proc_net_remove(net, "dev");
}
```

```c
static int __net_init dev_proc_net_init(struct net *net)
{
	int rc = -ENOMEM;

	if (!proc_net_fops_create(net, "dev", S_IRUGO, &dev_seq_fops))
		goto out;
	if (!proc_net_fops_create(net, "softnet_stat", S_IRUGO, &softnet_seq_fops))
		goto out_dev;
```

```c
static const struct file_operations softnet_seq_fops = {
	.owner	 = THIS_MODULE,
	.open    = softnet_seq_open,
	.read    = seq_read,
	.llseek  = seq_lseek,
	.release = seq_release,
};

static int softnet_seq_open(struct inode *inode, struct file *file)
{
	return seq_open(file, &softnet_seq_ops);
}
```

```c
static const struct seq_operations softnet_seq_ops = {
	.start = softnet_seq_start,
	.next  = softnet_seq_next,
	.stop  = softnet_seq_stop,
	.show  = softnet_seq_show,
};
```

```c
static struct netif_rx_stats *softnet_get_online(loff_t *pos)
{
	struct netif_rx_stats *rc = NULL;

	while (*pos < nr_cpu_ids)
		if (cpu_online(*pos)) {
			rc = &per_cpu(netdev_rx_stat, *pos);
			break;
		} else
			++*pos;
	return rc;
}

static void *softnet_seq_start(struct seq_file *seq, loff_t *pos)
{
	return softnet_get_online(pos);
}

static void *softnet_seq_next(struct seq_file *seq, void *v, loff_t *pos)
{
	++*pos;
	return softnet_get_online(pos);
}

static void softnet_seq_stop(struct seq_file *seq, void *v)
{
}

static int softnet_seq_show(struct seq_file *seq, void *v)
{
	struct netif_rx_stats *s = v;

	seq_printf(seq, "%08x %08x %08x %08x %08x %08x %08x %08x %08x %08x\n",
		   s->total, s->dropped, s->time_squeeze, 0,
		   0, 0, 0, 0, /* was fastroute */
		   s->cpu_collision, s->received_rps);
	return 0;
}
```

netif_rx_stats の定義。CPU変数から数値をかき集める用

```c
struct netif_rx_stats
{
	unsigned total;
	unsigned dropped;
	unsigned time_squeeze;
	unsigned cpu_collision;
	unsigned received_rps;
};
```

### total

2箇所でインクリメントされている

```c
/*
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
```

```c
int __netif_receive_skb(struct sk_buff *skb)
{
	struct packet_type *ptype, *pt_prev;
	struct net_device *orig_dev;
	struct net_device *master;
	struct net_device *null_or_orig;
	struct net_device *null_or_bond;
	struct net_device *exact_dev;
	int ret = NET_RX_DROP;
	__be16 type;

	if (!skb->tstamp.tv64)
		net_timestamp(skb);

	trace_netif_receive_skb(skb);
	if (vlan_tx_tag_present(skb) && vlan_hwaccel_do_receive(skb))
		return NET_RX_SUCCESS;

	/* if we've gotten here through NAPI, check netpoll */
	if (netpoll_receive_skb(skb))
		return NET_RX_DROP;

	if (!skb->iif)
		skb->iif = skb->dev->ifindex;

	/*
	 * bonding note: skbs received on inactive slaves should only
	 * be delivered to pkt handlers that are exact matches.  Also
	 * the deliver_no_wcard flag will be set.  If packet handlers
	 * are sensitive to duplicate packets these skbs will need to
	 * be dropped at the handler.  The vlan accel path may have
	 * already set the deliver_no_wcard flag.
	 */

	null_or_orig = NULL;
	orig_dev = skb->dev;
	master = ACCESS_ONCE(orig_dev->master);
	if (skb->deliver_no_wcard)
		null_or_orig = orig_dev;
	else if (master) {
		if (skb_bond_should_drop(skb, master)) {
			skb->deliver_no_wcard = 1;
			null_or_orig = orig_dev; /* deliver only exact match */
		} else
			skb->dev = master;
	}

	__get_cpu_var(netdev_rx_stat).total++;
```

### dropped

```c 
/*
 * enqueue_to_backlog is called to queue an skb to a per CPU backlog
 * queue (may be a remote CPU queue).
 */
static int enqueue_to_backlog(struct sk_buff *skb, int cpu,
			      unsigned int *qtail)
{

	spin_lock(&queue->input_pkt_queue.lock);
	if (queue->input_pkt_queue.qlen <= netdev_max_backlog) {

    //...    
    
	}

	spin_unlock(&queue->input_pkt_queue.lock);

	__get_cpu_var(netdev_rx_stat).dropped++;
	local_irq_restore(flags);

	kfree_skb(skb);
	return NET_RX_DROP;
}
``` 

### received_rps

 ```c
/* Called from hardirq (IPI) context */
static void trigger_softirq(void *data)
{
	struct softnet_data *sd = data;
	____napi_schedule(sd, &sd->backlog);
	__get_cpu_var(netdev_rx_stat).received_rps++;
}
```

### time_squeeze

```
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

### cpu_collision

```c
static inline int handle_dev_cpu_collision(struct sk_buff *skb,
					   struct netdev_queue *dev_queue,
					   struct Qdisc *q)
{
	int ret;

	if (unlikely(dev_queue->xmit_lock_owner == smp_processor_id())) {
		/*
		 * Same CPU holding the lock. It may be a transient
		 * configuration error, when hard_start_xmit() recurses. We
		 * detect it by checking xmit owner and drop the packet when
		 * deadloop is detected. Return OK to try the next skb.
		 */
		kfree_skb(skb);
		if (net_ratelimit())
			printk(KERN_WARNING "Dead loop on netdevice %s, "
			       "fix it urgently!\n", dev_queue->dev->name);
		ret = qdisc_qlen(q);
	} else {
		/*
		 * Another cpu is holding lock, requeue & delay xmits for
		 * some time.
		 */
		__get_cpu_var(netdev_rx_stat).cpu_collision++;
		ret = dev_requeue_skb(skb, q);
	}

	return ret;
}
```