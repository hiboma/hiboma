## tsc

```
Apr  9 02:19:51 vagrant-centos65 kernel: Measured 116527 cycles TSC warp between CPUs, turning off TSC clock.
Apr  9 02:19:51 vagrant-centos65 kernel: Marking TSC unstable due to check_tsc_sync_source failed
```

## setup_boot_APIC_clock 

```c
/*
 * The platform setup functions are preset with the default functions
 * for standard PC hardware.
 */
struct x86_init_ops x86_init __initdata = {

	.resources = {
		.probe_roms		= probe_roms,
		.reserve_resources	= reserve_standard_io_resources,
		.memory_setup		= default_machine_specific_memory_setup,
	},

	.mpparse = {
		.mpc_record		= x86_init_uint_noop,
		.setup_ioapic_ids	= x86_init_noop,
		.mpc_apic_id		= default_mpc_apic_id,
		.smp_read_mpc_oem	= default_smp_read_mpc_oem,
		.mpc_oem_bus_info	= default_mpc_oem_bus_info,
		.find_smp_config	= default_find_smp_config,
		.get_smp_config		= default_get_smp_config,
	},

	.irqs = {
		.pre_vector_init	= init_ISA_irqs,
		.intr_init		= native_init_IRQ,
		.trap_init		= x86_init_noop,
	},

	.oem = {
		.arch_setup		= x86_init_noop,
		.banner			= default_banner,
	},

	.paging = {
		.pagetable_setup_start	= native_pagetable_setup_start,
		.pagetable_setup_done	= native_pagetable_setup_done,
	},

	.timers = {
		.setup_percpu_clockev	= setup_boot_APIC_clock,
		.tsc_pre_init		= x86_init_noop,
		.timer_init		= hpet_time_init,
	},
};
```

## divider=10 nolapic_timer
 
 * ダミーデバイスとは?
 * local APIC タイマを無効にした際の副作用は?
   * local_apic_timer_interrupt の割り込みが発生しない?
   * CPU0 に IO-APIC-edge のタイマ割り込みが集中している。数値も随分と多いな
```
# with nolapic_timer
[vagrant@vagrant-centos65 ~]$ cat /proc/interrupts 
           CPU0       CPU1       CPU2       CPU3       
  0:     548516          0          0          0   IO-APIC-edge      timer
LOC:          0     547779     547245     546119   Local timer interrupts

# with lapic_timer
           CPU0       CPU1       CPU2       CPU3       
  0:        146          0          0          0   IO-APIC-edge      timer
LOC:       4178       3514       2970       2551   Local timer interrupts
```

nolapic_timer をブートオプション指定すると disable_apic_timer = 1 になる

```
Apr  9 02:19:51 vagrant-centos65 kernel: Disabling APIC timer
```

nolapic_timer がセットされる箇所

```c
static int __init parse_disable_apic_timer(char *arg)
{
	disable_apic_timer = 1;
	return 0;
}
early_param("noapictimer", parse_disable_apic_timer);

static int __init parse_nolapic_timer(char *arg)
{
	disable_apic_timer = 1;
	return 0;
}
early_param("nolapic_timer", parse_nolapic_timer);
```

disable_apic_timer は setup_boot_APIC_clock の挙動を変える

 * local APIC タイマを使わない
   * calibrate_APIC_clock, setup_APIC_timer を飛ばす
   * SMP の場合は dummy device として登録?

```c
/*
 * Setup the boot APIC
 *
 * Calibrate and verify the result.
 */
void __init setup_boot_APIC_clock(void)
{
	/*
	 * The local apic timer can be disabled via the kernel
	 * commandline or from the CPU detection code. Register the lapic
	 * timer as a dummy clock event source on SMP systems, so the
	 * broadcast mechanism is used. On UP systems simply ignore it.
	 */
	if (disable_apic_timer) {
		pr_info("Disabling APIC timer\n");
		/* No broadcast on UP ! */
		if (num_possible_cpus() > 1) {
			lapic_clockevent.mult = 1;
			setup_APIC_timer();
		}
		return;
	}

    // local APIC タイマーを使う場合
	apic_printk(APIC_VERBOSE, "Using local APIC timer interrupts.\n"
		    "calibrating APIC timer ...\n");

	if (calibrate_APIC_clock()) {
		/* No broadcast on UP ! */
		if (num_possible_cpus() > 1)
			setup_APIC_timer();
		return;
	}

	/*
	 * If nmi_watchdog is set to IO_APIC, we need the
	 * PIT/HPET going.  Otherwise register lapic as a dummy
	 * device.
	 */
	if (nmi_watchdog != NMI_IO_APIC)
		lapic_clockevent.features &= ~CLOCK_EVT_FEAT_DUMMY;
	else
		pr_warning("APIC timer registered as dummy,"
			" due to nmi_watchdog=%d!\n", nmi_watchdog);

	/* Setup the lapic or request the broadcast */
	setup_APIC_timer();
}
```

