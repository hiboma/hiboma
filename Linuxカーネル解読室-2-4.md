# 2.4 プロセッサ間割り込み

 * 要APIC

## send_IPI 群

プロセッサ間割り込み Inter Processor Interrupts

 * 下のは IA64 だった ...
 * x86 だと arch/x86/kernel/apic/ 以下を見る必要がある?

```c
/*
 * Called with preemption disabled.
 */
static inline void
send_IPI_single (int dest_cpu, int op)
{
    // ipi_operation CPUキャッシュのアラインのために DEFINE_PER_CPU_SHARED_ALIGNED でごにょごにょ
    // dest_cpu の per_cpu に op ビットを立てる
	set_bit(op, &per_cpu(ipi_operation, dest_cpu));

    // 役割に応じて割り込みベクタの定数が複数設定されている
    //
    //     #define IA64_IPI_LOCAL_TLB_FLUSH	0xfc	/* SMP flush local TLB */
    //     #define IA64_IPI_RESCHEDULE		0xfd	/* SMP reschedule */
    //     #define IA64_IPI_VECTOR			0xfe	/* inter-processor interrupt vector */
    //
    // 外部割り込みを pending させながら IPI を送る?
    //
    //     IA64_IPI_DM_INT =       0x0,    /* pend an external interrupt */
    //
	platform_send_ipi(dest_cpu, IA64_IPI_VECTOR, IA64_IPI_DM_INT, 0);
}
```

 * send_IPI_mask cpumask で指定した CPU だけに IPI を飛ばす
 * send_IPI_all  全部の CPU に飛ばす
 * send_IPI_self , send_IPI_allbutself など

## 割り込みハンドラの登録

arch/x86/kernel/entry_64.S

```asm
#ifdef CONFIG_SMP
apicinterrupt CALL_FUNCTION_SINGLE_VECTOR \
	call_function_single_interrupt smp_call_function_single_interrupt
apicinterrupt CALL_FUNCTION_VECTOR \
	call_function_interrupt smp_call_function_interrupt
apicinterrupt RESCHEDULE_VECTOR \
	reschedule_interrupt smp_reschedule_interrupt
#endif
```

```c
static void __init smp_intr_init(void)
{
#ifdef CONFIG_SMP
#if defined(CONFIG_X86_64) || defined(CONFIG_X86_LOCAL_APIC)
	/*
	 * The reschedule interrupt is a CPU-to-CPU reschedule-helper
	 * IPI, driven by wakeup.
	 */
	alloc_intr_gate(RESCHEDULE_VECTOR, reschedule_interrupt);

	/* IPIs for invalidation */
	alloc_intr_gate(INVALIDATE_TLB_VECTOR_START+0, invalidate_interrupt0);
	alloc_intr_gate(INVALIDATE_TLB_VECTOR_START+1, invalidate_interrupt1);
	alloc_intr_gate(INVALIDATE_TLB_VECTOR_START+2, invalidate_interrupt2);
	alloc_intr_gate(INVALIDATE_TLB_VECTOR_START+3, invalidate_interrupt3);
	alloc_intr_gate(INVALIDATE_TLB_VECTOR_START+4, invalidate_interrupt4);
	alloc_intr_gate(INVALIDATE_TLB_VECTOR_START+5, invalidate_interrupt5);
	alloc_intr_gate(INVALIDATE_TLB_VECTOR_START+6, invalidate_interrupt6);
	alloc_intr_gate(INVALIDATE_TLB_VECTOR_START+7, invalidate_interrupt7);

	/* IPI for generic function call */
	alloc_intr_gate(CALL_FUNCTION_VECTOR, call_function_interrupt);

	/* IPI for generic single function call */
	alloc_intr_gate(CALL_FUNCTION_SINGLE_VECTOR,
			call_function_single_interrupt);

	/* Low priority IPI to cleanup after moving an irq */
	set_intr_gate(IRQ_MOVE_CLEANUP_VECTOR, irq_move_cleanup_interrupt);
	set_bit(IRQ_MOVE_CLEANUP_VECTOR, used_vectors);

	/* IPI used for rebooting/stopping */
	alloc_intr_gate(REBOOT_VECTOR, reboot_interrupt);
#endif
#endif /* CONFIG_SMP */
}
```

## smp_reschedule_interrupt

プロセス再スケジュール要求を出す IPI の割り込みハンドラ

### Top Half

