## 用語

 * IRQ interrupt request
 * ISR interrupt service routine

## TODO

```
---- softirq プロセスコンテキスト ------------------------

  raise_softirq -> wakeup_softirqd で ksoftirqd を起床させる

--- ksoftirqd --------------------------------------------

  [ksoftirqd] が pending している sotirq を処理する
    do_softirq
    __do_softirq

---- softirq 割り込みコンテキスト ------------------------

  raise_softirq
    raise_softirq_irqoff で softirq を pending

---- ハードウェア割り込みハンドラ(ドライバ) ----

irqaction->handler で割り込みハンドラ呼び出し
  e1000_intr, serial8250_interrupt, ...

                   request_irq で登録
                  /
                 ｜  local_irq_enable, local_irq_disable
---- IRQ 層 ---- ↓ ---- ↑ ------------------------------

handle_IRQ_event
__do_IRQ
do_IRQ

---- CPUアーキテクチャ依存層 (i386/kernel/entry.S) -------
2
ENTRY(interrupt)
.text

vector=0
ENTRY(irq_entries_start)
/* i386 では NR_IRQS = 224 */
/* 224 の割り込みベクタを common_interrupt で処理 ?*/
.rept NR_IRQS
        ALIGN
        # 224 - 256 = -32 = IRQの数?
1:      pushl $vector-256
        jmp common_interrupt
.data
        .long 1b
.text
vector=vector+1
.endr

        ALIGN
common_interrupt:
        SAVE_ALL
        movl %esp,%eax
        call do_IRQ
        jmp ret_from_intr

# ---- ハードウェア ----

 * ローカルタイマ
 * グローバルタイマ
 * 外部デバイス (ディスク, イーサーネットカード, ... )
```

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

