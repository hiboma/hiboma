# KVM_CREATE_VM

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

```
4.2 KVM_CREATE_VM

Capability: basic
Architectures: all
Type: system ioctl
Parameters: machine type identifier (KVM_VM_*)
Returns: a VM fd that can be used to control the new virtual machine.

The new VM has no virtual cpus and no memory.  An mmap() of a VM fd
will access the virtual machine's physical address space; offset zero
corresponds to guest physical address zero.  Use of mmap() on a VM fd
is discouraged if userspace memory allocation (KVM_CAP_USER_MEMORY) is
available.
You most certainly want to use 0 as machine type.

In order to create user controlled virtual machines on S390, check
KVM_CAP_S390_UCONTROL and use the flag KVM_VM_S390_UCONTROL as
privileged user (CAP_SYS_ADMIN).
```

 * KVM_CREATE_VM で作った 「VM」は CPUもメモリも持たない
 * VM fd に mmap(2) すると 「VM の物理アドレス」にアクセスする
   * オフセット 0 はゲストの物理アドレスの 0 に相当する
   * KVM_CAP_USER_MEMORY するなら VM fd に mmap は推奨されない
 * たいがい使いたいのは machine type 0 だろ

## マクロの定義

```
#define KVM_CREATE_VM             _IO(KVMIO,   0x01) /* returns a VM fd */
```

## ioctl(2) + KVM_CREATE_VM

`/dev/kvm` の fd に ioctl(2) + KVM_CREATE_VM して VM を割り当てる

```c
static long kvm_dev_ioctl(struct file *filp,
			  unsigned int ioctl, unsigned long arg)
{
	long r = -EINVAL;

	switch (ioctl) {
	case KVM_GET_API_VERSION:
		if (arg)
			goto out;
		r = KVM_API_VERSION;
		break;
	case KVM_CREATE_VM: 
		r = kvm_dev_ioctl_create_vm(arg); ★ /* r はファイルデスクリプタ */
		break;
	case KVM_CHECK_EXTENSION:
		r = kvm_vm_ioctl_check_extension_generic(NULL, arg);
		break;
	case KVM_GET_VCPU_MMAP_SIZE:
		if (arg)
			goto out;
		r = PAGE_SIZE;     /* struct kvm_run */
#ifdef CONFIG_X86
		r += PAGE_SIZE;    /* pio data page */
#endif
#ifdef KVM_COALESCED_MMIO_PAGE_OFFSET
		r += PAGE_SIZE;    /* coalesced mmio ring page */
#endif
		break;
	case KVM_TRACE_ENABLE:
	case KVM_TRACE_PAUSE:
	case KVM_TRACE_DISABLE:
		r = -EOPNOTSUPP;
		break;
	default:
		return kvm_arch_dev_ioctl(filp, ioctl, arg);
	}
out:
	return r;
}
```

# /dev/kvm の実装

少し寄り道をして、 /dev/kvm の実装をみてみる。 /dev/kvm は character device 

```c
static struct miscdevice kvm_dev = {
	KVM_MINOR,
	"kvm",
	&kvm_chardev_ops,
};
``

マイナー番号は `#define KVM_MINOR		232` として定義されている

```
$ ls -hal /dev/kvm
crw-rw-rw- 1 root kvm 10, 232  2月 21 12:59 2016 /dev/kvm
```

file_operations の定義は下記の通りにセットされている

```c
static struct file_operations kvm_chardev_ops = {
	.unlocked_ioctl = kvm_dev_ioctl,
	.compat_ioctl   = kvm_dev_ioctl,
	.llseek		= noop_llseek, 
};
```

ioctl(2) で kvm_dev_ioctl を呼び出すようになっているのが分かる

## kvm_dev_ioctl_create_vm

nKVM_CREATE_VM の続きをみていく

 * struct kvm * のアロケートと初期化をする
 * anon_inode kvm-vm のファイルディスクリプタを返し、struct kvm とを結びつけておく

```c
static int kvm_dev_ioctl_create_vm(unsigned long type)
{
	int r;
	struct kvm *kvm;

	kvm = kvm_create_vm(type);
	if (IS_ERR(kvm))
		return PTR_ERR(kvm);
#ifdef KVM_COALESCED_MMIO_PAGE_OFFSET
	r = kvm_coalesced_mmio_init(kvm);
	if (r < 0) {
		kvm_put_kvm(kvm);
		return r;
	}
#endif
	r = anon_inode_getfd("kvm-vm", &kvm_vm_fops, kvm, O_RDWR | O_CLOEXEC);
	if (r < 0)
		kvm_put_kvm(kvm);

	return r;
}
```

kvm_vm_fops は下記の通りで、 anon_inode kvm-vm + ioctl(2) で vCPU の作成などができる

