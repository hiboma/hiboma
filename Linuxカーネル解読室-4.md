# 4 時計

## 4.1

 * 時刻
   * 1970月1月1日0時〜
 * 時限処理
   * あとでやる
   * デバイスポーリング
   * SIGALRM
 * グローバルタイマ
   * do_timer
 * CPUローカルタイマ
   * smp_local_timer_interrupt

## グローバルタイマー割り込みハンドラ

### do_timer ロードアベレージの計算

CentOS6.5 だと書籍とだいぶ違う。 **TODO** x86 の割り込みからのエントリポイントは?

```c
/*
 * The 64-bit jiffies value is not atomic - you MUST NOT read it
 * without sampling the sequence number in xtime_lock.
 * jiffies is defined in the linker script...
 */
void do_timer(unsigned long ticks)
{
	jiffies_64 += ticks;
	update_wall_time();
	calc_global_load();
}
```

calc_global_load でロードアベレージの計算をする

```c
/*
 * calc_load - update the avenrun load estimates 10 ticks after the
 * CPUs have updated calc_load_tasks.
 */
void calc_global_load(void)
{
	unsigned long upd = calc_load_update + 10;
	long active;

	if (time_before(jiffies, upd))
		return;

	active = atomic_long_read(&calc_load_tasks);
	active = active > 0 ? active * FIXED_1 : 0;

	avenrun[0] = calc_load(avenrun[0], EXP_1, active);
	avenrun[1] = calc_load(avenrun[1], EXP_5, active);
	avenrun[2] = calc_load(avenrun[2], EXP_15, active);

	calc_load_update += LOAD_FREQ;
}
```

移動平均?

```c
static unsigned long
calc_load(unsigned long load, unsigned long exp, unsigned long active)
{
	load *= exp;
	load += active * (FIXED_1 - exp);
	return load >> FSHIFT;
}
```

## 4.2.2 CPUローカルな時計 - ハードウェア割り込み

 * コアごとにズラす
 * プロファイリング
 * scheduler_tick

## smp_local_timer_interrupt (2.6.15)

CONFIG_SMP で update_process_times を呼び出すか否かが変わる

 * update_process_times
   * account_user_time
   * account_system_time
     * acct_update_integrals

```c
/*
 * Local timer interrupt handler. It does both profiling and
 * process statistics/rescheduling.
 *
 * We do profiling in every local tick, statistics/rescheduling
 * happen only every 'profiling multiplier' ticks. The default
 * multiplier is 1 and it can be changed by writing the new multiplier
 * value into /proc/profile.
 */

inline void smp_local_timer_interrupt(struct pt_regs * regs)
{
	int cpu = smp_processor_id();

	profile_tick(CPU_PROFILING, regs);

    // プロファイラを起動???
	if (--per_cpu(prof_counter, cpu) <= 0) {
		/*
		 * The multiplier may have changed since the last time we got
		 * to this point as a result of the user writing to
		 * /proc/profile. In this case we need to adjust the APIC
		 * timer accordingly.
		 *
		 * Interrupts are already masked off at this point.
		 */
		per_cpu(prof_counter, cpu) = per_cpu(prof_multiplier, cpu);
		if (per_cpu(prof_counter, cpu) !=
					per_cpu(prof_old_multiplier, cpu)) {
			__setup_APIC_LVTT(
					calibration_result/
					per_cpu(prof_counter, cpu));
			per_cpu(prof_old_multiplier, cpu) =
						per_cpu(prof_counter, cpu);
		}

#ifdef CONFIG_SMP
        // ((regs->xcs & 3) | (regs->eflags & VM_MASK)) != 0;
        // CSレジスタ ... ???
        // EFLAFGS    ... VM_MASK 仮想X86モード?
		update_process_times(user_mode_vm(regs));
#endif
	}

	/*
	 * We take the 'long' return path, and there every subsystem
	 * grabs the apropriate locks (kernel lock/ irq lock).
	 *
	 * we might want to decouple profiling from the 'long path',
	 * and do the profiling totally in assembly.
	 *
	 * Currently this isn't too much of an issue (performance wise),
	 * we can take more than 100K local irqs per second on a 100 MHz P5.
	 */
}
```