## 2.2.2 マルチプロセッサへの対応

 * どの CPU でも ハードウェア割り込みハンドラを処理できる
   * IRQ が異なっていれば並列に処理できる
 * どの CPU でも softirq を処理できる
   * softirq はハードウェア割り込みハンドラを受けたCPUで実行される
   * CPUキャッシュ
 * ハードゥエア割り込みを特定のCPUに affinity できる
   * [RedHat のドキュメント](https://access.redhat.com/site/documentation/ja-JP/Red_Hat_Enterprise_Linux/6/html/Performance_Tuning_Guide/s-cpu-irq.html)
```
[vagrant@vagrant-centos65 ~]$ ls -hal /proc/irq/0/
total 0
dr-xr-xr-x  2 root root 0 Mar  8 11:23 .
dr-xr-xr-x 21 root root 0 Mar  8 11:23 ..
-r--------  1 root root 0 Mar  8 11:23 affinity_hint
-r--r--r--  1 root root 0 Mar  8 11:23 node
-rw-------  1 root root 0 Mar  8 11:23 smp_affinity
-rw-------  1 root root 0 Mar  8 11:23 smp_affinity_list
-r--r--r--  1 root root 0 Mar  8 11:23 spurious
```

## 2.2.3 割り込みスタック

 * 割り込みハンドラ用のスタック
 * ハードウェア割り込みハンドラ、softirq は current のカーネルスタックを利用する
   * カーネルスタックのサイズが大きめに取られている理由
   * workqueue はカーネルスレッドがあるので そのスタック
   * tasklet は?
 
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
 * __netif_rx_schedule -> __raise_softirq_irqoff(NET_RX_SOFTIRQ) で softirq に繋がる
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
 * softirq は 各々のCPUで実行されるので ローカルIRQ を disable する
 * スピンロックはいらん

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

## TCP/IPプロトコル処理 (softirq ハンドラ)

__do_softirq の softirq_action->action で呼び出し

```c
static void net_rx_action(struct softirq_action *h)
{
	struct softnet_data *queue = &__get_cpu_var(softnet_data);
	unsigned long start_time = jiffies;
	int budget = netdev_budget;
	void *have;

	local_irq_disable();

	while (!list_empty(&queue->poll_list)) {
		struct net_device *dev;

		if (budget <= 0 || jiffies - start_time > 1)
			goto softnet_break;

		local_irq_enable();

		dev = list_entry(queue->poll_list.next,
				 struct net_device, poll_list);
		have = netpoll_poll_lock(dev);

		if (dev->quota <= 0 || dev->poll(dev, &budget)) {
			netpoll_poll_unlock(have);
			local_irq_disable();
			list_del(&dev->poll_list);
			list_add_tail(&dev->poll_list, &queue->poll_list);
			if (dev->quota < 0)
				dev->quota += dev->weight;
			else
				dev->quota = dev->weight;
		} else {
			netpoll_poll_unlock(have);
			dev_put(dev);
			local_irq_disable();
		}
	}
out:
	local_irq_enable();
	return;

softnet_break:
	__get_cpu_var(netdev_rx_stat).time_squeeze++;
	__raise_softirq_irqoff(NET_RX_SOFTIRQ);
	goto out;
}

polling の際に呼び出しされる process_backlog

 * polling 
 * sk_buffer __skb_dequeue で取り出して netif_receive_skb でごにょごにょ
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
        // CPUごとのキューから dequeue
        // CPUごとに独立しているのでロックがいらない
        // input_pkt_queue は struct sk_buff_head
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

 * sk_buff でパケットの中身を見て、プロトコルに応じたハンドラ (packet_type) に繋げる
   * dev_add_pack でパケットのハンドラを追加する
     * `dev_add_pack(&ip_packet_type);`
     * `dev_add_pack(&arp_packet_type);`
```c
int netif_receive_skb(struct sk_buff *skb)
{
	struct packet_type *ptype, *pt_prev;
	struct net_device *orig_dev;
	int ret = NET_RX_DROP;
	unsigned short type;

	/* if we've gotten here through NAPI, check netpoll */
	if (skb->dev->poll && netpoll_rx(skb))
		return NET_RX_DROP;

	if (!skb->tstamp.off_sec)
		net_timestamp(skb);

	if (!skb->input_dev)
		skb->input_dev = skb->dev;

	orig_dev = skb_bond(skb);

	__get_cpu_var(netdev_rx_stat).total++;

	skb->h.raw = skb->nh.raw = skb->data;
	skb->mac_len = skb->nh.raw - skb->mac.raw;

	pt_prev = NULL;

	rcu_read_lock();

#ifdef CONFIG_NET_CLS_ACT
	if (skb->tc_verd & TC_NCLS) {
		skb->tc_verd = CLR_TC_NCLS(skb->tc_verd);
		goto ncls;
	}
#endif

    // パケットタイプを探すぞー
    // パケットタイプの net_device と sk_buff の dev が一致するかどうからしい
	list_for_each_entry_rcu(ptype, &ptype_all, list) {
		if (!ptype->dev || ptype->dev == skb->dev) {
			if (pt_prev)
                      // packet_type の .func を呼び出しする
				ret = deliver_skb(skb, pt_prev, orig_dev);
			pt_prev = ptype;
		}
	}

#ifdef CONFIG_NET_CLS_ACT
	if (pt_prev) {
		ret = deliver_skb(skb, pt_prev, orig_dev);
		pt_prev = NULL; /* noone else should process this after*/
	} else {
		skb->tc_verd = SET_TC_OK2MUNGE(skb->tc_verd);
	}

	ret = ing_filter(skb);

	if (ret == TC_ACT_SHOT || (ret == TC_ACT_STOLEN)) {
		kfree_skb(skb);
		goto out;
	}

	skb->tc_verd = 0;
ncls:
#endif

	handle_diverter(skb);

	if (handle_bridge(&skb, &pt_prev, &ret, orig_dev))
		goto out;

    // パケットのプロトコル?
	type = skb->protocol;
    // プロトコルに応じたハンドラを探す
    // ハンドラは static struct list_head ptype_base[16];	/* 16 way hashed list */ に登録されている
    //  
	list_for_each_entry_rcu(ptype, &ptype_base[ntohs(type)&15], list) {
		if (ptype->type == type &&
		    (!ptype->dev || ptype->dev == skb->dev)) {
			if (pt_prev) 
				ret = deliver_skb(skb, pt_prev, orig_dev);
			pt_prev = ptype;
		}
	}

	if (pt_prev) {
		ret = pt_prev->func(skb, skb->dev, pt_prev, orig_dev);
	} else {
		kfree_skb(skb);
		/* Jamal, now you will not able to escape explaining
		 * me how you were going to use this. :-)
		 */
		ret = NET_RX_DROP;
	}

out:
	rcu_read_unlock();
	return ret;
}
```

## SCSIホストバスアダプタドライバ処理

どれみたらいいか分からん

## SCSIプロトコル処理

drivers/scsi/scsi.c ?

 * softirq は CPUごとの処理
   * ローカル割り込みは diable
   * スピンロックはいらない

```c
/* Private entry to scsi_done() to complete a command when the timer
 * isn't running --- used by scsi_times_out */
void __scsi_done(struct scsi_cmnd *cmd)
{
        unsigned long flags;

        /*   
         * Set the serial numbers back to zero
         */
        cmd->serial_number = 0; 

        atomic_inc(&cmd->device->iodone_cnt);
        if (cmd->result)
                atomic_inc(&cmd->device->ioerr_cnt);

        /*   
         * Next, enqueue the command into the done queue.
         * It is a per-CPU queue, so we just disable local interrupts
         * and need no spinlock.
         */
        local_irq_save(flags);
        list_add_tail(&cmd->eh_entry, &__get_cpu_var(scsi_done_q));
        raise_softirq_irqoff(SCSI_SOFTIRQ);
        local_irq_restore(flags);
}
```

list_add_tail + __get_cpu_var のやり方は イーサネットドライバ処理 似ている

## シリアルドライバ処理

どのドライバを読んだら良いか分からんので drivers/serial/8250.c

 * uart_ops の .startup の中で request_irq が 呼び出されていた
 * レジスタの初期化などを行ってから request_irq を呼び出す
   * 初期化されていないのに割り込みされたら意図しない挙動を招くから?

```c
static struct uart_ops serial8250_pops = {
	.tx_empty	= serial8250_tx_empty,
	.set_mctrl	= serial8250_set_mctrl,
	.get_mctrl	= serial8250_get_mctrl,
	.stop_tx	= serial8250_stop_tx,
	.start_tx	= serial8250_start_tx,
	.stop_rx	= serial8250_stop_rx,
	.enable_ms	= serial8250_enable_ms,
	.break_ctl	= serial8250_break_ctl,
	.startup	= serial8250_startup,    // これ
	.shutdown	= serial8250_shutdown,
	.set_termios	= serial8250_set_termios,
	.pm		= serial8250_pm,
	.type		= serial8250_type,
	.release_port	= serial8250_release_port,
	.request_port	= serial8250_request_port,
	.config_port	= serial8250_config_port,
	.verify_port	= serial8250_verify_port,
};
```

serial8250_startup -> **serial_link_irq_chain** の中で request_irq

```c
static int serial_link_irq_chain(struct uart_8250_port *up)
{
	struct irq_info *i = irq_lists + up->port.irq;
	int ret, irq_flags = up->port.flags & UPF_SHARE_IRQ ? SA_SHIRQ : 0;

    // local_irq_disable
    // prempt_disable
	spin_lock_irq(&i->lock);

	if (i->head) {
		list_add(&up->list, i->head);
		spin_unlock_irq(&i->lock);

		ret = 0;
	} else {
		INIT_LIST_HEAD(&up->list);
		i->head = &up->list;
		spin_unlock_irq(&i->lock);
        // local_irq_enable
        // prempt_enable

        // ここ
		ret = request_irq(up->port.irq, serial8250_interrupt,
				  irq_flags, "serial", i);
		if (ret < 0)
			serial_do_unlink(i, up);
	}

	return ret;
}
```

ハードウェア割り込みハンドラの実装は serial8250_interrupt

```c
/*
 * This is the serial driver's interrupt routine.
 *
 * Arjan thinks the old way was overly complex, so it got simplified.
 * Alan disagrees, saying that need the complexity to handle the weird
 * nature of ISA shared interrupts.  (This is a special exception.)
 *
 * In order to handle ISA shared interrupts properly, we need to check
 * that all ports have been serviced, and therefore the ISA interrupt
 * line has been de-asserted.
 *
 * This means we need to loop through all ports. checking that they
 * don't have an interrupt pending.
 */
static irqreturn_t serial8250_interrupt(int irq, void *dev_id, struct pt_regs *regs)
{
	struct irq_info *i = dev_id;
	struct list_head *l, *end = NULL;
	int pass_counter = 0, handled = 0;

	DEBUG_INTR("serial8250_interrupt(%d)...", irq);

	spin_lock(&i->lock);

	l = i->head;
	do {
        // 「ポート」をイテレートして割り込みが無いかを確認
		struct uart_8250_port *up;
		unsigned int iir;

		up = list_entry(l, struct uart_8250_port, list);

        // Interrupt ID Register から読み込み
        // 割り込みがあったかどうかを判定できるのかな?
		iir = serial_in(up, UART_IIR);
		if (!(iir & UART_IIR_NO_INT)) {
			spin_lock(&up->port.lock);
			serial8250_handle_port(up, regs);
			spin_unlock(&up->port.lock);

			handled = 1;

			end = NULL;
		} else if (end == NULL)
			end = l;

		l = l->next;

		if (l == i->head && pass_counter++ > PASS_LIMIT) {
			/* If we hit this, we're dead. */
			printk(KERN_ERR "serial8250: too much work for "
				"irq%d\n", irq);
			break;
		}
	} while (l != end);

	spin_unlock(&i->lock);

	DEBUG_INTR("end.\n");

	return IRQ_RETVAL(handled);
}
```

## 端末制御処理

serial8250_handle_port -> tty_flip_buffer_push -> schedule_delayed_work

work_struct, workqueue_struct 呼び出しに繋がる

```c
/**
 *	tty_flip_buffer_push	-	terminal
 *	@tty: tty to push
 *
 *	Queue a push of the terminal flip buffers to the line discipline. This
 *	function must not be called from IRQ context if tty->low_latency is set.
 *
 *	In the event of the queue being busy for flipping the work will be
 *	held off and retried later.
 */

void tty_flip_buffer_push(struct tty_struct *tty)
{
	if (tty->low_latency)
		flush_to_ldisc((void *) tty);
	else
		schedule_delayed_work (&tty->flip.work, 1);
}

EXPORT_SYMBOL(tty_flip_buffer_push);
```

```c
// プロセスコンテキトで遅延実行する奴
int fastcall schedule_delayed_work(struct work_struct *work, unsigned long delay)
{
    // 他にも使われている可能性がある
    // http://wiki.bit-hive.com/north/pg/%A5%EF%A1%BC%A5%AF%A5%AD%A5%E5%A1%BC
	return queue_delayed_work(keventd_wq, work, delay);
}
```

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

## ksoftirqd

SMP (CPU) の初期化?時に作成されるカーネルスレッド

 * kthread_create でCPUごとに作成される
 * kthread_bind で実行CPUを固定している
   * task_struct の cpus_allowd をセットしてるだけ
   * 固定したCPUからのハードウェア割り込み -> raise_softirq を扱う(はず)
```c
static int __devinit cpu_callback(struct notifier_block *nfb,
				  unsigned long action,
				  void *hcpu)
{
	int hotcpu = (unsigned long)hcpu;
	struct task_struct *p;

	switch (action) {
	case CPU_UP_PREPARE:
		BUG_ON(per_cpu(tasklet_vec, hotcpu).list);
		BUG_ON(per_cpu(tasklet_hi_vec, hotcpu).list);
		p = kthread_create(ksoftirqd, hcpu, "ksoftirqd/%d", hotcpu);
		if (IS_ERR(p)) {
			printk("ksoftirqd for %i failed\n", hotcpu);
			return NOTIFY_BAD;
		}
		kthread_bind(p, hotcpu);
  		per_cpu(ksoftirqd, hotcpu) = p;
 		break;
	case CPU_ONLINE:
		wake_up_process(per_cpu(ksoftirqd, hotcpu));
		break;
```

ksoftirqd のループは下記の通り

 * nice = 20 にセット

```c
static int ksoftirqd(void * __bind_cpu)
{
	set_user_nice(current, 19);
	current->flags |= PF_NOFREEZE;

	set_current_state(TASK_INTERRUPTIBLE);

	while (!kthread_should_stop()) {
		preempt_disable();

        // 起床されるまで待つ
        // wakeup_softirqd を呼ぶと ksoftirqd が起床する
        // https://github.com/hiboma/kernel_module_scratch/tree/master/wake_up_process を読もう
		if (!local_softirq_pending()) {
			preempt_enable_no_resched();
			schedule();

            // wakeup_process で起床〜
			preempt_disable();
		}

		__set_current_state(TASK_RUNNING);

        // pending している sotirq を処理ってく
		while (local_softirq_pending()) {
			/* Preempt disable stops cpu going offline.
			   If already offline, we'll be on wrong CPU:
			   don't process */
			if (cpu_is_offline((long)__bind_cpu))
				goto wait_to_die;

			do_softirq();
			preempt_enable_no_resched();
			cond_resched();
			preempt_disable();
		}
		preempt_enable();
		set_current_state(TASK_INTERRUPTIBLE);
	}
	__set_current_state(TASK_RUNNING);
	return 0;

wait_to_die:
	preempt_enable();
	/* Wait for kthread_stop */
	set_current_state(TASK_INTERRUPTIBLE);
	while (!kthread_should_stop()) {
		schedule();
		set_current_state(TASK_INTERRUPTIBLE);
	}
	__set_current_state(TASK_RUNNING);
	return 0;
}
```

```c
asmlinkage void do_softirq(void)
{
	unsigned long flags;
	struct thread_info *curctx;
	union irq_ctx *irqctx;
	u32 *isp;

	if (in_interrupt())
		return;

	local_irq_save(flags);

	if (local_softirq_pending()) {
		curctx = current_thread_info();
		irqctx = softirq_ctx[smp_processor_id()];
		irqctx->tinfo.task = curctx->task;
		irqctx->tinfo.previous_esp = current_stack_pointer;

        // スタックポインタをごにょごにょ ...
		/* build the stack frame on the softirq stack */
		isp = (u32*) ((char*)irqctx + sizeof(*irqctx));

		asm volatile(
			"       xchgl   %%ebx,%%esp     \n"   // スタックポインタと ebx を交換
			"       call    __do_softirq    \n"   // __do_softirq 呼び出しだ !
			"       movl    %%ebx,%%esp     \n"   // スタックポインタと ebx を元に戻す
			: "=b"(isp)
			: "0"(isp)
			: "memory", "cc", "edx", "ecx", "eax"
		);
	}

	local_irq_restore(flags);
}

EXPORT_SYMBOL(do_softirq);
#endif
```

__do_softirq で pending している sofirq のハンドラを呼び出して具体的な処理に繋がる

```c
asmlinkage void __do_softirq(void)
{
	struct softirq_action *h;
	__u32 pending;
	int max_restart = MAX_SOFTIRQ_RESTART;
	int cpu;

	pending = local_softirq_pending();

    // bottom half を disable ...
	local_bh_disable();
	cpu = smp_processor_id();
restart:
	/* Reset the pending bitmask before enabling irqs */
	set_softirq_pending(0);

	local_irq_enable();

	h = softirq_vec;

	do {
		if (pending & 1) {
            // softirq のハンドラを呼び出して処理
			h->action(h);
			rcu_bh_qsctr_inc(cpu);
		}
		h++;
		pending >>= 1;
	} while (pending);

	local_irq_disable();

	pending = local_softirq_pending();
    // pending している間はループ。 MAX_SOFTIRQ_RESTART 回だけ繰り返す可能性がある
	if (pending && --max_restart)
		goto restart;

    // まだ pending してたらもういっぺん起床させる
    / ただし、スケジューリングを挟むので ksoftirqd がずっと動くって訳じゃない?
	if (pending)
		wakeup_softirqd();

	__local_bh_enable();
```