## tsc

```c
static struct clocksource clocksource_tsc = {
	.name                   = "tsc",
	.rating                 = 300,
	.read                   = read_tsc,
	.resume			= resume_tsc,
	.mask                   = CLOCKSOURCE_MASK(64),
	.shift                  = 22,
	.flags                  = CLOCK_SOURCE_IS_CONTINUOUS |
				  CLOCK_SOURCE_MUST_VERIFY,
#ifdef CONFIG_X86_64
	.vread                  = vread_tsc,
#endif
};
```

read_tsc の中身

```c
/*
 * We compare the TSC to the cycle_last value in the clocksource
 * structure to avoid a nasty time-warp. This can be observed in a
 * very small window right after one CPU updated cycle_last under
 * xtime/vsyscall_gtod lock and the other CPU reads a TSC value which
 * is smaller than the cycle_last reference value due to a TSC which
 * is slighty behind. This delta is nowhere else observable, but in
 * that case it results in a forward time jump in the range of hours
 * due to the unsigned delta calculation of the time keeping core
 * code, which is necessary to support wrapping clocksources like pm
 * timer.
 */
static cycle_t read_tsc(struct clocksource *cs)
{
	cycle_t ret = (cycle_t)get_cycles();

	return ret >= clocksource_tsc.cycle_last ?
		ret : clocksource_tsc.cycle_last;
}
```

get_cycles の中身は rdtscll

```
static inline cycles_t get_cycles(void)
{
	unsigned long long ret = 0;

#ifndef CONFIG_X86_TSC
	if (!cpu_has_tsc)
		return 0;
#endif
	rdtscll(ret);

	return ret;
}
```

rdtscll は rdtsc 命令呼び出しになる

```c
#define rdtscll(val)						\
	((val) = __native_read_tsc())

static __always_inline unsigned long long __native_read_tsc(void)
{
	DECLARE_ARGS(val, low, high);

	asm volatile("rdtsc" : EAX_EDX_RET(val, low, high));

	return EAX_EDX_VAL(val, low, high);
}
```

## acpi_pm

___ACPI PM タイマ = Advanced Configuration and Power Interface Power Management Timer___

```c
static struct clocksource clocksource_acpi_pm = {
	.name		= "acpi_pm",
	.rating		= 200,
	.read		= acpi_pm_read,
	.mask		= (cycle_t)ACPI_PM_MASK,
	.mult		= 0, /*to be calculated*/
	.shift		= 22,
	.flags		= CLOCK_SOURCE_IS_CONTINUOUS,

};
```

acpi_pm_read の実装は下記の通り

```
static cycle_t acpi_pm_read(struct clocksource *cs)
{
	return (cycle_t)read_pmtmr();
}
```

read_pmtmr で I/Oポートから時刻をとっているのかな?

```
/*
 * The I/O port the PMTMR resides at.
 * The location is detected during setup_arch(),
 * in arch/i386/kernel/acpi/boot.c
 */
u32 pmtmr_ioport __read_mostly;

static inline u32 read_pmtmr(void)
{
	/* mask the output to 24 bits */
	return inl(pmtmr_ioport) & ACPI_PM_MASK;
}
```

pmtmr_ioport のアドレスは dmesg に出てる

```
Apr  8 13:16:57 vagrant-centos65 kernel: ACPI: PM-Timer IO Port: 0x4008
```

PM-TImer IO Port は acpi_parse_fadt で出力されている

```c
static int __init acpi_parse_fadt(struct acpi_table_header *table)
{

#ifdef CONFIG_X86_PM_TIMER
	/* detect the location of the ACPI PM Timer */
	if (acpi_gbl_FADT.header.revision >= FADT2_REVISION_ID) {
		/* FADT rev. 2 */
		if (acpi_gbl_FADT.xpm_timer_block.space_id !=
		    ACPI_ADR_SPACE_SYSTEM_IO)
			return 0;

		pmtmr_ioport = acpi_gbl_FADT.xpm_timer_block.address;
		/*
		 * "X" fields are optional extensions to the original V1.0
		 * fields, so we must selectively expand V1.0 fields if the
		 * corresponding X field is zero.
	 	 */
		if (!pmtmr_ioport)
			pmtmr_ioport = acpi_gbl_FADT.pm_timer_block;
	} else {
		/* FADT rev. 1 */
		pmtmr_ioport = acpi_gbl_FADT.pm_timer_block;
	}
	if (pmtmr_ioport)
		printk(KERN_INFO PREFIX "PM-Timer IO Port: %#x\n",
		       pmtmr_ioport);
#endif
	return 0;
}
```

## dmesg