```c
void smp_reschedule_interrupt(struct pt_regs *regs)
{
    // ACK を出して、割り込みを可にする
	ack_APIC_irq();
	__smp_reschedule_interrupt();
	/*
	 * KVM uses this interrupt to force a cpu out of guest mode
	 */
}
```

/proc/interrupts の統計をインクリメント

```c
/*
 * Reschedule call back. Nothing to do,
 * all the work is done automatically when
 * we return from the interrupt.
 */
static inline void __smp_reschedule_interrupt(void)
{
	inc_irq_stat(irq_resched_count);
	scheduler_ipi();
}
```

SCHED_SOFTIRQ に繋げて softirq として処理

```c
void scheduler_ipi(void)
{
	if (!got_nohz_idle_kick())
		return;

	/*
	 * Not all reschedule IPI handlers call irq_enter/irq_exit, since
	 * traditionally all their work was done from the interrupt return
	 * path. Now that we actually do some work, we need to make sure
	 * we do call them.
	 *
	 * Some archs already do call them, luckily irq_enter/exit nest
	 * properly.
	 *
	 * Arguably we should visit all archs and update all handlers,
	 * however a fair share of IPIs are still resched only so this would
	 * somewhat pessimize the simple resched case.
	 */
	irq_enter();
	/*
	 * Check if someone kicked us for doing the nohz idle load balance.
	 */
	if (unlikely(got_nohz_idle_kick() && !need_resched()))
		raise_softirq_irqoff(SCHED_SOFTIRQ);

    // ここで softirq をやっつける
	irq_exit();
}
```

### Bottom Half

sched.c

```c
#ifdef CONFIG_SMP
	open_softirq(SCHED_SOFTIRQ, run_rebalance_domains);
#endif
```

rebalance_domains が SCHED_SOFTIRQ の実装らしい

```c
/*
 * run_rebalance_domains is triggered when needed from the scheduler tick.
 * Also triggered for nohz idle balancing (with nohz_balancing_kick set).
 */
static void run_rebalance_domains(struct softirq_action *h)
{
	int this_cpu = smp_processor_id();
	struct rq *this_rq = cpu_rq(this_cpu);
	enum cpu_idle_type idle = this_rq->idle_at_tick ?
						CPU_IDLE : CPU_NOT_IDLE;

	rebalance_domains(this_cpu, idle);

	/*
	 * If this cpu has a pending nohz_balance_kick, then do the
	 * balancing on behalf of the other idle cpus whose ticks are
	 * stopped.
	 */
	nohz_idle_balance(this_cpu, idle);
}
```

## smp_invalidate_interrupt

 * flush_tlb_current_task
 * local_flush_mm
 * local_flush_page

```c
/*
 * FIXME: use of asmlinkage is not consistent.  On x86_64 it's noop
 * but still used for documentation purpose but the usage is slightly
 * inconsistent.  On x86_32, asmlinkage is regparm(0) but interrupt
 * entry calls in with the first parameter in %eax.  Maybe define
 * intrlinkage?
 */
#ifdef CONFIG_X86_64
asmlinkage
#endif
void smp_invalidate_interrupt(struct pt_regs *regs)
{
	unsigned int cpu;
	unsigned int sender;
	union smp_flush_state *f;

	cpu = smp_processor_id();

#ifdef CONFIG_X86_32
	if (current->active_mm)
		load_user_cs_desc(cpu, current->active_mm);
#endif

	/*
	 * orig_rax contains the negated interrupt vector.
	 * Use that to determine where the sender put the data.
	 */
	sender = ~regs->orig_ax - INVALIDATE_TLB_VECTOR_START;
	f = &flush_state[sender];

	if (!cpumask_test_cpu(cpu, to_cpumask(f->flush_cpumask)))
		goto out;
		/*
		 * This was a BUG() but until someone can quote me the
		 * line from the intel manual that guarantees an IPI to
		 * multiple CPUs is retried _only_ on the erroring CPUs
		 * its staying as a return
		 *
		 * BUG();
		 */

	if (f->flush_mm == percpu_read(cpu_tlbstate.active_mm)) {
		if (percpu_read(cpu_tlbstate.state) == TLBSTATE_OK) {
			if (f->flush_va == TLB_FLUSH_ALL)
				local_flush_tlb();
			else
				__flush_tlb_one(f->flush_va);
		} else
			leave_mm(cpu);
	}
out:
	ack_APIC_irq();
	smp_mb__before_clear_bit();
	cpumask_clear_cpu(cpu, to_cpumask(f->flush_cpumask));
	smp_mb__after_clear_bit();
	inc_irq_stat(irq_tlb_count);
}
``` 