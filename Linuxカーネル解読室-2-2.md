## 2.2.1 応答性の確保

> 伝統UNIXでは、応答性を確保するために割り込みレベルという考え方を採用していました

高優先度の割り込みがネストすることを許可する
 
  * Linux
    * 応答性が必要     ... ハードゥエア割り込みハンドラ
    * 応答性が必要ない ... 遅延実行、ソフト割り込み (ソフトIRQ)

```    
int
request_irq(unsigned int irq, irqreturn_t (*handler)(int, void *, struct pt_regs *),
	    unsigned long irqflags, const char * devname, void *dev_id)
```    

## イーサネットドライバ処理

 * http://wiki.bit-hive.com/linuxkernelmemo/pg/%C1%F7%BC%F5%BF%AE
 * [Interl PRO/1000](http://www.amazon.co.jp/dp/B000BMZHX2)

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
 * ハンドラの実行を終えたら IRQ_HANDLED を返す
 * CONFIG_E1000_MQ
   * Multiple Queue
   * 割り込み処理を複数CPUに分散させるやつ
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
		__netif_rx_schedule(poll_dev);
	else
		e1000_irq_enable(adapter);

	put_cpu();
}
#endif
```

## SCSIホストバスアダプタドライバ処理

## シリアルドライバ処理	

## TCP/IPプロトコル処理

## SCSIプロトコル処理

## 端末制御処理    