```c
static struct file_operations kvm_vm_fops = {
	.release        = kvm_vm_release,
	.unlocked_ioctl = kvm_vm_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl   = kvm_vm_compat_ioctl,
#endif
	.llseek		= noop_llseek,
};
```

vCPUの作成などは長くなるので別途で調べる

## kvm_dev_ioctl_create_vm ->  kvm_create_vm

struct kvm * を初期化して返す

```c
static struct kvm *kvm_create_vm(unsigned long type)
{
	int r, i;

    //static inline struct kvm *kvm_arch_alloc_vm(void)
    //{
    //	return kzalloc(sizeof(struct kvm), GFP_KERNEL);
    //}
	struct kvm *kvm = kvm_arch_alloc_vm(); 

	if (!kvm)
		return ERR_PTR(-ENOMEM);

	r = kvm_arch_init_vm(kvm, type); ★1
	if (r)
		goto out_err_no_disable;

	r = hardware_enable_all(); ★2
	if (r)
		goto out_err_no_disable;

#ifdef CONFIG_HAVE_KVM_IRQFD
	INIT_HLIST_HEAD(&kvm->irq_ack_notifier_list);
#endif

	BUILD_BUG_ON(KVM_MEM_SLOTS_NUM > SHRT_MAX);

	r = -ENOMEM;
	for (i = 0; i < KVM_ADDRESS_SPACE_NUM; i++) {
        // memslot とはなんだ???
		kvm->memslots[i] = kvm_alloc_memslots();
		if (!kvm->memslots[i])
			goto out_err_no_srcu;
	}

    // Sleepable RCU
    // * https://lwn.net/Articles/202847/
	if (init_srcu_struct(&kvm->srcu))
		goto out_err_no_srcu;
	if (init_srcu_struct(&kvm->irq_srcu))
		goto out_err_no_irq_srcu;
	for (i = 0; i < KVM_NR_BUSES; i++) {
		kvm->buses[i] = kzalloc(sizeof(struct kvm_io_bus),
					GFP_KERNEL);
		if (!kvm->buses[i])
			goto out_err;
	}

	spin_lock_init(&kvm->mmu_lock);

    // 現在のタスクが kvm そのものになるのだろうか?
	kvm->mm = current->mm;
	atomic_inc(&kvm->mm->mm_count);
	kvm_eventfd_init(kvm);
	mutex_init(&kvm->lock);
	mutex_init(&kvm->irq_lock);
	mutex_init(&kvm->slots_lock);
	atomic_set(&kvm->users_count, 1);
	INIT_LIST_HEAD(&kvm->devices);

    // https://lwn.net/Articles/266320/
    // http://www.atmarkit.co.jp/flinux/rensai/watch2008/watchmemb.html
	r = kvm_init_mmu_notifier(kvm);
	if (r)
		goto out_err;

	spin_lock(&kvm_lock);

    // 全部の VM リスト
	list_add(&kvm->vm_list, &vm_list);
	spin_unlock(&kvm_lock);

	return kvm;

out_err:
	cleanup_srcu_struct(&kvm->irq_srcu);
out_err_no_irq_srcu:
	cleanup_srcu_struct(&kvm->srcu);
out_err_no_srcu:
	hardware_disable_all();
out_err_no_disable:
	for (i = 0; i < KVM_NR_BUSES; i++)
		kfree(kvm->buses[i]);
	for (i = 0; i < KVM_ADDRESS_SPACE_NUM; i++)
		kvm_free_memslots(kvm, kvm->memslots[i]);
	kvm_arch_free_vm(kvm);
	return ERR_PTR(r);
}
```

## ★1 kvm_arch_init_vm: arch/x86/kvm/x86.c 

```c
int kvm_arch_init_vm(struct kvm *kvm, unsigned long type)
{
	if (type)
		return -EINVAL;

	INIT_HLIST_HEAD(&kvm->arch.mask_notifier_list);
	INIT_LIST_HEAD(&kvm->arch.active_mmu_pages);
	INIT_LIST_HEAD(&kvm->arch.zapped_obsolete_pages);
	INIT_LIST_HEAD(&kvm->arch.assigned_dev_head);
	atomic_set(&kvm->arch.noncoherent_dma_count, 0);

	/* Reserve bit 0 of irq_sources_bitmap for userspace irq source */
	set_bit(KVM_USERSPACE_IRQ_SOURCE_ID, &kvm->arch.irq_sources_bitmap);
	/* Reserve bit 1 of irq_sources_bitmap for irqfd-resampler */
	set_bit(KVM_IRQFD_RESAMPLE_IRQ_SOURCE_ID,
		&kvm->arch.irq_sources_bitmap);

	raw_spin_lock_init(&kvm->arch.tsc_write_lock);
	mutex_init(&kvm->arch.apic_map_lock);
	spin_lock_init(&kvm->arch.pvclock_gtod_sync_lock);

	pvclock_update_vm_gtod_copy(kvm);

	INIT_DELAYED_WORK(&kvm->arch.kvmclock_update_work, kvmclock_update_fn);
	INIT_DELAYED_WORK(&kvm->arch.kvmclock_sync_work, kvmclock_sync_fn);

	return 0;
}
```

