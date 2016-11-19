# KVM_CREATE_IRQCHIP

https://www.kernel.org/doc/Documentation/virtual/kvm/api.txt

```
4.24 KVM_CREATE_IRQCHIP

Capability: KVM_CAP_IRQCHIP, KVM_CAP_S390_IRQCHIP (s390)
Architectures: x86, ARM, arm64, s390
Type: vm ioctl
Parameters: none
Returns: 0 on success, -1 on error

Creates an interrupt controller model in the kernel.
On x86, creates a virtual ioapic, a virtual PIC (two PICs, nested), and sets up
future vcpus to have a local APIC.  IRQ routing for GSIs 0-15 is set to both
PIC and IOAPIC; GSI 16-23 only go to the IOAPIC.
On ARM/arm64, a GICv2 is created. Any other GIC versions require the usage of
KVM_CREATE_DEVICE, which also supports creating a GICv2.  Using
KVM_CREATE_DEVICE is preferred over KVM_CREATE_IRQCHIP for GICv2.
On s390, a dummy irq routing table is created.

Note that on s390 the KVM_CAP_S390_IRQCHIP vm capability needs to be enabled
before KVM_CREATE_IRQCHIP can be used.
```

割り込みコントロラーをホストカーネルで仮想化 ( in-kernel IRQ ) LAPIC/IOAPIC/PIT

 * Virtual IOAPIC
 * Virtual PIC
 * IRQ routing

qemu のマクロに付いたコメントで補足する

```c
/**
 * kvm_irqchip_in_kernel:
 *
 * Returns: true if the user asked us to create an in-kernel
 * irqchip via the "kernel_irqchip=on" machine option.
 * What this actually means is architecture and machine model
 * specific: on PC, for instance, it means that the LAPIC,
 * IOAPIC and PIT are all in kernel. This function should never
 * be used from generic target-independent code: use one of the
 * following functions or some other specific check instead.
 */
#define kvm_irqchip_in_kernel() (kvm_kernel_irqchip)
```

in-kernel IRQ によって非同期で(= 任意のスレッドが任意のタイミングで ioctl(2) を読んで) 割り込みの配信ができる。同期的だと vCPU が止まった時ににしかできない

```c
 * kvm_async_interrupts_enabled:
 *
 * Returns: true if we can deliver interrupts to KVM
 * asynchronously (ie by ioctl from any thread at any time)
 * rather than having to do interrupt delivery synchronously
 * (where the vcpu must be stopped at a suitable point first).
 */
#define kvm_async_interrupts_enabled() (kvm_async_interrupts_allowed)
```

```c
/**
 * kvm_halt_in_kernel
 *
 * Returns: true if halted cpus should still get a KVM_RUN ioctl to run
 * inside of kernel space. This only works if MP state is implemented.
 */
#define kvm_halt_in_kernel() (kvm_halt_in_kernel_allowed)
```

KVM_IRQ_LINE もみえいく?

## kvm_arch_vm_ioctl

