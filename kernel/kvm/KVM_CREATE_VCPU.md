# KVM_CREATE_VCPU

## Documentation

https://kernel.org/doc/Documentation/virtual/kvm/api.txt

```
2. File descriptors
-------------------

The kvm API is centered around file descriptors.  An initial
open("/dev/kvm") obtains a handle to the kvm subsystem; this handle
can be used to issue system ioctls.  A KVM_CREATE_VM ioctl on this
handle will create a VM file descriptor which can be used to issue VM
ioctls.  A KVM_CREATE_VCPU ioctl on a VM fd will create a virtual cpu
and return a file descriptor pointing to it.  Finally, ioctls on a vcpu
fd can be used to control the vcpu, including the important task of
actually running guest code.

In general file descriptors can be migrated among processes by means
of fork() and the SCM_RIGHTS facility of unix domain socket.  These
kinds of tricks are explicitly not supported by kvm.  While they will
not cause harm to the host, their actual behavior is not guaranteed by
the API.  The only supported use is one virtual machine per process,
and one vcpu per thread.
```

 * ioctl(2) `/dev/kvm` + KVM_CREATE_VM は ***anon_inode kvm-vm*** を返す
 * ioctl(2) `anon_inode kvm-vm` + KVM_CREATE_VCPU は ***anon_inode kvm-vcpu*** を返す
 * fork(2) と UNIX Domain Socket の SCM_RIGHTS での migrate には対応しない

```
4.7 KVM_CREATE_VCPU

Capability: basic
Architectures: all
Type: vm ioctl
Parameters: vcpu id (apic id on x86)
Returns: vcpu fd on success, -1 on error

This API adds a vcpu to a virtual machine. No more than max_vcpus may be added.
The vcpu id is an integer in the range [0, max_vcpu_id).

The recommended max_vcpus value can be retrieved using the KVM_CAP_NR_VCPUS of
the KVM_CHECK_EXTENSION ioctl() at run-time.
The maximum possible value for max_vcpus can be retrieved using the
KVM_CAP_MAX_VCPUS of the KVM_CHECK_EXTENSION ioctl() at run-time.

If the KVM_CAP_NR_VCPUS does not exist, you should assume that max_vcpus is 4
cpus max.
If the KVM_CAP_MAX_VCPUS does not exist, you should assume that max_vcpus is
same as the value returned from KVM_CAP_NR_VCPUS.

The maximum possible value for max_vcpu_id can be retrieved using the
KVM_CAP_MAX_VCPU_ID of the KVM_CHECK_EXTENSION ioctl() at run-time.

If the KVM_CAP_MAX_VCPU_ID does not exist, you should assume that max_vcpu_id
is the same as the value returned from KVM_CAP_MAX_VCPUS.
```

 * VM に vcpu を追加する API
 * max_vcpu が最大
   * vcpu の id は `[0, max_vcpu)` の範囲
 * 実行時の max_vcpu は KVM_CHECK_EXTENSION の KVM_CAP_NR_VCPUS で取るのが推奨されてる???
 * 実行時の max_vcpu は KVM_CHECK_EXTENSION の KVM_CAP_MAX_VCPUS で取れる???
   * KVM_CAP_NR_VCPUS が無いなら 4 としておけ
   * KVM_CAP_MAX_VCPUS がないなら KVM_CAP_MAX_VCPUS にしておけ
 * max_vcpu_id は KVM_CHECK_EXTENSION の KVM_CAP_MAX_VCPU_ID でとれる
   * KVM_CAP_MAX_VCPU_ID がないなら、 KVM_CAP_MAX_VCPUS にしておけ

```
On powerpc using book3s_hv mode, the vcpus are mapped onto virtual
threads in one or more virtual CPU cores.  (This is because the
hardware requires all the hardware threads in a CPU core to be in the
same partition.)  The KVM_CAP_PPC_SMT capability indicates the number
of vcpus per virtual core (vcore).  The vcore id is obtained by
dividing the vcpu id by the number of vcpus per vcore.  The vcpus in a
given vcore will always be in the same physical core as each other
(though that might be a different physical core from time to time).
Userspace can control the threading (SMT) mode of the guest by its
allocation of vcpu ids.  For example, if userspace wants
single-threaded guest vcpus, it should make all vcpu ids be a multiple
of the number of vcpus per vcore.

For virtual cpus that have been created with S390 user controlled virtual
machines, the resulting vcpu fd can be memory mapped at page offset
KVM_S390_SIE_PAGE_OFFSET in order to obtain a memory map of the virtual
cpu's hardware control block.
```

