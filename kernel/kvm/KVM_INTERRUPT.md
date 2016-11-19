# KVM_INTERRUPT

## Documentation

https://www.kernel.org/doc/Documentation/virtual/kvm/api.txt

```
4.16 KVM_INTERRUPT

Capability: basic
Architectures: x86, ppc, mips
Type: vcpu ioctl
Parameters: struct kvm_interrupt (in)
Returns: 0 on success, negative on failure.

Queues a hardware interrupt vector to be injected.

/* for KVM_INTERRUPT */
struct kvm_interrupt {
	/* in */
	__u32 irq; // 割り込みベクタ
};

X86:

Returns: 0 on success,
	 -EEXIST if an interrupt is already enqueued
	 -EINVAL the the irq number is invalid
	 -ENXIO if the PIC is in the kernel
	 -EFAULT if the pointer is invalid

Note 'irq' is an interrupt vector, not an interrupt pin or line. This
ioctl is useful if the in-kernel PIC is not used.

PPC:

Queues an external interrupt to be injected. This ioctl is overleaded
with 3 different irq values:
```

 * in-kernel PIC (KVM_CREATE_IRQCHIP で作る) が無い場合に useful
 * VMCS_ENTRY に割り込み情報を書くのが一番の肝?

x86 の場合、kvm_queued_interrupt で interrupt をキューイングできる

```c
struct kvm_vcpu_arch {

...

	struct kvm_queued_exception {
		bool pending;
		bool has_error_code;
		bool reinject;
		u8 nr;
		u32 error_code;
	} exception;

	struct kvm_queued_interrupt { ★
		bool pending;
		bool soft;
		u8 nr;
	} interrupt;
```

## interrupt の queueing と clear の API

 * pending しているか否か
 * ソフト割り込みか、外部割り込みか
 * 割り込みベクタ

```c
static inline void kvm_queue_interrupt(struct kvm_vcpu *vcpu, u8 vector,
	bool soft)
{
	vcpu->arch.interrupt.pending = true;
	vcpu->arch.interrupt.soft = soft;
	vcpu->arch.interrupt.nr = vector;
}
```

解除するときは pending = false にするだけ

```c
static inline void kvm_clear_interrupt_queue(struct kvm_vcpu *vcpu)
{
	vcpu->arch.interrupt.pending = false;
}
```

## kvm_queue_interrupt の呼び出し

vCPU の fd に ioctl(2) + KVM_INTERRUPT を読んで、ホストからシステムコールで interrupt をキューイングできる ( VM exit しているので vCPU は止まっている ) 

```c
long kvm_arch_vcpu_ioctl(struct file *filp,
			 unsigned int ioctl, unsigned long arg)
{
	struct kvm_vcpu *vcpu = filp->private_data;
	void __user *argp = (void __user *)arg;
	int r;
	union {
		struct kvm_lapic_state *lapic;
		struct kvm_xsave *xsave;
		struct kvm_xcrs *xcrs;
		void *buffer;
	} u;

	u.buffer = NULL;
	switch (ioctl) {

...

	case KVM_INTERRUPT: {
		struct kvm_interrupt irq;

		r = -EFAULT;
		if (copy_from_user(&irq, argp, sizeof irq))
			goto out;
		r = kvm_vcpu_ioctl_interrupt(vcpu, &irq); ★
		break;
```

```c
static int kvm_vcpu_ioctl_interrupt(struct kvm_vcpu *vcpu,
				    struct kvm_interrupt *irq)
{
	if (irq->irq >= KVM_NR_INTERRUPTS)
		return -EINVAL;
	if (irqchip_in_kernel(vcpu->kvm))
		return -ENXIO;

	kvm_queue_interrupt(vcpu, irq->irq, false);
	kvm_make_request(KVM_REQ_EVENT, vcpu);

	return 0;
}
```

## interrupt injection

kvm_make_request でリクエストイベントを出しておく