```c
long kvm_arch_vm_ioctl(struct file *filp,
		       unsigned int ioctl, unsigned long arg)
{
	struct kvm *kvm = filp->private_data;
	void __user *argp = (void __user *)arg;
	int r = -ENOTTY;
	/*
	 * This union makes it completely explicit to gcc-3.x
	 * that these two variables' stack usage should be
	 * combined, not added together.
	 */
	union {
		struct kvm_pit_state ps;
		struct kvm_pit_state2 ps2;
		struct kvm_pit_config pit_config;
	} u;

	switch (ioctl) {

...

	case KVM_CREATE_IRQCHIP: {
		struct kvm_pic *vpic;

		mutex_lock(&kvm->lock);
		r = -EEXIST;
		if (kvm->arch.vpic)
			goto create_irqchip_unlock;
		r = -EINVAL;
		if (atomic_read(&kvm->online_vcpus))
			goto create_irqchip_unlock;
		r = -ENOMEM;
		vpic = kvm_create_pic(kvm); ★
		if (vpic) {
			r = kvm_ioapic_init(kvm); ★
			if (r) {
                // 失敗
				mutex_lock(&kvm->slots_lock);
				kvm_io_bus_unregister_dev(kvm, KVM_PIO_BUS,
							  &vpic->dev_master);
				kvm_io_bus_unregister_dev(kvm, KVM_PIO_BUS,
							  &vpic->dev_slave);
				kvm_io_bus_unregister_dev(kvm, KVM_PIO_BUS,
							  &vpic->dev_eclr);
				mutex_unlock(&kvm->slots_lock);
				kfree(vpic);
				goto create_irqchip_unlock;
			}
		} else
			goto create_irqchip_unlock;

        // vpic :kvm = 1 :1 
		smp_wmb();
		kvm->arch.vpic = vpic;
		smp_wmb();

        // IRQ Routing 手強いので別件で
		r = kvm_setup_default_irq_routing(kvm);
		if (r) {
            // 失敗
			mutex_lock(&kvm->slots_lock);
			mutex_lock(&kvm->irq_lock);
			kvm_ioapic_destroy(kvm);
			kvm_destroy_pic(kvm);
			mutex_unlock(&kvm->irq_lock);
			mutex_unlock(&kvm->slots_lock);
		}
	create_irqchip_unlock:
		mutex_unlock(&kvm->lock);
		break;
	}
```

# kvm_create_pic

```
struct kvm_pic *kvm_create_pic(struct kvm *kvm)
{
	struct kvm_pic *s;
	int ret;

	s = kzalloc(sizeof(struct kvm_pic), GFP_KERNEL);
	if (!s)
		return NULL;
	spin_lock_init(&s->lock);
	s->kvm = kvm;
	s->pics[0].elcr_mask = 0xf8;
	s->pics[1].elcr_mask = 0xde;
	s->pics[0].pics_state = s;
	s->pics[1].pics_state = s;

	/*
	 * Initialize PIO device
	 */
	kvm_iodevice_init(&s->dev_master, &picdev_master_ops);
	kvm_iodevice_init(&s->dev_slave, &picdev_slave_ops);
	kvm_iodevice_init(&s->dev_eclr, &picdev_eclr_ops);
	mutex_lock(&kvm->slots_lock);
	ret = kvm_io_bus_register_dev(kvm, KVM_PIO_BUS, 0x20, 2,
				      &s->dev_master);
	if (ret < 0)
		goto fail_unlock;

	ret = kvm_io_bus_register_dev(kvm, KVM_PIO_BUS, 0xa0, 2, &s->dev_slave);
	if (ret < 0)
		goto fail_unreg_2;

	ret = kvm_io_bus_register_dev(kvm, KVM_PIO_BUS, 0x4d0, 2, &s->dev_eclr);
	if (ret < 0)
		goto fail_unreg_1;

	mutex_unlock(&kvm->slots_lock);

	return s;

fail_unreg_1:
	kvm_io_bus_unregister_dev(kvm, KVM_PIO_BUS, &s->dev_slave);

fail_unreg_2:
	kvm_io_bus_unregister_dev(kvm, KVM_PIO_BUS, &s->dev_master);

fail_unlock:
	mutex_unlock(&kvm->slots_lock);

	kfree(s);

	return NULL;
}
```

# IOAPIC: kvm_ioapic_init

```c
int kvm_ioapic_init(struct kvm *kvm)
{
	struct kvm_ioapic *ioapic;
	int ret;

	ioapic = kzalloc(sizeof(struct kvm_ioapic), GFP_KERNEL);
	if (!ioapic)
		return -ENOMEM;
	spin_lock_init(&ioapic->lock);

    // * workqueue API
    // * top half -> bottom half
    // https://www.ibm.com/developerworks/jp/linux/library/l-tasklets/

    // 割り込み処理完了後の EOI (End of Interrupt) を IOAPIC に通知するのを workqueue に任せる?
    // https://ja.wikipedia.org/wiki/APIC
    // workqueue の呼び出し側がどこかを追うこと
    // -> handle_apic_eoi_induced
    // -> kvm_apic_set_eoi_accelerated
    // -> kvm_ioapic_send_eoi
    // -> kvm_ioapic_update_eoi
	INIT_DELAYED_WORK(&ioapic->eoi_inject, kvm_ioapic_eoi_inject_work); ★

    // Virtual IOAPIC
	kvm->arch.vioapic = ioapic;
	kvm_ioapic_reset(ioapic);
	kvm_iodevice_init(&ioapic->dev, &ioapic_mmio_ops);
	ioapic->kvm = kvm;

	mutex_lock(&kvm->slots_lock);
	ret = kvm_io_bus_register_dev(kvm, KVM_MMIO_BUS, ioapic->base_address,
				      IOAPIC_MEM_LENGTH, &ioapic->dev);
	mutex_unlock(&kvm->slots_lock);
	if (ret < 0) {
		kvm->arch.vioapic = NULL;
		kfree(ioapic);
	}

	return ret;
}
```

