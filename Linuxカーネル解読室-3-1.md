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
     * CPU が固定されているのは interrupt -> do_IRQ -> raise_softirq の流れを追えば分かりそう

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
    // すでに 「IRQスタック」にスイッチしている場合
    // 割り込みハンドラを実行している最中に、割り込みを受けた場合を指す様子
	if (unlikely(curctx == irqctx))
		return 0;

	/* build the stack frame on the IRQ stack */
    // スタックフレームを作る
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

    // オーバーフローしそうな場合?
    //     printk(KERN_WARNING "low stack detected by irq handler\n");
    // てなメッセージを出す様子
	if (unlikely(overflow))
		call_on_stack(print_stack_overflow, isp);

	asm volatile("xchgl	%%ebx,%%esp	\n"       // esp と ebx を交換
		     "call	*%%edi		\n"           // desc->handle_irq を call
		     "movl	%%ebx,%%esp	\n"           // esp を ebx に戻す
		     : "=a" (arg1), "=d" (arg2), "=b" (isp)
		     :  "0" (irq),   "1" (desc),  "2" (isp),
			"D" (desc->handle_irq)
		     : "memory", "cc", "ecx");
	return 1;
}
```

## 3.1.3 ソフト割り込み

 * open_softirq で softirq_vec にハンドラを登録する
 * ハンドラの実体は softirq_action

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

softirq_action の中身は下記の通り。 alias 的に使われるだけの struct

```c
struct softirq_action
{
	void	(*action)(struct softirq_action *);
};
```

irq_stat テーブル

```c
#ifndef __ARCH_IRQ_STAT
extern irq_cpustat_t irq_stat[];		/* defined in asm/hardirq.h */
#define __IRQ_STAT(cpu, member)	(irq_stat[cpu].member)
#endif
```

> Linuxカーネル2.6 には、6種類のソフト割り込み種別があります

2.6.32-431 ではもっと多い

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

## 3.1.3.2 ソフト割り込みの制御

 * local_bh_disable, local_bh_enable
   * システムコールと softirq とで競合するリソースを保護する場合に使う
   * 実行したCPU でのみ softirq が 保留 = pending される
   * 他の CPU では softirq ハンドラが実行される
 * ハードウェア割り込みを禁止すると softirq も禁止される
   * raise_softirq するのはハードウェア割り込みハンドラからだけ、というルールから導き出せる

 * local_bh_disable
```c
void local_bh_disable(void)
{
	__local_bh_disable((unsigned long)__builtin_return_address(0),
				SOFTIRQ_DISABLE_OFFSET);
}

static inline void __local_bh_disable(unsigned long ip, unsigned int cnt)
{
    // thread_info->preempt_count に cnt を足す
	add_preempt_count(cnt);
	barrier();
}
```

 * local_bh_enable
```c
void local_bh_enable(void)
{
	_local_bh_enable_ip((unsigned long)__builtin_return_address(0));
}
EXPORT_SYMBOL(local_bh_enable);

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

    // 割り込みコンテキストではない + pending している softirq があったら do_softirq でやっつける
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

何度も見たので ok

 * wake_up_process で ksoftirqd が起床するけど、スケジューリングされるまでは他のプロセスが実行されているのがミソかな

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