```c
static int inject_pending_event(struct kvm_vcpu *vcpu, bool req_int_win)
{
	int r;

	/* try to reinject previous events if any */
	if (vcpu->arch.exception.pending) {
...
    }

	if (vcpu->arch.nmi_injected) {
...    
	}

	if (vcpu->arch.interrupt.pending) {
		kvm_x86_ops->set_irq(vcpu); ★
		return 0;
    }

	/* try to inject new event if pending */
	if (vcpu->arch.nmi_pending) {
...
	} else if (kvm_cpu_has_injectable_intr(vcpu)) {
		/*
		 * TODO/FIXME: We are calling check_nested_events again
		 * here to avoid a race condition. We should really be
		 * setting KVM_REQ_EVENT only on certain events
		 * and not unconditionally.
		 * See https://lkml.org/lkml/2014/7/2/60 for discussion
		 * about this proposal and current concerns
		 */

        // static inline bool is_guest_mode(struct kvm_vcpu *vcpu)
        // {
        // 	return vcpu->arch.hflags & HF_GUEST_MASK;
        // }
		if (is_guest_mode(vcpu) && kvm_x86_ops->check_nested_events) {
			r = kvm_x86_ops->check_nested_events(vcpu, req_int_win);
			if (r != 0)
				return r;
		}

        // static int vmx_interrupt_allowed(struct kvm_vcpu *vcpu)
        // {
        // 	return (!to_vmx(vcpu)->nested.nested_run_pending &&
        // 		vmcs_readl(GUEST_RFLAGS) & X86_EFLAGS_IF) &&
        // 		!(vmcs_read32(GUEST_INTERRUPTIBILITY_INFO) &
        // 			(GUEST_INTR_STATE_STI | GUEST_INTR_STATE_MOV_SS));
        // }
		if (kvm_x86_ops->interrupt_allowed(vcpu)) {
			kvm_queue_interrupt(vcpu, kvm_cpu_get_interrupt(vcpu),
					    false); ★
			kvm_x86_ops->set_irq(vcpu); ★
		}
	}
	return 0;
}
```

## set_irq: arch/x86/kvm/vmx.c 

```c
static struct kvm_x86_ops vmx_x86_ops = {

	.set_irq = vmx_inject_irq,

```

割り込み情報を VMCS_ENTRY フィールドに書き込む

```c
static void vmx_inject_irq(struct kvm_vcpu *vcpu)
{
	struct vcpu_vmx *vmx = to_vmx(vcpu);
	uint32_t intr;
	int irq = vcpu->arch.interrupt.nr;

	trace_kvm_inj_virq(irq);

    // 統計を持っている irq_injection をした回数
	++vcpu->stat.irq_injections;

	if (vmx->rmode.vm86_active) {
		int inc_eip = 0;
		if (vcpu->arch.interrupt.soft)
			inc_eip = vcpu->arch.event_exit_inst_len;
		if (kvm_inject_realmode_interrupt(vcpu, irq, inc_eip) != EMULATE_DONE)
			kvm_make_request(KVM_REQ_TRIPLE_FAULT, vcpu);
		return;
	}
	intr = irq | INTR_INFO_VALID_MASK;

    // キューイングされている割り込みがソフト割り込みの場合
	if (vcpu->arch.interrupt.soft) {
		intr |= INTR_TYPE_SOFT_INTR;
        // VMCS に書いておく 
		vmcs_write32(VM_ENTRY_INSTRUCTION_LEN,
			     vmx->vcpu.arch.event_exit_inst_len);
	} else
        // 外部割り込みの場合 デバイス等々
		intr |= INTR_TYPE_EXT_INTR;
    // VMCS に割り込みベクタ? を書いておく
	vmcs_write32(VM_ENTRY_INTR_INFO_FIELD, intr);
}
```

# inject した割り込みが VM のどこで処理されるか?

## vcpu_enter_guest

```c
// ioctl(2) + vCPU + KVM_RUN
//  kvm_vcpu_ioctl + KVM_RUN
//   kvm_arch_vcpu_ioctl_run
//    __vcpu_run
/*
 * Returns 1 to let __vcpu_run() continue the guest execution loop without
 * exiting to the userspace.  Otherwise, the value will be returned to the
 * userspace.
 */
static int vcpu_enter_guest(struct kvm_vcpu *vcpu)
{
	int r;
	bool req_int_win = !irqchip_in_kernel(vcpu->kvm) &&
		vcpu->run->request_interrupt_window;
	bool req_immediate_exit = false;

...

		if (inject_pending_event(vcpu, req_int_win) != 0)
			req_immediate_exit = true;
		/* enable NMI/IRQ window open exits if needed */
```

VMRESUME でゲストに制御が戻った後は、CPU が VMCS をよしなに扱って割り込みをエミュレートしてくれる (Linux カーネルの実装ではない?)

