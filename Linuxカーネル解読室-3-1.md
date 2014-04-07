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
   * プロセスのスタックを利用 (thread_info)
   * 大きめに確保してスタックオーバーフローを防ぐ

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
+------------------------+ <--- ここから上が割り込みのスタック
|                        |
|   システムコール処理   |
|                        |
+------------------------+
```

割り込みハンドラがプロセスのスタックを乗っ取って動くのは execute_on_irq_stack を見ると分かる

```c
static inline int
execute_on_irq_stack(int overflow, struct irq_desc *desc, int irq)
{
	union irq_ctx *curctx, *irqctx;
	u32 *isp, arg1, arg2;

    // /*
    //  * per-CPU IRQ handling contexts (thread information and stack)
    //  */
    // union irq_ctx {
    // 	struct thread_info      tinfo;
    // 	u32                     stack[THREAD_SIZE/sizeof(u32)];
    // } __attribute__((aligned(PAGE_SIZE)));
    //
	curctx = (union irq_ctx *) current_thread_info();

    // ?
	irqctx = __get_cpu_var(hardirq_ctx);

	/*
	 * this is where we switch to the IRQ stack. However, if we are
	 * already using the IRQ stack (because we interrupted a hardirq
	 * handler) we can't do that and just have to keep using the
	 * current stack (which is the irq stack already after all)
	 */
	if (unlikely(curctx == irqctx))
		return 0;

	/* build the stack frame on the IRQ stack */
	isp = (u32 *) ((char *)irqctx + sizeof(*irqctx));
	irqctx->tinfo.task = curctx->tinfo.task;
	irqctx->tinfo.previous_esp = current_stack_pointer;

	/*
	 * Copy the softirq bits in preempt_count so that the
	 * softirq checks work in the hardirq context.
	 */
	irqctx->tinfo.preempt_count =
		(irqctx->tinfo.preempt_count & ~SOFTIRQ_MASK) |
		(curctx->tinfo.preempt_count & SOFTIRQ_MASK);

	if (unlikely(overflow))
		call_on_stack(print_stack_overflow, isp);

	asm volatile("xchgl	%%ebx,%%esp	\n"
		     "call	*%%edi		\n"
		     "movl	%%ebx,%%esp	\n"
		     : "=a" (arg1), "=d" (arg2), "=b" (isp)
		     :  "0" (irq),   "1" (desc),  "2" (isp),
			"D" (desc->handle_irq)
		     : "memory", "cc", "ecx");
	return 1;
}
```

## 3.1.3 ソフト割り込み


```c
struct softirq_action
{
	void	(*action)(struct softirq_action *);
};
```

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