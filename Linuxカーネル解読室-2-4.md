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

