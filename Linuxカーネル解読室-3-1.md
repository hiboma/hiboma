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

要点

 * 割り込みコンテキストで処理しきれない softirq を、カーネルスレッドに処理させる
   * softirq がえんえんと実行されるのを防ぐ
 * スレッドの優先度は低い

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

## 3.1.3.4 ソフト割り込みの実装

 * do_IRQ でハードウェア割り込みハンドラを実行後 irq_exit する際に do_softirq でソフト割り込みハンドラを実行
 * ソフト割り込みハンドラ実行中は local_irq_enable なので softirq を更に pending 可能
 * pending している softirq 処理が MAX_SOFTIRQ_RESTART 回を超えたら wakeup_softirqd を起床

```c
asmlinkage void do_softirq(void)
{
 	__u32 pending;
 	unsigned long flags;

 	if (in_interrupt())
 		return;

    // cli命令でハードウェア割り込み禁止 (1)
 	local_irq_save(flags);

    // pending されている softirq (2)
 	pending = local_softirq_pending();
 	/* Switch to interrupt stack */
 	if (pending)
		call_softirq();

    // popfl で EFLAGS を復帰 (3)
 	local_irq_restore(flags); 
}
EXPORT_SYMBOL(do_softirq);
```

```c
asmlinkage void __do_softirq(void)
{
	struct softirq_action *h;
	__u32 pending;
    // 10回
	int max_restart = MAX_SOFTIRQ_RESTART;
	int cpu;

	pending = local_softirq_pending();

    // softirq を禁止 (5)
	local_bh_disable();
	cpu = smp_processor_id();
restart:
	/* Reset the pending bitmask before enabling irqs */
	set_softirq_pending(0);

    // sti命令でハードウェア割り込みを許可 (7)
	local_irq_enable();

	h = softirq_vec;

	do {
		if (pending & 1) {

            // open_softirq で定義した softirq のハンドラ (8)
			h->action(h);
			rcu_bh_qsctr_inc(cpu);
		}
		h++;
		pending >>= 1;
	} while (pending);

	local_irq_disable();

    // softirq ハンドラ実行中にハードウェア割り込みが発生、 pending されている softirq がある場合は
    // もういっぺんやり直し (11)
	pending = local_softirq_pending();
	if (pending && --max_restart)
		goto restart;

    // (12)
	if (pending)
		wakeup_softirqd();

    // (13) softirq を許可
	__local_bh_enable();
}
```

## 3.1.4 tasklet

https://github.com/hiboma/kernel_module_scratch/tree/master/tasklet

 * ソフト割り込みハンドラの拡張
 * 任意の関数を実行可能

> taslet_vec に登録されている関数群を順番に実行していきます。 taslet_vec は、CPUごとに用意されており

実体は DEFINE_PER_CPU で定義されている2重リンクリスト

```c
// kernel/softirq.c
/*
 * Tasklets
 */
struct tasklet_head
{
	struct tasklet_struct *head;
	struct tasklet_struct **tail;
};

// TASKLET_SOFTIRQ 用
static DEFINE_PER_CPU(struct tasklet_head, tasklet_vec);

// HI_SOFTIRQ 用
static DEFINE_PER_CPU(struct tasklet_head, tasklet_hi_vec);
```

 * HI_SOFTIRQ
   * 優先度が一番高い
   * tasklet_hi_schedule で raise_softirq_irqoff
 * TASKLET_SOFTIRQ
   * 優先度が一番低い
   * tasklet_schedule で raise_softirq_irqoff

## 3.1.4.2 tasklet の実行

> tasklet の起動要求は tasklet_schedule 関数で行います

softirq を pending させておいて、しかるべきタイミングで実行される

```c
void __tasklet_schedule(struct tasklet_struct *t)
{
	unsigned long flags;

    // tasklet_vec は 割り込みハンドラからも操作されるので local_irq_save して保護
	local_irq_save(flags);
	t->next = NULL;

    // cpu var の tasklet_vec の末尾に突っ込む
	*__get_cpu_var(tasklet_vec).tail = t;
	__get_cpu_var(tasklet_vec).tail = &(t->next);
    // IRQ が disabled された状態で呼び出す API
    // local_irq_save してから他にもごそごそしたい場合に raise_softirq ではなくこっちを使う
	raise_softirq_irqoff(TASKLET_SOFTIRQ);
	local_irq_restore(flags);
}
```

> tasklet_action 関数は、tasklet_vec に登録された処理を順番に実行していきます

tasklet_action は softirq_init で登録されている

```c
void __init softirq_init(void)
{
	int cpu;

    // 各CPUごとに tasklet_vec しの初期化
	for_each_possible_cpu(cpu) {
		int i;

		per_cpu(tasklet_vec, cpu).tail =
			&per_cpu(tasklet_vec, cpu).head;
		per_cpu(tasklet_hi_vec, cpu).tail =
			&per_cpu(tasklet_hi_vec, cpu).head;
		for (i = 0; i < NR_SOFTIRQS; i++)
			INIT_LIST_HEAD(&per_cpu(softirq_work_list[i], cpu));
	}

	register_hotcpu_notifier(&remote_softirq_cpu_notifier);

    // ここね
	open_softirq(TASKLET_SOFTIRQ, tasklet_action);
    // HI の方
	open_softirq(HI_SOFTIRQ, tasklet_hi_action);
}
```

```c
static void tasklet_action(struct softirq_action *a)
{
	struct tasklet_struct *list;

	local_irq_disable();
    // tasklet_vec から先頭だけ取り出す
	list = __get_cpu_var(tasklet_vec).head;
	__get_cpu_var(tasklet_vec).head = NULL;
	__get_cpu_var(tasklet_vec).tail = &__get_cpu_var(tasklet_vec).head;
	local_irq_enable();

	while (list) {
		struct tasklet_struct *t = list;

        // リストが無くなるまでひたすら続ける
		list = list->next;

		if (tasklet_trylock(t)) {
			if (!atomic_read(&t->count)) {
				if (!test_and_clear_bit(TASKLET_STATE_SCHED, &t->state))
					BUG();

                // ここで tasklet の実行
				t->func(t->data);
				tasklet_unlock(t);
				continue;
			}
			tasklet_unlock(t);
		}

		local_irq_disable();
		t->next = NULL;
		*__get_cpu_var(tasklet_vec).tail = t;
		__get_cpu_var(tasklet_vec).tail = &(t->next);
        // ???
		__raise_softirq_irqoff(TASKLET_SOFTIRQ);
		local_irq_enable();
	}
}
```