update_process_times でローカルタイマ割り込みを受けた際の task_struct の時間の統計を出す

 * run_local_timers (softirq の実行)
 * CPU時間の統計
 * 再スケジューリング
   * scheduler_tick
 * posix タイマ (struct k_timer) => timer_create(2)
   * check_thread_timers
     * RLIMIT_RTTIME
   * check_process_timers
     * CPUCLOCK_PROF
     * CPUCLOCK_VIRT
     * CPUCLOCK_SCHED
     * RLIMIT_CPU を超えてないかどうか

```c
/*
 * Called from the timer interrupt handler to charge one tick to the current 
 * process.  user_tick is 1 if the tick is user time, 0 for system.
 */
void update_process_times(int user_tick)
{
	struct task_struct *p = current;
	int cpu = smp_processor_id();

	/* Note: this timer irq context must be accounted for as well. */
	if (user_tick)
		account_user_time(p, jiffies_to_cputime(1));
	else
		account_system_time(p, HARDIRQ_OFFSET, jiffies_to_cputime(1));
	run_local_timers();
	if (rcu_pending(cpu))
		rcu_check_callbacks(cpu, user_tick);

    /* 再スケジューリング */
	scheduler_tick();

    /* posix タイマ */
 	run_posix_cpu_timers(p);
}
```

account_user_time, account_system_time でタスクのCPU統計と、CPUの統計を出す

 * account_system_time が IRQ, SOFTIRQ, system時間, ... と分類されていておもしろい
   * munin のグラフで見るのもこれ
 * account_user_time は nice 時間が特殊かな?

```c
/*
 * Account user cpu time to a process.
 * @p: the process that the cpu time gets accounted to
 * @hardirq_offset: the offset to subtract from hardirq_count()
 * @cputime: the cpu time spent in user space since the last update
 */
void account_user_time(struct task_struct *p, cputime_t cputime)
{
	struct cpu_usage_stat *cpustat = &kstat_this_cpu.cpustat;
	cputime64_t tmp;

    // プロセスの user 時間に加算
	p->utime = cputime_add(p->utime, cputime);

	/* Add user time to cpustat. */
	tmp = cputime_to_cputime64(cputime);

    // CPU自体がどう使われたのかの統計?
    // NICE 値が 0 以上なら nice 時間として加算
	if (TASK_NICE(p) > 0)
		cpustat->nice = cputime64_add(cpustat->nice, tmp);
	else
		cpustat->user = cputime64_add(cpustat->user, tmp);
}

/*
 * Account system cpu time to a process.
 * @p: the process that the cpu time gets accounted to
 * @hardirq_offset: the offset to subtract from hardirq_count()
 * @cputime: the cpu time spent in kernel space since the last update
 */
void account_system_time(struct task_struct *p, int hardirq_offset,
			 cputime_t cputime)
{
	struct cpu_usage_stat *cpustat = &kstat_this_cpu.cpustat;
	runqueue_t *rq = this_rq();
	cputime64_t tmp;

	p->stime = cputime_add(p->stime, cputime);

	/* Add system time to cpustat. */
	tmp = cputime_to_cputime64(cputime);

    // IRQ, SOFTIRQ, system時間, I/O wait、idle で分類している
	if (hardirq_count() - hardirq_offset)
		cpustat->irq = cputime64_add(cpustat->irq, tmp);
	else if (softirq_count())
		cpustat->softirq = cputime64_add(cpustat->softirq, tmp);
	else if (p != rq->idle)
		cpustat->system = cputime64_add(cpustat->system, tmp);
	else if (atomic_read(&rq->nr_iowait) > 0)
		cpustat->iowait = cputime64_add(cpustat->iowait, tmp);
	else
		cpustat->idle = cputime64_add(cpustat->idle, tmp);
	/* Account for system time used */
	acct_update_integrals(p);
}
```

acct_update_integrals で acct(2) アカウンティング統計を更新?

```c
/**
 * acct_update_integrals - update mm integral fields in task_struct
 * @tsk: task_struct for accounting
 */
void acct_update_integrals(struct task_struct *tsk)
{
	if (likely(tsk->mm)) {
		long delta = tsk->stime - tsk->acct_stimexpd;

		if (delta == 0)
			return;
		tsk->acct_stimexpd = tsk->stime;
		tsk->acct_rss_mem1 += delta * get_mm_rss(tsk->mm);
		tsk->acct_vm_mem1 += delta * tsk->mm->total_vm;
	}
}
```

### scheduler_tick

HZの頻度で呼び出しされる (= ローカルタイマ)