(他のアーキテクチャはよく分からんのでスルー)

## References

 * https://dc-cloud.impress.co.jp/story/2009/01/08/632
 * https://syuu1228.github.io/howto_implement_hypervisor/part1.pdf
 * https://syuu1228.github.io/howto_implement_hypervisor/part2.pdf

あたりを眺めながら読むと何がどうなってるのか理解できるはず

## Abbreviation

 * VMM  = Virtual Machine Monitor
 * VMX  = Virtual Machine eXtensions
 * VMCS = Virtual Machine Control Structure

## Macro definition of KVM_CREATE_VCPU 

```c
/* include/uapi/linux/kvm.h */
#define KVM_CREATE_VCPU           _IO(KVMIO,   0x41)
```

```
#define KVMIO 0xAE
#define _IO(type,nr)		_IOC(_IOC_NONE,(type),(nr),0)
```

```c
#define _IOC(dir,type,nr,size) \
	(((dir)  << _IOC_DIRSHIFT) | \
	 ((type) << _IOC_TYPESHIFT) | \
	 ((nr)   << _IOC_NRSHIFT) | \
	 ((size) << _IOC_SIZESHIFT))
```

```c
#ifndef _IOC_NONE
# define _IOC_NONE	0U
#endif
```

## create_vcpu_fd

kvm-vm のデスクリプタを anon_inode で返す。ユーザランドからファイルディスクリプタを通じて操作できる

# ioctl(2) + KVM_CREATE_VCPU 

kvm_vm_ioctl は anon_inode kvm-vm ioctl(2) 

```c
static long kvm_vm_ioctl(struct file *filp,
			   unsigned int ioctl, unsigned long arg)
{
	struct kvm *kvm = filp->private_data;
	void __user *argp = (void __user *)arg;
	int r;

	if (kvm->mm != current->mm)
		return -EIO;
	switch (ioctl) {
	case KVM_CREATE_VCPU: 🍣
		r = kvm_vm_ioctl_create_vcpu(kvm, arg);
		break;

...
```

KVM_CREATE_VCPU は vCPU をセットアップして、最後にデスクリプタを返す。デスクリプタは anon_inode kvm-vm

```c
static int create_vcpu_fd(struct kvm_vcpu *vcpu)
{
	return anon_inode_getfd("kvm-vcpu", &kvm_vcpu_fops, vcpu, O_RDWR | O_CLOEXEC);
}
```

kvm_vcpu_fops の file_operations は下記の通り

```c
static struct file_operations kvm_vcpu_fops = {
	.release        = kvm_vcpu_release,
	.unlocked_ioctl = kvm_vcpu_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl   = kvm_vcpu_compat_ioctl,
#endif
	.mmap           = kvm_vcpu_mmap,
	.llseek		= noop_llseek,
};
```

ioctl(2) + anon_inode kvm-vcpu を通して vCPU が操作できるようになる。 kvm_vcpu_fops の中身は盛りだくさんなので省略する

# vCPU をセットアップするまで

## kvm_vm_ioctl_create_vcpu

