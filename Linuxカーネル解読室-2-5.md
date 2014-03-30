# 2.5 マスク不可割り込みNMI

> NMIは特殊な用途に利用しています。通常の割り込みは禁止（マスク）することが可能ですが、このNMIは禁止できません。CPUの割り込み禁止（local_irq_enable関数）を行っていても、NMIが発生すると、指定した割り込みハンドラへ実行を移すことができます。

 * CPUの割り込み禁止をシカト
 * 割り込みコントローラーでは?
 * NMIは誰が発生させる?

>　NMIは特殊な目的で利用されます。ハードウェアに依存しますが、メモリのパリティエラー発生の捕捉、ウォッチドッグ、デバッガの強制起動などに利用されます。

>　Intel x86用Linuxでは、LDTに直接NMI用の割り込みハンドラ（nmi関数）を登録しています。NMIが発生するとその時点におけるCPU状態によらず、割り込みハンドラが呼び出されます。

 * LDT ... Local Descriptor Table
   * ????
 * ウォッチドッグ
   * http://ja.wikipedia.org/wiki/ウォッチドッグタイマー

## nmi

```asm
	/* runs on exception stack */
ENTRY(nmi)
	INTR_FRAME
	PARAVIRT_ADJUST_EXCEPTION_FRAME
	pushq_cfi $-1
	subq $15*8, %rsp
	CFI_ADJUST_CFA_OFFSET 15*8
	call save_paranoid
	DEFAULT_FRAME 0
	/* paranoidentry do_nmi, 0; without TRACE_IRQS_OFF */
	movq %rsp,%rdi
	movq $-1,%rsi
	call do_nmi
#ifdef CONFIG_TRACE_IRQFLAGS
	/* paranoidexit; without TRACE_IRQS_OFF */
	/* ebx:	no swapgs flag */
	DISABLE_INTERRUPTS(CLBR_NONE)
	testl %ebx,%ebx				/* swapgs needed? */
	jnz nmi_restore
	testl $3,CS(%rsp)
	jnz nmi_userspace
nmi_swapgs:
	SWAPGS_UNSAFE_STACK
nmi_restore:
	RESTORE_ALL 8
	jmp irq_return
nmi_userspace:
	GET_THREAD_INFO(%rcx)
	movl TI_flags(%rcx),%ebx
	andl $_TIF_WORK_MASK,%ebx
	jz nmi_swapgs
	movq %rsp,%rdi			/* &pt_regs */
	call sync_regs
	movq %rax,%rsp			/* switch stack for scheduling */
	testl $_TIF_NEED_RESCHED,%ebx
	jnz nmi_schedule
	movl %ebx,%edx			/* arg3: thread flags */
	ENABLE_INTERRUPTS(CLBR_NONE)
	xorl %esi,%esi 			/* arg2: oldset */
	movq %rsp,%rdi 			/* arg1: &pt_regs */
	call do_notify_resume
	DISABLE_INTERRUPTS(CLBR_NONE)
	jmp nmi_userspace
nmi_schedule:
	ENABLE_INTERRUPTS(CLBR_ANY)
	call schedule
	DISABLE_INTERRUPTS(CLBR_ANY)
	jmp nmi_userspace
	CFI_ENDPROC
#else
	jmp paranoid_exit
	CFI_ENDPROC
#endif
END(nmi)
```   




