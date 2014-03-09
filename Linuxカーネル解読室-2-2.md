## 2.2.1 応答性の確保

> 伝統UNIXでは、応答性を確保するために割り込みレベルという考え方を採用していました

高優先度の割り込みによるネストを許可する

  * 優先度高い割り込み
    * 時計?
    * 電源?
  * Linux
    * 応答性が必要     ... ハードゥエア割り込みハンドラ
    * 応答性が必要ない ... 遅延実行、ソフト割り込み (ソフトIRQ)

```c
int
request_irq(unsigned int irq, irqreturn_t (*handler)(int, void *, struct pt_regs *),
	    unsigned long irqflags, const char * devname, void *dev_id)
```

## イーサネットドライバ処理

ハードウェア割り込みハンドラへ IRQ を配送するコードはどこ?

 * http://wiki.bit-hive.com/linuxkernelmemo/pg/%C1%F7%BC%F5%BF%AE
 * [Interl PRO/1000](http://www.amazon.co.jp/dp/B000BMZHX2) のドライバをサンプルに見てみよう

IRQの割り当てとハードウェア割り込みハンドラの登録

```c
int
e1000_up(struct e1000_adapter *adapter)
{

	if((err = request_irq(adapter->pdev->irq, &e1000_intr,
		              SA_SHIRQ | SA_SAMPLE_RANDOM,
		              netdev->name, netdev))) {
		DPRINTK(PROBE, ERR,
		    "Unable to allocate interrupt Error: %d\n", err);
		return err;
```

ハードウェア割り込みハンドラの実装

 * 実装の詳細はさておき IRQ番号の扱い, softirq に繋がる部分を読む
 * ハンドラの実行中は IRQ が disabled
 * 関係ない割り込みの場合は IRQ_NONE を返しとく?
 * ハンドラの実行を終えたら IRQ_HANDLED を返す
 * CONFIG_E1000_MQ
   * Multiple Queue
   * 割り込み処理を複数CPUに分散させるやつ?
 * __netif_rx_schedule -> __raise_softirq_irqoff(NET_RX_SOFTIRQ);
   * polling のリストを追加
   
```c
/**
 * e1000_intr - Interrupt Handler
 * @irq: interrupt number
 * @data: pointer to a network interface device structure
 * @pt_regs: CPU registers structure
 **/

static irqreturn_t
e1000_intr(int irq, void *data, struct pt_regs *regs)
{
	struct net_device *netdev = data;
	struct e1000_adapter *adapter = netdev_priv(netdev);
	struct e1000_hw *hw = &adapter->hw;
	uint32_t icr = E1000_READ_REG(hw, ICR);
#if defined(CONFIG_E1000_NAPI) && defined(CONFIG_E1000_MQ) || !defined(CONFIG_E1000_NAPI)
	int i;
#endif

	if(unlikely(!icr))
		return IRQ_NONE;  /* Not our interrupt */

	if(unlikely(icr & (E1000_ICR_RXSEQ | E1000_ICR_LSC))) {
		hw->get_link_status = 1;
        // 割り込みを処理 => watchdog_timer を更新しておく
		mod_timer(&adapter->watchdog_timer, jiffies);
	}

#ifdef CONFIG_E1000_NAPI
	atomic_inc(&adapter->irq_sem);
	E1000_WRITE_REG(hw, IMC, ~0);
	E1000_WRITE_FLUSH(hw);
#ifdef CONFIG_E1000_MQ
	if (atomic_read(&adapter->rx_sched_call_data.count) == 0) {
		cpu_set(adapter->cpu_for_queue[0],
			adapter->rx_sched_call_data.cpumask);
		for (i = 1; i < adapter->num_queues; i++) {
			cpu_set(adapter->cpu_for_queue[i],
				adapter->rx_sched_call_data.cpumask);
			atomic_inc(&adapter->irq_sem);
		}
		atomic_set(&adapter->rx_sched_call_data.count, i);
		smp_call_async_mask(&adapter->rx_sched_call_data);
	} else {
		printk("call_data.count == %u\n", atomic_read(&adapter->rx_sched_call_data.count));
	}
#else /* if !CONFIG_E1000_MQ */
	if (likely(netif_rx_schedule_prep(&adapter->polling_netdev[0])))
		__netif_rx_schedule(&adapter->polling_netdev[0]);
	else
		e1000_irq_enable(adapter);
#endif /* CONFIG_E1000_MQ */

#else /* if !CONFIG_E1000_NAPI */
	/* Writing IMC and IMS is needed for 82547.
	   Due to Hub Link bus being occupied, an interrupt
	   de-assertion message is not able to be sent.
	   When an interrupt assertion message is generated later,
	   two messages are re-ordered and sent out.
	   That causes APIC to think 82547 is in de-assertion
	   state, while 82547 is in assertion state, resulting
	   in dead lock. Writing IMC forces 82547 into
	   de-assertion state.
	*/

    /* Intel® 82547 Gigabit Ethernet Controller のことを指すらしい */
	if(hw->mac_type == e1000_82547 || hw->mac_type == e1000_82547_rev_2){
		atomic_inc(&adapter->irq_sem);
		E1000_WRITE_REG(hw, IMC, ~0);
	}

	for(i = 0; i < E1000_MAX_INTR; i++)
		if(unlikely(!adapter->clean_rx(adapter, adapter->rx_ring) &
		   !e1000_clean_tx_irq(adapter, adapter->tx_ring)))
			break;

	if(hw->mac_type == e1000_82547 || hw->mac_type == e1000_82547_rev_2)
		e1000_irq_enable(adapter);

#endif /* CONFIG_E1000_NAPI */

	return IRQ_HANDLED;
}
```

割り込みの on / off の切り替え

```c
/**
 * e1000_irq_disable - Mask off interrupt generation on the NIC
 * @adapter: board private structure
 **/

static inline void
e1000_irq_disable(struct e1000_adapter *adapter)
{
	atomic_inc(&adapter->irq_sem);
	E1000_WRITE_REG(&adapter->hw, IMC, ~0);
	E1000_WRITE_FLUSH(&adapter->hw);
	synchronize_irq(adapter->pdev->irq);
}

/**
 * e1000_irq_enable - Enable default interrupt generation settings
 * @adapter: board private structure
 **/

static inline void
e1000_irq_enable(struct e1000_adapter *adapter)
{
	if(likely(atomic_dec_and_test(&adapter->irq_sem))) {
       // レジスタへの書き込み
       // レジスタの中身は drivers/net/e1000/e1000_hw.h をみる
		E1000_WRITE_REG(&adapter->hw, IMS, IMS_ENABLE_MASK);
		E1000_WRITE_FLUSH(&adapter->hw);
	}
}
```

```
#ifdef CONFIG_E1000_MQ
void
e1000_rx_schedule(void *data)
{
	struct net_device *poll_dev, *netdev = data;
	struct e1000_adapter *adapter = netdev->priv;
	int this_cpu = get_cpu();

	poll_dev = *per_cpu_ptr(adapter->cpu_netdev, this_cpu);
	if (poll_dev == NULL) {
		put_cpu();
		return;
	}

	if (likely(netif_rx_schedule_prep(poll_dev)))
        // すでに softirq が発行済?で polling させる場合
        // softirq から process_backlog に繋がる
		__netif_rx_schedule(poll_dev);
	else
		e1000_irq_enable(adapter);

	put_cpu();
}
#endif
```

__netif_rx_schedule を呼び出すと softirq へ繋がる
 * poll_list への追加

```c
/* Add interface to tail of rx poll list. This assumes that _prep has
 * already been called and returned 1.
 */

static inline void __netif_rx_schedule(struct net_device *dev)
{
	unsigned long flags;

	local_irq_save(flags);
	dev_hold(dev);
	list_add_tail(&dev->poll_list, &__get_cpu_var(softnet_data).poll_list);
	if (dev->quota < 0)
		dev->quota += dev->weight;
	else
		dev->quota = dev->weight;
	__raise_softirq_irqoff(NET_RX_SOFTIRQ);
	local_irq_restore(flags);
}
```

NET_RX_SOFTIRQ に対応するハンドらは net_dev_init で登録されている

```c
/*
 *       This is called single threaded during boot, so no need
 *       to take the rtnl semaphore.
 */
static int __init net_dev_init(void)
{
	int i, rc = -ENOMEM;

	BUG_ON(!dev_boot_phase);

	net_random_init();

	if (dev_proc_init())
		goto out;

	if (netdev_sysfs_init())
		goto out;

	INIT_LIST_HEAD(&ptype_all);
	for (i = 0; i < 16; i++) 
		INIT_LIST_HEAD(&ptype_base[i]);

	for (i = 0; i < ARRAY_SIZE(dev_name_head); i++)
		INIT_HLIST_HEAD(&dev_name_head[i]);

	for (i = 0; i < ARRAY_SIZE(dev_index_head); i++)
		INIT_HLIST_HEAD(&dev_index_head[i]);

	/*
	 *	Initialise the packet receive queues.
	 */

    // 受信キューは CPU ごとに用意されている
	for (i = 0; i < NR_CPUS; i++) {
		struct softnet_data *queue;

		queue = &per_cpu(softnet_data, i);
        // パケット受信キューの初期化
        // sk_buff_head, sk_buff のリスト
		skb_queue_head_init(&queue->input_pkt_queue);
		queue->completion_queue = NULL;
		INIT_LIST_HEAD(&queue->poll_list);
		set_bit(__LINK_STATE_START, &queue->backlog_dev.state);
		queue->backlog_dev.weight = weight_p;
        // polling の際に呼び出されるハンドラ?
		queue->backlog_dev.poll = process_backlog;
		atomic_set(&queue->backlog_dev.refcnt, 1);
	}

	dev_boot_phase = 0;

    // softirq の静的な Array に IRQ番号に応じたデータと関数ポインタぶっこむだけ
    //	softirq_vec[nr].data = data;
    //	softirq_vec[nr].action = action;
	open_softirq(NET_TX_SOFTIRQ, net_tx_action, NULL);
	open_softirq(NET_RX_SOFTIRQ, net_rx_action, NULL);

	hotcpu_notifier(dev_cpu_callback, 0);
	dst_init();
	dev_mcast_init();
	rc = 0;
out:
	return rc;
}
```

process_backlog

 * polling 
 * sk_buffer を取り出して netif_receive_skb でごにょごにょ
```c
static int process_backlog(struct net_device *backlog_dev, int *budget)
{
	int work = 0;
	int quota = min(backlog_dev->quota, *budget);
	struct softnet_data *queue = &__get_cpu_var(softnet_data);
	unsigned long start_time = jiffies;

	backlog_dev->weight = weight_p;
	for (;;) {
		struct sk_buff *skb;
		struct net_device *dev;

		local_irq_disable();
		skb = __skb_dequeue(&queue->input_pkt_queue);
		if (!skb)
			goto job_done;
		local_irq_enable();

		dev = skb->dev;

		netif_receive_skb(skb);

		dev_put(dev);

		work++;

		if (work >= quota || jiffies - start_time > 1)
			break;

	}

	backlog_dev->quota -= work;
	*budget -= work;
	return -1;

job_done:
	backlog_dev->quota -= work;
	*budget -= work;

	list_del(&backlog_dev->poll_list);
	smp_mb__before_clear_bit();
	netif_poll_enable(backlog_dev);

	local_irq_enable();
	return 0;
}
```

## TCP/IPプロトコル処理 (softirq)

## SCSIホストバスアダプタドライバ処理

## シリアルドライバ処理	

## SCSIプロトコル処理

## 端末制御処理    

## request_irq

 * struct irqaction
 * struct irq_desc
 * /proc/irq/<IRQ番号>

```c
/*
 * This is the "IRQ descriptor", which contains various information
 * about the irq, including what kind of hardware handling it has,
 * whether it is disabled etc etc.
 *
 * Pad this out to 32 bytes for cache and indexing reasons.
 */
typedef struct irq_desc {
	hw_irq_controller *handler;
	void *handler_data;
	struct irqaction *action;	/* IRQ action list */
	unsigned int status;		/* IRQ status */
	unsigned int depth;		/* nested irq disables */
	unsigned int irq_count;		/* For detecting broken interrupts */
	unsigned int irqs_unhandled;
	spinlock_t lock;
#if defined (CONFIG_GENERIC_PENDING_IRQ) || defined (CONFIG_IRQBALANCE)
	unsigned int move_irq;		/* Flag need to re-target intr dest*/
#endif
} ____cacheline_aligned irq_desc_t;

extern irq_desc_t irq_desc [NR_IRQS];
```

```c
struct irqaction {
	irqreturn_t (*handler)(int, void *, struct pt_regs *);
	unsigned long flags;
	cpumask_t mask;
	const char *name;
	void *dev_id;
	struct irqaction *next;
	int irq;
	struct proc_dir_entry *dir;
};
```