```c
/*
 * Creates some virtual cpus.  Good luck creating more than one.
 */
static int kvm_vm_ioctl_create_vcpu(struct kvm *kvm, u32 id)
{
	int r;
	struct kvm_vcpu *vcpu, *v;

    /* CentOS7 では 255 だった。255 以上は増やせない? */
	if (id >= KVM_MAX_VCPUS)
		return -EINVAL;

    // kvm_arch_vcpu_create はアーキテクチャ依存
    // struct kvm_vcpu *kvm_arch_vcpu_create(struct kvm *kvm,
    // 						unsigned int id)
    // {
    // 	struct kvm_vcpu *vcpu;
    //
    // 	if (check_tsc_unstable() && atomic_read(&kvm->online_vcpus) != 0)
    // 		printk_once(KERN_WARNING
    // 		"kvm: SMP vm created on host with unstable TSC; "
    // 		"guest TSC will not be reliable\n");
    //
    // 	vcpu = kvm_x86_ops->vcpu_create(kvm, id);
    // 
    // 	return vcpu;
    // }
	vcpu = kvm_arch_vcpu_create(kvm, id); ★
	if (IS_ERR(vcpu))
		return PTR_ERR(vcpu);

	preempt_notifier_init(&vcpu->preempt_notifier, &kvm_preempt_ops);

    //int kvm_arch_vcpu_setup(struct kvm_vcpu *vcpu)
    //{
    //	int r;
    //
    //	vcpu->arch.mtrr_state.have_fixed = 1;
    //	r = vcpu_load(vcpu);
    //	if (r)
    //		return r;
    //	kvm_vcpu_reset(vcpu); ★
    //	kvm_mmu_setup(vcpu); ★
    //	vcpu_put(vcpu);
    //
    //	return r;
    //}

    // ここもアーキテクチャ依存なセットアップ
    r = kvm_arch_vcpu_setup(vcpu);
	if (r)
		goto vcpu_destroy;

    /* --> */
	mutex_lock(&kvm->lock); 
	if (!kvm_vcpu_compatible(vcpu)) {
		r = -EINVAL;
		goto unlock_vcpu_destroy;
	}

    /* オンラインの CPU 数を kvm から取れる */
	if (atomic_read(&kvm->online_vcpus) == KVM_MAX_VCPUS) {
		r = -EINVAL;
		goto unlock_vcpu_destroy;
	}

	kvm_for_each_vcpu(r, v, kvm)
        //	* int cpu;    
        // id とは?
		if (v->vcpu_id == id) {
			r = -EEXIST;
			goto unlock_vcpu_destroy;
		}

    // * struct kvm_vcpu *vcpus[KVM_MAX_VCPUS];
	// * atomic_t online_vcpus;
    // struct kvm_vcpu * の配列。NULL でなかったら BUG_ON
	BUG_ON(kvm->vcpus[atomic_read(&kvm->online_vcpus)]);

	/* Now it's all set up, let userspace reach it */
	kvm_get_kvm(kvm);
    // ここまででセットアップが終わって、ユーザランドからさわれる?らしい
    // ioctl(2) の結果としてデスクリプタを返すので、デスクリプタ経由で操作できる?

    // /*
    //  * Allocates an inode for the vcpu.
    //  */
    // static int create_vcpu_fd(struct kvm_vcpu *vcpu)
    // {
    // 	return anon_inode_getfd("kvm-vcpu", &kvm_vcpu_fops, vcpu, O_RDWR | O_CLOEXEC);
    //
    // see also http://wiki.bit-hive.com/north/pg/anon_inodefs
    }
	r = create_vcpu_fd(vcpu);
	if (r < 0) {
        // どういうケースでコケる?
		kvm_put_kvm(kvm);
		goto unlock_vcpu_destroy;
	}

	kvm->vcpus[atomic_read(&kvm->online_vcpus)] = vcpu;
    // メモリバリアが必要な理由は???
	smp_wmb();
	atomic_inc(&kvm->online_vcpus);

    /* <-- */
	mutex_unlock(&kvm->lock);
	kvm_arch_vcpu_postcreate(vcpu);

    // r is file descriptor
    // ホスト側でデスクリプタを保持して、 kvm_vcpu_fops であれこれできる
	return r;

unlock_vcpu_destroy:
	mutex_unlock(&kvm->lock);
vcpu_destroy:
	kvm_arch_vcpu_destroy(vcpu);
	return r;
}
```

## kvm_arch_vcpu_create

```c
struct kvm_vcpu *kvm_arch_vcpu_create(struct kvm *kvm,
						unsigned int id)
{
	struct kvm_vcpu *vcpu;

	if (check_tsc_unstable() && atomic_read(&kvm->online_vcpus) != 0)
		printk_once(KERN_WARNING
		"kvm: SMP vm created on host with unstable TSC; "
		"guest TSC will not be reliable\n");

	vcpu = kvm_x86_ops->vcpu_create(kvm, id);

	return vcpu;
}
```

## kvm_x86_ops: Intel CPU vmx 

