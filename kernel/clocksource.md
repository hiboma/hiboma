

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
	tick_clock_notify();
}
```

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