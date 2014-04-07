# 3.1 割り込み処理の遅延

 * ハードウェア割り込みハンドラ
   * 要応答性
 * その他は softirq, tasklet で遅延処理する
   * softirq, tasklet 実行中は割り込み可能なので、ハードウェア割り込みの応答性を確保

## 3.1.1 マルチプロセッサへの対応

 * 同種のハードウェア割り込み単一のCPUでのみ実行可能
 * softirq は並列実行可能
   * ハードウェア割り込みを softirq に委譲させてスケーラビリティを確保m
   * softirqハンドラは、ハードウェア割り込みを受けたCPU上で実行される
     * CPUキャッシュ++

## 3.1.2 ソフト割り込みスタック

 * ハードウェア割り込みがネストする可能性がある
 * 大きめに確保
 * プロセスのスタックを利用 (thread_info)

```
struct thread_info

+------------------------+
|                        |
|          ^             |
|          |             |
+------------------------+
| タイマ割り込みハンドラ |
+------------------------+
|    SCSI割り込み        |
+------------------------+
|    TCP/IP softirq      |
+------------------------+
|                        |
|   システムコール処理   |
|                        |
+------------------------+
```

## 3.1.3 ソフト割り込み


```c
#ifndef __ARCH_IRQ_STAT
extern irq_cpustat_t irq_stat[];		/* defined in asm/hardirq.h */
#define __IRQ_STAT(cpu, member)	(irq_stat[cpu].member)
#endif
```


```c
void open_softirq(int nr, void (*action)(struct softirq_action *))
{
	softirq_vec[nr].action = action;
}

// #!ruby で書いた場合
// 
// softirq_vec[nr] = lambda { ... }
//
```

```c
// linux-2.6.32-431
enum
{
	HI_SOFTIRQ=0,
	TIMER_SOFTIRQ,
	NET_TX_SOFTIRQ,
	NET_RX_SOFTIRQ,
	BLOCK_SOFTIRQ,        // New!
	BLOCK_IOPOLL_SOFTIRQ, // New!
	TASKLET_SOFTIRQ,
	SCHED_SOFTIRQ,        // New!
	HRTIMER_SOFTIRQ,      // New!
	RCU_SOFTIRQ,	/* Preferable RCU should always be the last softirq */

	NR_SOFTIRQS
};
```

### local_bh_disable

```c
void local_bh_disable(void)
{
	__local_bh_disable((unsigned long)__builtin_return_address(0),
				SOFTIRQ_DISABLE_OFFSET);
}
```

### local_bh_enable

```c
void local_bh_enable(void)
{
	_local_bh_enable_ip((unsigned long)__builtin_return_address(0));
}
EXPORT_SYMBOL(local_bh_enable);
```

```c
static inline void _local_bh_enable_ip(unsigned long ip)
{
	WARN_ON_ONCE(in_irq() || irqs_disabled());
#ifdef CONFIG_TRACE_IRQFLAGS
	local_irq_disable();
#endif
	/*
	 * Are softirqs going to be turned on now:
	 */
	if (softirq_count() == SOFTIRQ_DISABLE_OFFSET)
		trace_softirqs_on(ip);
	/*
	 * Keep preemption disabled until we are done with
	 * softirq processing:
 	 */
	sub_preempt_count(SOFTIRQ_DISABLE_OFFSET - 1);

	if (unlikely(!in_interrupt() && local_softirq_pending()))
		do_softirq();

	dec_preempt_count();
#ifdef CONFIG_TRACE_IRQFLAGS
	local_irq_enable();
#endif
	preempt_check_resched();
}
```

## wakeup_softirqd

 * __do_softirq で pending されている sofirq があれば wakeup_softirqd

```
[vagrant@vagrant-centos65 ~]$ ps aux | grep softirq
root         3  0.1  0.0      0     0 ?        S    11:42   0:00 [ksoftirqd/0]
root        13  0.0  0.0      0     0 ?        S    11:42   0:00 [ksoftirqd/1]
root        19  0.0  0.0      0     0 ?        S    11:42   0:00 [ksoftirqd/2]
root        24  0.0  0.0      0     0 ?        S    11:42   0:00 [ksoftirqd/3]
```

```c
/*
 * we cannot loop indefinitely here to avoid userspace starvation,
 * but we also don't want to introduce a worst case 1/HZ latency
 * to the pending events, so lets the scheduler to balance
 * the softirq load for us.
 */
void wakeup_softirqd(void)
{
	/* Interrupts are disabled: no need to stop preemption */
	struct task_struct *tsk = __get_cpu_var(ksoftirqd);

	if (tsk && tsk->state != TASK_RUNNING)
		wake_up_process(tsk);
}
```