```c
static struct kvm_x86_ops vmx_x86_ops = {
	.cpu_has_kvm_support = cpu_has_kvm_support,
	.disabled_by_bios = vmx_disabled_by_bios,
	.hardware_setup = hardware_setup,
	.hardware_unsetup = hardware_unsetup,
	.check_processor_compatibility = vmx_check_processor_compat,
	.hardware_enable = hardware_enable,
	.hardware_disable = hardware_disable,
	.cpu_has_accelerated_tpr = report_flexpriority,
	.cpu_has_high_real_mode_segbase = vmx_has_high_real_mode_segbase,

	.vcpu_create = vmx_create_vcpu, ★
	.vcpu_free = vmx_free_vcpu,
	.vcpu_reset = vmx_vcpu_reset,

... 非常に長いので省略
```

## kvm_x86_ops->vcpu_create: vmx_create_vcpu

```c
static struct kvm_vcpu *vmx_create_vcpu(struct kvm *kvm, unsigned int id)
{
	int err;
	struct vcpu_vmx *vmx = kmem_cache_zalloc(kvm_vcpu_cache, GFP_KERNEL);
	int cpu;

	if (!vmx)
		return ERR_PTR(-ENOMEM);

    // virtual processor id ? 用途は?
	allocate_vpid(vmx);

	err = kvm_vcpu_init(&vmx->vcpu, kvm, id); ★
	if (err)
		goto free_vcpu;

    // ゲストの MSR? Model Specific Register
    // http://mcn.oops.jp/wiki/index.php?CPU%2FMSR
	vmx->guest_msrs = kmalloc(PAGE_SIZE, GFP_KERNEL);

    // BUILD_BUG_ON ... http://kernhack.hatenablog.com/entry/2013/12/20/173228
	BUILD_BUG_ON(ARRAY_SIZE(vmx_msr_index) * sizeof(vmx->guest_msrs[0])
		     > PAGE_SIZE);

	err = -ENOMEM;
	if (!vmx->guest_msrs) {
		goto uninit_vcpu;
	}

    // Virtual Machine Control Structure
    // struct vmcs {
    // 	u32 revision_id;
    // 	u32 abort;
    // 	char data[0];
    // };
    // 現在の vCPU の VMCS を指す (nested guest だと違う)
	vmx->loaded_vmcs = &vmx->vmcs01;

    // VMCS は物理CPU と
    // static struct vmcs *alloc_vmcs(void)
    // {
    // 	return alloc_vmcs_cpu(raw_smp_processor_id());
    // }

    // static struct vmcs *alloc_vmcs_cpu(int cpu)
    // {
    // 	int node = cpu_to_node(cpu);
    // 	struct page *pages;
    // 	struct vmcs *vmcs;
    // 
    // 	pages = alloc_pages_exact_node(node, GFP_KERNEL, vmcs_config.order);
    // 	if (!pages)
    // 		return NULL;
    // 	vmcs = page_address(pages);
    // 	memset(vmcs, 0, vmcs_config.size);
    // 	vmcs->revision_id = vmcs_config.revision_id; /* vmcs revision id */
    // 	return vmcs;
    // }
	vmx->loaded_vmcs->vmcs = alloc_vmcs();
	if (!vmx->loaded_vmcs->vmcs)
		goto free_msrs;

    // module_param 
	if (!vmm_exclusive)
        //static void kvm_cpu_vmxon(u64 addr)
        //{
        //	asm volatile (ASM_VMX_VMXON_RAX
        //			: : "a"(&addr), "m"(addr)
        //			: "memory", "cc");
        //}
        //
        // #define __pa(x)		__phys_addr((unsigned long)(x))
        //
        // VMXON 命令 VMXモードにはいる
        // Virtual Machine eXtension ON ???
        //  * http://www.tptp.cc/mirrors/siyobik.info/instruction/VMXON.html
        //  * https://dc-cloud.impress.co.jp/story/2009/01/08/632
		kvm_cpu_vmxon(__pa(per_cpu(vmxarea, raw_smp_processor_id())));

    // VMCS = Virtual Machine Control Structure の初期化
    //  * https://dc-cloud.impress.co.jp/story/2009/01/08/632
    //  * vCPU ごとに VMCS が必要
	loaded_vmcs_init(vmx->loaded_vmcs);

	if (!vmm_exclusive)
		kvm_cpu_vmxoff();

	cpu = get_cpu(); /* smp_processor_id を返す */
	vmx_vcpu_load(&vmx->vcpu, cpu); ★

    // vCPU と 物理CPU の対応付けになる?
	vmx->vcpu.cpu = cpu;

    // VMCS にあれこれを書き込んでいく
	err = vmx_vcpu_setup(vmx) ★;
	vmx_vcpu_put(&vmx->vcpu);
	put_cpu();
	if (err)
		goto free_vmcs;

	if (vm_need_virtualize_apic_accesses(kvm)) {
		err = alloc_apic_access_page(kvm);
		if (err)
			goto free_vmcs;
	}

	if (enable_ept) {
		if (!kvm->arch.ept_identity_map_addr)
			kvm->arch.ept_identity_map_addr =
				VMX_EPT_IDENTITY_PAGETABLE_ADDR;
		err = init_rmode_identity_map(kvm);
		if (err)
			goto free_vmcs;
	}

	vmx->nested.current_vmptr = -1ull;
	vmx->nested.current_vmcs12 = NULL;

	/*
	 * If PML is turned on, failure on enabling PML just results in failure
	 * of creating the vcpu, therefore we can simplify PML logic (by
	 * avoiding dealing with cases, such as enabling PML partially on vcpus
	 * for the guest, etc.
	 */
	if (enable_pml) {
		err = vmx_enable_pml(vmx);
		if (err)
			goto free_vmcs;
	}

	return &vmx->vcpu;

free_vmcs:
	free_loaded_vmcs(vmx->loaded_vmcs);
free_msrs:
	kfree(vmx->guest_msrs);
uninit_vcpu:
	kvm_vcpu_uninit(&vmx->vcpu);
free_vcpu:
	free_vpid(vmx);
	kmem_cache_free(kvm_vcpu_cache, vmx);
	return ERR_PTR(err);
}
```