```
/*
 * This function gets called by the timer code, with HZ frequency.
 * We call it with interrupts disabled.
 *
 * It also gets called by the fork code, when changing the parent's
 * timeslices.
 */
void scheduler_tick(void)
{
	int cpu = smp_processor_id();
	struct rq *rq = cpu_rq(cpu);
	struct task_struct *curr = rq->curr;

	sched_clock_tick();

	spin_lock(&rq->lock);
	update_rq_clock(rq);
	update_cpu_load_active(rq);
	curr->sched_class->task_tick(rq, curr, 0);
	spin_unlock(&rq->lock);

	perf_event_task_tick();

#ifdef CONFIG_SMP
	rq->idle_at_tick = idle_cpu(cpu);
	trigger_load_balance(rq, cpu);
#endif
}
```

## 4.2.3 CPUローカルな時計 - ソフト割り込み

 * タイマーリスト (struct timer_list)
 * 縮退
   * 複数回のローカルタイマ割り込みに対して、一回しかローカルタイマソフト割り込みが実行されないこと
   * まとめてやりなおす

```c
/*
 * Called by the local, per-CPU timer interrupt on SMP.
 */
void run_local_timers(void)
{
    // hrtimer ? でキューイングされてるジョブを実行?
	hrtimer_run_queues();
	raise_softirq(TIMER_SOFTIRQ);
}
```

TIMER_SOFTIRQ に対応するのは run_timer_softirq。 init_timers で登録されている

```c

void __init init_timers(void)
{
	int err = timer_cpu_notify(&timers_nb, (unsigned long)CPU_UP_PREPARE,
				(void *)(long)smp_processor_id());

	init_timer_stats();

	BUG_ON(err == NOTIFY_BAD);
	register_cpu_notifier(&timers_nb);
	open_softirq(TIMER_SOFTIRQ, run_timer_softirq);
}
```

run_timer_softirq の実装

```c
/*
 * This function runs timers and the timer-tq in bottom half context.
 */
static void run_timer_softirq(struct softirq_action *h)
{
	struct tvec_base *base = __get_cpu_var(tvec_bases);

	hrtimer_run_pending();

	if (time_after_eq(jiffies, base->timer_jiffies))
		__run_timers(base);
}
```