```
Mar 30 14:55:01 vagrant-centos65 kernel: ACPI: HPET 00000000264f02f0 00038 (v01 VBOX   VBOXHPET 00000001 ASL  00000061)
Mar 30 14:55:01 vagrant-centos65 kernel: ACPI: HPET id: 0x8086a201 base: 0xfed00000
Mar 30 14:55:01 vagrant-centos65 kernel: TSC: using HPET reference calibration
Mar 30 14:55:01 vagrant-centos65 kernel: HPET: 3 timers in total, 0 timers will be used for per-cpu timer
Mar 30 14:55:01 vagrant-centos65 kernel: hpet0: at MMIO 0xfed00000, IRQs 2, 8, 0
Mar 30 14:55:01 vagrant-centos65 kernel: hpet0: 3 comparators, 64-bit 100.000000 MHz counter
Mar 30 14:55:01 vagrant-centos65 kernel: Switching to clocksource hpet
Mar 30 14:55:01 vagrant-centos65 kernel: rtc0: alarms up to one day, 114 bytes nvram, hpet irqs
Mar 30 14:55:31 vagrant-centos65 kernel: ACPI: HPET 00000000264f02f0 00038 (v01 VBOX   VBOXHPET 00000001 ASL  00000061)
Mar 30 14:55:31 vagrant-centos65 kernel: ACPI: HPET id: 0x8086a201 base: 0xfed00000
Mar 30 14:55:31 vagrant-centos65 kernel: TSC: using HPET reference calibration
Mar 30 14:55:31 vagrant-centos65 kernel: HPET: 3 timers in total, 0 timers will be used for per-cpu timer
Mar 30 14:55:31 vagrant-centos65 kernel: hpet0: at MMIO 0xfed00000, IRQs 2, 8, 0
Mar 30 14:55:31 vagrant-centos65 kernel: hpet0: 3 comparators, 64-bit 100.000000 MHz counter
Mar 30 14:55:31 vagrant-centos65 kernel: Switching to clocksource hpet
Mar 30 14:55:31 vagrant-centos65 kernel: rtc0: alarms up to one day, 114 bytes nvram, hpet irqs
```

## /sys/devices/system/clocksource/clocksource0/current_clocksource

 * クロックソースを変えると `Switching to clocksource %s` のメッセージが出る
 * clocksource_list に `struct clocksource` がリストされている

```c
/**
 * clocksource_select - Select the best clocksource available
 *
 * Private function. Must hold clocksource_mutex when called.
 *
 * Select the clocksource with the best rating, or the clocksource,
 * which is selected by userspace override.
 */
static void clocksource_select(void)
{
	struct clocksource *best, *cs;

	if (!finished_booting || list_empty(&clocksource_list))
		return;
	/* First clocksource on the list has the best rating. */
	best = list_first_entry(&clocksource_list, struct clocksource, list);
	/* Check for the override clocksource. */
	list_for_each_entry(cs, &clocksource_list, list) {
		if (strcmp(cs->name, override_name) != 0)
			continue;
		/*
		 * Check to make sure we don't switch to a non-highres
		 * capable clocksource if the tick code is in oneshot
		 * mode (highres or nohz)
		 */
		if (!(cs->flags & CLOCK_SOURCE_VALID_FOR_HRES) &&
		    tick_oneshot_mode_active()) {
			/* Override clocksource cannot be used. */
			printk(KERN_WARNING "Override clocksource %s is not "
			       "HRT compatible. Cannot switch while in "
			       "HRT/NOHZ mode\n", cs->name);
			override_name[0] = 0;
		} else
			/* Override clocksource can be used. */
			best = cs;
		break;
	}
	if (curr_clocksource != best) {
		printk(KERN_INFO "Switching to clocksource %s\n", best->name);
		curr_clocksource = best;
		timekeeping_notify(curr_clocksource);
	}
}
```

timekeeping_notify で clocksource を切り替える

```c
/**
 * timekeeping_notify - Install a new clock source
 * @clock:		pointer to the clock source
 *
 * This function is called from clocksource.c after a new, better clock
 * source has been registered. The caller holds the clocksource_mutex.
 */
void timekeeping_notify(struct clocksource *clock)
{
	if (timekeeper.clock == clock)
		return;
	stop_machine(change_clocksource, clock, NULL);
    // 各CPU に clocksource が変わったことを notify
    // per_cpu でビットをたてておく
	tick_clock_notify();
}
```

stop_machine で 一時的に CPU を停止?するようだ

```c
int stop_machine(int (*fn)(void *), void *data, const struct cpumask *cpus)
{
	int ret;

	/* No CPUs can come up or down during this. */
	get_online_cpus();
	ret = __stop_machine(fn, data, cpus);
	put_online_cpus();
	return ret;
}
EXPORT_SYMBOL_GPL(stop_machine);
```