## vmx_vcpu_load

```c
/*
 * Switches to specified vcpu, until a matching vcpu_put(), but assumes
 * vcpu mutex is already taken.
 */
static void vmx_vcpu_load(struct kvm_vcpu *vcpu, int cpu)
{
	struct vcpu_vmx *vmx = to_vmx(vcpu);
	u64 phys_addr = __pa(per_cpu(vmxarea, cpu));

	if (!vmm_exclusive)
		kvm_cpu_vmxon(phys_addr);
	else if (vmx->loaded_vmcs->cpu != cpu)
		loaded_vmcs_clear(vmx->loaded_vmcs);

	if (per_cpu(current_vmcs, cpu) != vmx->loaded_vmcs->vmcs) {
		per_cpu(current_vmcs, cpu) = vmx->loaded_vmcs->vmcs;

        // static void vmcs_load(struct vmcs *vmcs)
        // {
        // 	u64 phys_addr = __pa(vmcs);
        // 	u8 error;
        //
        // http://www.tptp.cc/mirrors/siyobik.info/instruction/VMPTRLD.html
        //
        // 	asm volatile (__ex(ASM_VMX_VMPTRLD_RAX) "; setna %0"
        // 			: "=qm"(error) : "a"(&phys_addr), "m"(phys_addr)
        // 			: "cc", "memory");
        // 	if (error)
        // 		printk(KERN_ERR "kvm: vmptrld %p/%llx failed\n",
        // 		       vmcs, phys_addr);
        // }
        // VMCS を読み取る
		vmcs_load(vmx->loaded_vmcs->vmcs);
	}

	if (vmx->loaded_vmcs->cpu != cpu) {
		struct desc_ptr *gdt = &__get_cpu_var(host_gdt);
		unsigned long sysenter_esp;

		kvm_make_request(KVM_REQ_TLB_FLUSH, vcpu);
		local_irq_disable();
		crash_disable_local_vmclear(cpu);

		/*
		 * Read loaded_vmcs->cpu should be before fetching
		 * loaded_vmcs->loaded_vmcss_on_cpu_link.
		 * See the comments in __loaded_vmcs_clear().
		 */
		smp_rmb();

		list_add(&vmx->loaded_vmcs->loaded_vmcss_on_cpu_link,
			 &per_cpu(loaded_vmcss_on_cpu, cpu));
		crash_enable_local_vmclear(cpu);
		local_irq_enable();

		/*
		 * Linux uses per-cpu TSS and GDT, so set these when switching
		 * processors.
		 */

        // TR レジスタ を VMCS に書いておく。用途は?
		vmcs_writel(HOST_TR_BASE, kvm_read_tr_base()); /* 22.2.4 */
        // GDTR レジスタ を VMCS に書いておく。用途は?
		vmcs_writel(HOST_GDTR_BASE, gdt->address);   /* 22.2.4 */

        // SYSENTER の ESP を読んで VMCS に書いておく
		rdmsrl(MSR_IA32_SYSENTER_ESP, sysenter_esp);
		vmcs_writel(HOST_IA32_SYSENTER_ESP, sysenter_esp); /* 22.2.3 */
		vmx->loaded_vmcs->cpu = cpu;
	}
}
```