## kvm_ioapic_eoi_inject_work

```c
static void kvm_ioapic_eoi_inject_work(struct work_struct *work)
{
	int i;
	struct kvm_ioapic *ioapic = container_of(work, struct kvm_ioapic,
						 eoi_inject.work);
	spin_lock(&ioapic->lock);
	for (i = 0; i < IOAPIC_NUM_PINS; i++) {
		union kvm_ioapic_redirect_entry *ent = &ioapic->redirtbl[i];

		if (ent->fields.trig_mode != IOAPIC_LEVEL_TRIG)
			continue;

		if (ioapic->irr & (1 << i) && !ent->fields.remote_irr)
			ioapic_service(ioapic, i, false); ★
	}
	spin_unlock(&ioapic->lock);
}
```

 * APIC や IO BUS の仕様が分からん
 * ioapic_service 以下は手強いので別件で読むがよいか

```c
struct kvm_ioapic {
	u64 base_address;
	u32 ioregsel;
	u32 id;
	u32 irr;
	u32 pad;
	union kvm_ioapic_redirect_entry redirtbl[IOAPIC_NUM_PINS];
	unsigned long irq_states[IOAPIC_NUM_PINS];
	struct kvm_io_device dev;
	struct kvm *kvm;
	void (*ack_notifier)(void *opaque, int irq);
	spinlock_t lock;
	DECLARE_BITMAP(handled_vectors, 256);
	struct rtc_status rtc_status;
	struct delayed_work eoi_inject;
	u32 irq_eoi[IOAPIC_NUM_PINS];
	u32 irr_delivered;
};
```

## qemu/kvm-all.c

kvm_init ->

```c
static void kvm_irqchip_create(MachineState *machine, KVMState *s)
{
    int ret;

    if (kvm_check_extension(s, KVM_CAP_IRQCHIP)) {
        ;
    } else if (kvm_check_extension(s, KVM_CAP_S390_IRQCHIP)) {
        ret = kvm_vm_enable_cap(s, KVM_CAP_S390_IRQCHIP, 0);
        if (ret < 0) {
            fprintf(stderr, "Enable kernel irqchip failed: %s\n", strerror(-ret));
            exit(1);
        }
    } else {
        return;
    }

    /* First probe and see if there's a arch-specific hook to create the
     * in-kernel irqchip for us */
    ret = kvm_arch_irqchip_create(machine, s);
    if (ret == 0) {
        if (machine_kernel_irqchip_split(machine)) {
            perror("Split IRQ chip mode not supported.");
            exit(1);
        } else {
            ret = kvm_vm_ioctl(s, KVM_CREATE_IRQCHIP);
        }
    }
    if (ret < 0) {
        fprintf(stderr, "Create kernel irqchip failed: %s\n", strerror(-ret));
        exit(1);
    }

    kvm_kernel_irqchip = true;
    /* If we have an in-kernel IRQ chip then we must have asynchronous
     * interrupt delivery (though the reverse is not necessarily true)
     */
    kvm_async_interrupts_allowed = true; // 非同期
    kvm_halt_in_kernel_allowed = true;   // HALT ? を in-kernel で扱える?

    kvm_init_irq_routing(s); // -> KVM_CAP_IRQ_ROUTING

    s->gsimap = g_hash_table_new(g_direct_hash, g_direct_equal);
}
```