__run_timers でタイマ (struct timer_list) の実行?

 * keepalive のタイマとか?
 * timer_list の実装サンプル [refs](https://github.com/hiboma/kernel_module_scratch/blob/master/tasklet/tasklet.c)

```c
/**
 * __run_timers - run all expired timers (if any) on this CPU.
 * @base: the timer vector to be processed.
 *
 * This function cascades all vectors and executes all expired timer
 * vectors.
 */
static inline void __run_timers(struct tvec_base *base)
{
	struct timer_list *timer;

	spin_lock_irq(&base->lock);
	while (time_after_eq(jiffies, base->timer_jiffies)) {
		struct list_head work_list;
		struct list_head *head = &work_list;
		int index = base->timer_jiffies & TVR_MASK;

		/*
		 * Cascade timers:
		 */
		if (!index &&
			(!cascade(base, &base->tv2, INDEX(0))) &&
				(!cascade(base, &base->tv3, INDEX(1))) &&
					!cascade(base, &base->tv4, INDEX(2)))
			cascade(base, &base->tv5, INDEX(3));
		++base->timer_jiffies;
		list_replace_init(base->tv1.vec + index, &work_list);
		while (!list_empty(head)) {
			void (*fn)(unsigned long);
			unsigned long data;

            /* タイマ */
			timer = list_first_entry(head, struct timer_list,entry);
			fn = timer->function;
			data = timer->data;

			timer_stats_account_timer(timer);

			set_running_timer(base, timer);
			detach_timer(timer, 1);

			spin_unlock_irq(&base->lock);
			{
				int preempt_count = preempt_count();

#ifdef CONFIG_LOCKDEP
				/*
				 * It is permissible to free the timer from
				 * inside the function that is called from
				 * it, this we need to take into account for
				 * lockdep too. To avoid bogus "held lock
				 * freed" warnings as well as problems when
				 * looking into timer->lockdep_map, make a
				 * copy and use that here.
				 */
				struct lockdep_map lockdep_map =
					timer->lockdep_map;
#endif
				/*
				 * Couple the lock chain with the lock chain at
				 * del_timer_sync() by acquiring the lock_map
				 * around the fn() call here and in
				 * del_timer_sync().
				 */
				lock_map_acquire(&lockdep_map);

				trace_timer_expire_entry(timer);

                /* タイマの実行 */
				fn(data);
				trace_timer_expire_exit(timer);

				lock_map_release(&lockdep_map);

				if (preempt_count != preempt_count()) {
					printk(KERN_ERR "huh, entered %p "
					       "with preempt_count %08x, exited"
					       " with %08x?\n",
					       fn, preempt_count,
					       preempt_count());
					BUG();
				}
			}
			spin_lock_irq(&base->lock);
		}
	}
	set_running_timer(base, NULL);
	spin_unlock_irq(&base->lock);
}
```

## 4.3 Linux の時刻

### 4.3.1 Linux 内部時計

 * UTC 1970/1/1 からの経過時間を **xtime**
 * stime(2), settimeofday(2)
 * NTP slew mode

### 4.3.2 ハードウェアのカレンダ

 * **カレンダ** と呼ばれるコントローラー
 * hwclock <=> Linux 内部時計
 * BIOS とかでセットするやつ
 * /dev/rtc

```
[vagrant@vagrant-centos65 ~]$ ls -hal /dev/rtc*
lrwxrwxrwx 1 root root      4 May 19 12:44 /dev/rtc -> rtc0
crw-rw---- 1 root root 254, 0 May 19 12:44 /dev/rtc0
```

### 4.3.4 タイムスタンプカウンタ

## 4.4 各種タイマー関連ハードゥエア

## 4.5 時刻の取得

 * time(2), gettimeofday(2)
   * time は精度が秒
   * gettimeofday は精度が マイクロ秒

```c

	time_t t;
	if(time(&t) == -1) {
		perror("time");
		exit(1);
	}

	struct timeval tv;
	if(gettimeofday(&tv, NULL) == -1) {
		perror("gettimeofday");
		exit(1);
	}

	printf("%ld\n", t);
	printf("%ld - %d\n", tv.tv_sec, tv.tv_usec);
```

型　| 精度
---|---
time_t | 秒
struct timeval | マイクロ秒
struct timespec | ナノ秒

### time(2) の実装

```c
/*
 * sys_time() can be implemented in user-level using
 * sys_gettimeofday().  Is this for backwards compatibility?  If so,
 * why not move it into the appropriate arch directory (for those
 * architectures that need it).
 */
SYSCALL_DEFINE1(time, time_t __user *, tloc)
{
    // ->
	time_t i = get_seconds();

	if (tloc) {
		if (put_user(i,tloc))
			return -EFAULT;
	}
	force_successful_syscall_return();
	return i;
}
```

get_seconds の中身は **timekeeper.xtime.tv_sec** を return するだけ

```c
unsigned long get_seconds(void)
{
	return timekeeper.xtime.tv_sec;
}
EXPORT_SYMBOL(get_seconds);
```

### gettimeofday(2) の実装

```c
SYSCALL_DEFINE2(gettimeofday, struct timeval __user *, tv,
		struct timezone __user *, tz)
{
	if (likely(tv != NULL)) {
		struct timeval ktv;
        // ->
		do_gettimeofday(&ktv);
		if (copy_to_user(tv, &ktv, sizeof(ktv)))
			return -EFAULT;
	}
	if (unlikely(tz != NULL)) {
		if (copy_to_user(tz, &sys_tz, sizeof(sys_tz)))
			return -EFAULT;
	}
	return 0;
}
```

do_gettimeofday の中身

  * tv_sec の扱いは time(2) と一緒
  * tv_usec は getnstimeofday を追う必要がある

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

    // ->
	getnstimeofday(&now);
	tv->tv_sec = now.tv_sec;
    // nanosec を 1000 で割って usec に変換している
	tv->tv_usec = now.tv_nsec/1000;
}
EXPORT_SYMBOL(do_gettimeofday);
```

getnstimeofday は ナノ秒を精度として時刻取得する

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
        // シーケンシャル読み取りロック?
		seq = read_seqbegin(&timekeeper.lock);

		*ts = timekeeper.xtime;

        // ナノ秒
		nsecs = timekeeping_get_ns();

		/* If arch requires, add in gettimeoffset() */
		nsecs += arch_gettimeoffset();

   // ロックとれるまでループ
	} while (read_seqretry(&timekeeper.lock, seq));

    // ?
	timespec_add_ns(ts, nsecs);
}
EXPORT_SYMBOL(getnstimeofday);
```