## ★2 hardware_enable_all

```c
static int hardware_enable_all(void)
{
	int r = 0;
	int count;

	raw_spin_lock(&kvm_count_lock);

	count = ++kvm_usage_count;
	if (kvm_usage_count == 1) {
		atomic_set(&hardware_enable_failed, 0);
        
        // CPU ごとに hardware_enable_nolock していく
		on_each_cpu(hardware_enable_nolock, NULL, 1); ★3

		if (atomic_read(&hardware_enable_failed)) {
			hardware_disable_all_nolock();
			r = -EBUSY;
		}
	}

	raw_spin_unlock(&kvm_count_lock);

	if (r == 0) {
		char count_string[20];
		char event_string[] = "EVENT=create";
		char *envp[] = { event_string, count_string, NULL };

		sprintf(count_string, "COUNT=%d", count);
		kobject_uevent_env(&kvm_dev.this_device->kobj, KOBJ_CHANGE, envp);
	}
	return r;
}
```

## ★3 hardware_enable_nolock

```c
static void hardware_enable_nolock(void *junk)
{
	int cpu = raw_smp_processor_id();
	int r;

	if (cpumask_test_cpu(cpu, cpus_hardware_enabled))
		return;

	cpumask_set_cpu(cpu, cpus_hardware_enabled);

	r = kvm_arch_hardware_enable(); ★4

	if (r) {
		cpumask_clear_cpu(cpu, cpus_hardware_enabled);
		atomic_inc(&hardware_enable_failed);
		pr_info("kvm: enabling virtualization on CPU%d failed\n", cpu);
	}
}
```

##### ★4 hardware_enable_nolock -> kvm_arch_hardware_enable arch/x86/kvm/x86.c

```c
int kvm_arch_hardware_enable(void)
{
	struct kvm *kvm;
	struct kvm_vcpu *vcpu;
	int i;
	int ret;
	u64 local_tsc;
	u64 max_tsc = 0;
	bool stable, backwards_tsc = false;

	kvm_shared_msr_cpu_online();

    // CR4 レジスタ、VMXE ビット
	ret = kvm_x86_ops->hardware_enable(); ★5
	if (ret != 0)
		return ret;

    //static __always_inline unsigned long long __native_read_tsc(void)
    //{
    //	DECLARE_ARGS(val, low, high);
    //
    //	asm volatile("rdtsc" : EAX_EDX_RET(val, low, high));
    //
    // http://softwaretechnique.jp/OS_Development/Tips/IA32_Instructions/RDTSC.html
    //	return EAX_EDX_VAL(val, low, high);
    //}
    // ホストCPU のタイムスタンプカウンタを取る?
	local_tsc = native_read_tsc();
	stable = !check_tsc_unstable();

    // 各VCPU で TSC の初期化?
	list_for_each_entry(kvm, &vm_list, vm_list) {
		kvm_for_each_vcpu(i, vcpu, kvm) {
			if (!stable && vcpu->cpu == smp_processor_id())

                // static inline void kvm_make_request(int req, struct kvm_vcpu *vcpu)
                // {
                // 	set_bit(req, &vcpu->requests);
                // }
				kvm_make_request(KVM_REQ_CLOCK_UPDATE, vcpu);
			if (stable && vcpu->arch.last_host_tsc > local_tsc) {
                // ホストのタイムスタンプカウンタのほうが、VM よりも先?未来? になっている
				backwards_tsc = true;
				if (vcpu->arch.last_host_tsc > max_tsc)
					max_tsc = vcpu->arch.last_host_tsc;
			}
		}
	}

	/*
	 * Sometimes, even reliable TSCs go backwards.  This happens on
	 * platforms that reset TSC during suspend or hibernate actions, but
	 * maintain synchronization.  We must compensate.  Fortunately, we can
	 * detect that condition here, which happens early in CPU bringup,
	 * before any KVM threads can be running.  Unfortunately, we can't
	 * bring the TSCs fully up to date with real time, as we aren't yet far
	 * enough into CPU bringup that we know how much real time has actually
	 * elapsed; our helper function, get_kernel_ns() will be using boot
	 * variables that haven't been updated yet.
	 *
	 * So we simply find the maximum observed TSC above, then record the
	 * adjustment to TSC in each VCPU.  When the VCPU later gets loaded,
	 * the adjustment will be applied.  Note that we accumulate
	 * adjustments, in case multiple suspend cycles happen before some VCPU
	 * gets a chance to run again.  In the event that no KVM threads get a
	 * chance to run, we will miss the entire elapsed period, as we'll have
	 * reset last_host_tsc, so VCPUs will not have the TSC adjusted and may
	 * loose cycle time.  This isn't too big a deal, since the loss will be
	 * uniform across all VCPUs (not to mention the scenario is extremely
	 * unlikely). It is possible that a second hibernate recovery happens
	 * much faster than a first, causing the observed TSC here to be
	 * smaller; this would require additional padding adjustment, which is
	 * why we set last_host_tsc to the local tsc observed here.
	 *
	 * N.B. - this code below runs only on platforms with reliable TSC,
	 * as that is the only way backwards_tsc is set above.  Also note
	 * that this runs for ALL vcpus, which is not a bug; all VCPUs should
	 * have the same delta_cyc adjustment applied if backwards_tsc
	 * is detected.  Note further, this adjustment is only done once,
	 * as we reset last_host_tsc on all VCPUs to stop this from being
	 * called multiple times (one for each physical CPU bringup).
	 *
	 * Platforms with unreliable TSCs don't have to deal with this, they
	 * will be compensated by the logic in vcpu_load, which sets the TSC to
	 * catchup mode.  This will catchup all VCPUs to real time, but cannot
	 * guarantee that they stay in perfect synchronization.
	 */
	if (backwards_tsc) {
		u64 delta_cyc = max_tsc - local_tsc;
		backwards_tsc_observed = true;
		list_for_each_entry(kvm, &vm_list, vm_list) {
			kvm_for_each_vcpu(i, vcpu, kvm) {
				vcpu->arch.tsc_offset_adjustment += delta_cyc;
				vcpu->arch.last_host_tsc = local_tsc;
				kvm_make_request(KVM_REQ_MASTERCLOCK_UPDATE, vcpu);
			}

			/*
			 * We have to disable TSC offset matching.. if you were
			 * booting a VM while issuing an S4 host suspend....
			 * you may have some problem.  Solving this issue is
			 * left as an exercise to the reader.
			 */
			kvm->arch.last_tsc_nsec = 0;
			kvm->arch.last_tsc_write = 0;
		}

	}
	return 0;
}
```