## kvm_arch_pre_run

kvm_cpu_exec -> ( KVM_RUN も読むべし )

```c
void kvm_arch_pre_run(CPUState *cpu, struct kvm_run *run)
{
    X86CPU *x86_cpu = X86_CPU(cpu);
    CPUX86State *env = &x86_cpu->env;
    int ret;

    // 優先度 NMI > SMI > INTERRUPT となっている
    /* Inject NMI */
    if (cpu->interrupt_request & (CPU_INTERRUPT_NMI | CPU_INTERRUPT_SMI)) {
        if (cpu->interrupt_request & CPU_INTERRUPT_NMI) {
            qemu_mutex_lock_iothread();
            cpu->interrupt_request &= ~CPU_INTERRUPT_NMI;
            qemu_mutex_unlock_iothread();
            DPRINTF("injected NMI\n");
            ret = kvm_vcpu_ioctl(cpu, KVM_NMI); 
            if (ret < 0) {
                fprintf(stderr, "KVM: injection failed, NMI lost (%s)\n",
                        strerror(-ret));
            }
        }

        // SMI は System management interrupts
        // CPU は SMM (System Management Mode) にはいる
        if (cpu->interrupt_request & CPU_INTERRUPT_SMI) {
            qemu_mutex_lock_iothread();
            cpu->interrupt_request &= ~CPU_INTERRUPT_SMI;
            qemu_mutex_unlock_iothread();
            DPRINTF("injected SMI\n");
            ret = kvm_vcpu_ioctl(cpu, KVM_SMI);
            if (ret < 0) {
                fprintf(stderr, "KVM: injection failed, SMI lost (%s)\n",
                        strerror(-ret));
            }
        }
    }

    // KVM_CREATE_IRQCHIP = in-kernel IRQ でない場合、 IO スレッドを止める
    // vCPU も停止、IOスレッドも停止
    if (!kvm_pic_in_kernel()) {
        qemu_mutex_lock_iothread();
    }

    /* Force the VCPU out of its inner loop to process any INIT requests
     * or (for userspace APIC, but it is cheap to combine the checks here)
     * pending TPR access reports.
     */
    if (cpu->interrupt_request & (CPU_INTERRUPT_INIT | CPU_INTERRUPT_TPR)) {
        if ((cpu->interrupt_request & CPU_INTERRUPT_INIT) &&
            !(env->hflags & HF_SMM_MASK)) {
            cpu->exit_request = 1;
        }
        if (cpu->interrupt_request & CPU_INTERRUPT_TPR) {
            cpu->exit_request = 1;
        }
    }

    // KVM_CREATE_IRQCHIP してない = in-kernel IRQ じゃない場合
    // qem-kvm が同期的に IRQ を配信する必要がある
    if (!kvm_pic_in_kernel()) {
        // CPU_INTERRUPT_HARD なので ハードウェア割り込み だけ KVM_INTERRUPT で受け付ける?
        /* Try to inject an interrupt if the guest can accept it */
        if (run->ready_for_interrupt_injection &&
            (cpu->interrupt_request & CPU_INTERRUPT_HARD) &&
            (env->eflags & IF_MASK)) {
            int irq;

            cpu->interrupt_request &= ~CPU_INTERRUPT_HARD;
            irq = cpu_get_pic_interrupt(env);
            if (irq >= 0) {
                struct kvm_interrupt intr;

                intr.irq = irq;
                DPRINTF("injected interrupt %d\n", irq);
                ret = kvm_vcpu_ioctl(cpu, KVM_INTERRUPT, &intr);
                if (ret < 0) {
                    fprintf(stderr,
                            "KVM: injection failed, interrupt lost (%s)\n",
                            strerror(-ret));
                }
            }
        }

        /* If we have an interrupt but the guest is not ready to receive an
         * interrupt, request an interrupt window exit.  This will
         * cause a return to userspace as soon as the guest is ready to
         * receive interrupts. */
        if ((cpu->interrupt_request & CPU_INTERRUPT_HARD)) {
            run->request_interrupt_window = 1;
        } else {
            run->request_interrupt_window = 0;
        }

        DPRINTF("setting tpr\n");
        run->cr8 = cpu_get_apic_tpr(x86_cpu->apic_state);

        qemu_mutex_unlock_iothread();
    }
```