## kvm_vcpu_init

アーキテクチャ非依存のセットアップコード

```c
int kvm_vcpu_init(struct kvm_vcpu *vcpu, struct kvm *kvm, unsigned id)
{
	struct page *page;
	int r;

	mutex_init(&vcpu->mutex);
	vcpu->cpu = -1;
	vcpu->kvm = kvm;
	vcpu->vcpu_id = id;
	vcpu->pid = NULL;
	init_waitqueue_head(&vcpu->wq);
	kvm_async_pf_vcpu_init(vcpu);

	page = alloc_page(GFP_KERNEL | __GFP_ZERO);
	if (!page) {
		r = -ENOMEM;
		goto fail;
	}
	vcpu->run = page_address(page);

	kvm_vcpu_set_in_spin_loop(vcpu, false);
	kvm_vcpu_set_dy_eligible(vcpu, false);
	vcpu->preempted = false;

	r = kvm_arch_vcpu_init(vcpu);
	if (r < 0)
		goto fail_free_run;
	return 0;

fail_free_run:
	free_page((unsigned long)vcpu->run);
fail:
	return r;
}
EXPORT_SYMBOL_GPL(kvm_vcpu_init);
```

## vmx_create_vcpu-> vmx_vcpu_setup

ひたすら VMCS の初期化をしている