## ★5 hardware_enable: arch/x86/kvm/vmx.c

CR4 レジスタで VMXE ビットをたてるあたりが肝なんだろうか

```c
static int hardware_enable(void)
{
	int cpu = raw_smp_processor_id();
	u64 phys_addr = __pa(per_cpu(vmxarea, cpu));
	u64 old, test_bits;

    // https://en.wikipedia.org/wiki/Control_register
    // CR4 レジスタの 13bit をみて VMXE = Virtual Machine Extensions Enable かどうか
    // #define X86_CR4_VMXE_BIT	13 /* enable VMX virtualization */
    // #define X86_CR4_VMXE		_BITUL(X86_CR4_VMXE_BIT)
	if (read_cr4() & X86_CR4_VMXE)
		return -EBUSY;

	INIT_LIST_HEAD(&per_cpu(loaded_vmcss_on_cpu, cpu));

	/*
	 * Now we can enable the vmclear operation in kdump
	 * since the loaded_vmcss_on_cpu list on this cpu
	 * has been initialized.
	 *
	 * Though the cpu is not in VMX operation now, there
	 * is no problem to enable the vmclear operation
	 * for the loaded_vmcss_on_cpu list is empty!
	 */
	crash_enable_local_vmclear(cpu);

	rdmsrl(MSR_IA32_FEATURE_CONTROL, old);

	test_bits = FEATURE_CONTROL_LOCKED;

    // http://www.itmedia.co.jp/enterprise/articles/0803/14/news063_2.html
    // SMX = Safer Mode Extention が有効かどうか???
	test_bits |= FEATURE_CONTROL_VMXON_ENABLED_OUTSIDE_SMX;
	if (tboot_enabled())
		test_bits |= FEATURE_CONTROL_VMXON_ENABLED_INSIDE_SMX;

	if ((old & test_bits) != test_bits) {
		/* enable and lock */
		wrmsrl(MSR_IA32_FEATURE_CONTROL, old | test_bits);
	}

    // VMXE ビットを on 
	write_cr4(read_cr4() | X86_CR4_VMXE); /* FIXME: not cpu hotplug safe */

    // ???
	if (vmm_exclusive) {
		kvm_cpu_vmxon(phys_addr);
		ept_sync_global();
	}

    // http://softwaretechnique.jp/OS_Development/Tips/IA32_Instructions/SGDT.html
    // SGDT 命令
	native_store_gdt(&__get_cpu_var(host_gdt));

	return 0;
}
```

