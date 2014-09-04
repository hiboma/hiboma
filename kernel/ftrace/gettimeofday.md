# gettimeofday

## vagrant での実行結果

ACPI から時刻を読み取っていた

```
            ruby-2564  [000] 104284.076140: funcgraph_entry:                   |  sys_gettimeofday() {
            ruby-2564  [000] 104284.076145: funcgraph_entry:                   |    do_gettimeofday() {
            ruby-2564  [000] 104284.076149: funcgraph_entry:                   |      getnstimeofday() {
            ruby-2564  [000] 104284.076153: funcgraph_entry:        6.696 us   |        acpi_pm_read();
            ruby-2564  [000] 104284.076165: funcgraph_exit:       + 15.548 us  |      }
            ruby-2564  [000] 104284.076169: funcgraph_exit:       + 24.388 us  |    }
            ruby-2564  [000] 104284.076174: funcgraph_exit:       + 33.267 us  |  }
```

available_clocksource を確認すると確かに **acpi_pm**

```
# cat /sys/devices/system/clocksource/clocksource0/available_clocksource 
acpi_pm 
```

## acpi_pm_read

`ACPI PM based clocksource.` の実装だそうです

```c
static cycle_t acpi_pm_read(struct clocksource *cs)
{
	return (cycle_t)read_pmtmr();
}

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

read_pmtmr で PMTMR? とかいう I/O ポートから時刻をとれるらしい

```c
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

## getnstimeofday

 * struct timespec で時刻を返す
 * 精度はナノ

```c
/**
 * getnstimeofday - Returns the time of day in a timespec
 * @ts:		pointer to the timespec to be set
 *
 * Returns the time of day in a timespec.
 */
void getnstimeofday(struct timespec *ts)
{
	unsigned long seq;
	s64 nsecs;

	WARN_ON(timekeeping_suspended);

	do {
		seq = read_seqbegin(&timekeeper.lock);

		*ts = timekeeper.xtime;
		nsecs = timekeeping_get_ns();

		/* If arch requires, add in gettimeoffset() */
		nsecs += arch_gettimeoffset();

	} while (read_seqretry(&timekeeper.lock, seq));

	timespec_add_ns(ts, nsecs);
}
EXPORT_SYMBOL(getnstimeofday);
```

available_clocksource から時計を取るのは timekeeping_get_ns の実装

 * inline なので ftrace では表示されない
 * `clock->read` でクロックソースの実装に委譲する ( acpi_pm_read )

```c
/* Timekeeper helper functions. */
static inline s64 timekeeping_get_ns(void)
{
	cycle_t cycle_now, cycle_delta;
	struct clocksource *clock;

	/* read clocksource: */
	clock = timekeeper.clock;
	cycle_now = clock->read(clock);

	/* calculate the delta since the last update_wall_time: */
	cycle_delta = (cycle_now - clock->cycle_last) & clock->mask;

	/* return delta convert to nanoseconds using ntp adjusted mult. */
	return clocksource_cyc2ns(cycle_delta, timekeeper.mult,
				  timekeeper.shift);
}
```

## do_gettimeofday

getnstimeofday の精度をマイクロ秒まで落として、 gettimeofday に返す

```c
/**
 * do_gettimeofday - Returns the time of day in a timeval
 * @tv:		pointer to the timeval to be set
 *
 * NOTE: Users should be converted to using getnstimeofday()
 */
void do_gettimeofday(struct timeval *tv)
{
	struct timespec now;

	getnstimeofday(&now);
	tv->tv_sec = now.tv_sec;
	tv->tv_usec = now.tv_nsec/1000;
}
EXPORT_SYMBOL(do_gettimeofday);
```