```c
/*
 * Sets up the vmcs for emulated real mode.
 */
static int vmx_vcpu_setup(struct vcpu_vmx *vmx)
{
#ifdef CONFIG_X86_64
	unsigned long a;
#endif
	int i;

	/* I/O */
	vmcs_write64(IO_BITMAP_A, __pa(vmx_io_bitmap_a));
	vmcs_write64(IO_BITMAP_B, __pa(vmx_io_bitmap_b));

    // デフォルトは on 
    // https://software.intel.com/en-us/blogs/2014/12/12/enabling-virtual-machine-control-structure-shadowing-on-a-nested-virtual-machine
    // nested virtualization 用?
	if (enable_shadow_vmcs) { 
		vmcs_write64(VMREAD_BITMAP, __pa(vmx_vmread_bitmap));
		vmcs_write64(VMWRITE_BITMAP, __pa(vmx_vmwrite_bitmap));
	}

	if (cpu_has_vmx_msr_bitmap())
		vmcs_write64(MSR_BITMAP, __pa(vmx_msr_bitmap_legacy));

	vmcs_write64(VMCS_LINK_POINTER, -1ull); /* 22.3.1.5 */

	/* Control */
	vmcs_write32(PIN_BASED_VM_EXEC_CONTROL, vmx_pin_based_exec_ctrl(vmx));

	vmcs_write32(CPU_BASED_VM_EXEC_CONTROL, vmx_exec_control(vmx));

	if (cpu_has_secondary_exec_ctrls()) {
		vmcs_write32(SECONDARY_VM_EXEC_CONTROL,
				vmx_secondary_exec_control(vmx));
	}

	if (vmx_vm_has_apicv(vmx->vcpu.kvm)) {
		vmcs_write64(EOI_EXIT_BITMAP0, 0);
		vmcs_write64(EOI_EXIT_BITMAP1, 0);
		vmcs_write64(EOI_EXIT_BITMAP2, 0);
		vmcs_write64(EOI_EXIT_BITMAP3, 0);

		vmcs_write16(GUEST_INTR_STATUS, 0);

		vmcs_write64(POSTED_INTR_NV, POSTED_INTR_VECTOR);
		vmcs_write64(POSTED_INTR_DESC_ADDR, __pa((&vmx->pi_desc)));
	}

	if (ple_gap) {
		vmcs_write32(PLE_GAP, ple_gap);
		vmx->ple_window = ple_window;
		vmx->ple_window_dirty = true;
	}

	vmcs_write32(PAGE_FAULT_ERROR_CODE_MASK, 0);
	vmcs_write32(PAGE_FAULT_ERROR_CODE_MATCH, 0);
	vmcs_write32(CR3_TARGET_COUNT, 0);           /* 22.2.1 */

	vmcs_write16(HOST_FS_SELECTOR, 0);            /* 22.2.4 */
	vmcs_write16(HOST_GS_SELECTOR, 0);            /* 22.2.4 */
	vmx_set_constant_host_state(vmx);
#ifdef CONFIG_X86_64
	rdmsrl(MSR_FS_BASE, a);
	vmcs_writel(HOST_FS_BASE, a); /* 22.2.4 */
	rdmsrl(MSR_GS_BASE, a);
	vmcs_writel(HOST_GS_BASE, a); /* 22.2.4 */
#else
	vmcs_writel(HOST_FS_BASE, 0); /* 22.2.4 */
	vmcs_writel(HOST_GS_BASE, 0); /* 22.2.4 */
#endif

	vmcs_write32(VM_EXIT_MSR_STORE_COUNT, 0);
	vmcs_write32(VM_EXIT_MSR_LOAD_COUNT, 0);
	vmcs_write64(VM_EXIT_MSR_LOAD_ADDR, __pa(vmx->msr_autoload.host));
	vmcs_write32(VM_ENTRY_MSR_LOAD_COUNT, 0);
	vmcs_write64(VM_ENTRY_MSR_LOAD_ADDR, __pa(vmx->msr_autoload.guest));

	if (vmcs_config.vmentry_ctrl & VM_ENTRY_LOAD_IA32_PAT) {
		u32 msr_low, msr_high;
		u64 host_pat;
		rdmsr(MSR_IA32_CR_PAT, msr_low, msr_high);
		host_pat = msr_low | ((u64) msr_high << 32);
		/* Write the default value follow host pat */
		vmcs_write64(GUEST_IA32_PAT, host_pat);
		/* Keep arch.pat sync with GUEST_IA32_PAT */
		vmx->vcpu.arch.pat = host_pat;
	}

	for (i = 0; i < ARRAY_SIZE(vmx_msr_index); ++i) {
		u32 index = vmx_msr_index[i];
		u32 data_low, data_high;
		int j = vmx->nmsrs;

		if (rdmsr_safe(index, &data_low, &data_high) < 0)
			continue;
		if (wrmsr_safe(index, data_low, data_high) < 0)
			continue;
		vmx->guest_msrs[j].index = i;
		vmx->guest_msrs[j].data = 0;
		vmx->guest_msrs[j].mask = -1ull;
		++vmx->nmsrs;
	}


	vm_exit_controls_init(vmx, vmcs_config.vmexit_ctrl);

	/* 22.2.1, 20.8.1 */
	vm_entry_controls_init(vmx, vmcs_config.vmentry_ctrl);

	vmcs_writel(CR0_GUEST_HOST_MASK, ~0UL);
	set_cr4_guest_host_mask(vmx);

	return 0;
}
```

----

## VMXON

> VMXモードに入る

```c
static void kvm_cpu_vmxon(u64 addr)
{
	asm volatile (ASM_VMX_VMXON_RAX
			: : "a"(&addr), "m"(addr)
			: "memory", "cc");
}
```

## VMXOFF

> VMXモードから抜ける

```c
/* Just like cpu_vmxoff(), but with the __kvm_handle_fault_on_reboot()
 * tricks.
 */
static void kvm_cpu_vmxoff(void)
{
	asm volatile (__ex(ASM_VMX_VMXOFF) : : : "cc");
}
```

## VMCLEAR

> VMCSを初期化（VM非アクティブ）

```c
static void vmcs_clear(struct vmcs *vmcs)
{
	u64 phys_addr = __pa(vmcs);
	u8 error;

	asm volatile (__ex(ASM_VMX_VMCLEAR_RAX) "; setna %0"
		      : "=qm"(error) : "a"(&phys_addr), "m"(phys_addr)
		      : "cc", "memory");
	if (error)
		printk(KERN_ERR "kvm: vmclear fail: %p/%llx\n",
		       vmcs, phys_addr);
}

static inline void loaded_vmcs_init(struct loaded_vmcs *loaded_vmcs)
{
	vmcs_clear(loaded_vmcs->vmcs);
	loaded_vmcs->cpu = -1;
	loaded_vmcs->launched = 0;
}
```