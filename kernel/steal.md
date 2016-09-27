# /proc/stat steal

メトリクスで表示される **%steal** の実態を追う

```
top - 17:07:52 up 208 days,  1:19,  3 users,  load average: 0.12, 0.11, 0.13
Tasks: 129 total,   1 running, 128 sleeping,   0 stopped,   0 zombie
%Cpu0  :  4.0 us,  1.0 sy,  0.0 ni, 92.1 id,  3.0 wa,  0.0 hi,  0.0 si,  0.0 st
%Cpu1  :  2.0 us,  1.0 sy,  0.0 ni, 94.0 id,  2.0 wa,  0.0 hi,  0.0 si,  1.0 st
%Cpu2  :  3.0 us,  0.0 sy,  0.0 ni, 96.0 id,  1.0 wa,  0.0 hi,  0.0 si,  0.0 st
%Cpu3  :  4.0 us,  2.0 sy,  0.0 ni, 90.1 id,  3.0 wa,  0.0 hi,  0.0 si,  1.0 st
KiB Mem :  3882188 total,   408364 free,   249212 used,  3224612 buff/cache
KiB Swap:   421884 total,   421884 free,        0 used.  3348956 avail Mem 
Change delay from 1.0 to 
```

## どこで値をとれるか

値は `/proc/stat` で取れる

```
$ cat /proc/stat
cpu  104081295 44432 5368640 1310420768 1771744 0 344335 570240 0 0
cpu0 19641585 7271 1287977 334091326 499663 0 21771 143394 0 0
cpu1 58697902 2625 1907542 293707021 394457 0 311519 197877 0 0
cpu2 14328989 14672 1138997 339769757 452081 0 7159 121860 0 0
cpu3 11412819 19863 1034123 342852662 425542 0 3885 107108 0 0
intr 3080341771 126 10 0 0 0 0 3 0 0 0 0 23 144 0 0 3479645 0 0 0 0 0 0 0 0 0 5449754 0 785365473 8083 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
ctxt 2664678820
btime 1470107891
processes 17839700
procs_running 2
procs_blocked 0
softirq 2638614457 2 1329269733 323 822177513 1739859 0 10775 198077892 0 287338360
```

## Documentation/filesystems/proc.txt

```
The very first  "cpu" line aggregates the  numbers in all  of the other "cpuN"
lines.  These numbers identify the amount of time the CPU has spent performing
different kinds of work.  Time units are in USER_HZ (typically hundredths of a
second).  The meanings of the columns are as follows, from left to right:

- user: normal processes executing in user mode
- nice: niced processes executing in user mode
- system: processes executing in kernel mode
- idle: twiddling thumbs
- iowait: waiting for I/O to complete
- irq: servicing interrupts
- softirq: servicing softirqs
- steal: involuntary wait ★
- guest: running a normal guest
- guest_nice: running a niced guest
```

**involuntary wait**

## Other Documents

```
# https://access.redhat.com/documentation/ja-JP/Red_Hat_Enterprise_Linux/6/html/6.3_Release_Notes/virtualization.html

KVM 「Steal Time」 のサポート
Steal time (スチールタイム) とは、ハイパーバイザーが別の仮想プロセッサを担当している間に、仮想 CPU が実 CPU を待つ時間のことです。KVM の仮想化マシンは今回、ゲストに正確な CPU 運用データを提供する top と vmstat のようなツールを介して可視化されるスチールタイムを算出して報告できます。
KVM のスチールタイム機能は、CPU 運用と仮想化マシンのパフォーマンスに関してゲストに正確なデータを提供します。大幅なスチールタイムは、仮想マシンのパフォーマンスが、ハイパーバイザーでゲストに割り当てられた CPU タイムによって縮小されていることを示します。ユーザーは、ホスト上でゲスト数を低減するか、又はゲストの CPU 優先度を増加することにより、CPU 闘争から出るパフォーマンス問題を軽減することができます。KVM スチールタイムの値は、ユーザーに対してアプリケーションのランタイムパフォーマンスの改善で次のステップへ進む為のデータを提供します。BZ#612320
```

```
# https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Virtualization_Deployment_and_Administration_Guide/sect-KVM_guest_timing_management-Steal_time_accounting.html

9.2. STEAL TIME ACCOUNTING

Steal time is the amount of CPU time desired by a guest virtual machine that is not provided by the host. Steal time occurs when the host allocates these resources elsewhere: for example, to another guest.
Steal time is reported in the CPU time fields in /proc/stat as st. It is automatically reported by utilities such as top and vmstat, and cannot be switched off.
Large amounts of steal time indicate CPU contention, which can reduce guest performance. To relieve CPU contention, increase the guest's CPU priority or CPU quota, or run fewer guests on the host.
```

* http://blog.scoutapp.com/articles/2013/07/25/understanding-cpu-steal-time-when-should-you-be-worried
  * VM 全体で steal しているか、一部の VM で streal しているかで状態を判断する
  * ???

```
Has %st (CPU Steal Time Percentage) increased on every virtual server? This means your virtual machines are using more CPU. You need to increase the CPU resources for your VMs.

Has %st (CPU Steal Time Percentage) increased dramatically on only a subset of servers? This means the physical servers may be oversold. Move the VM to another physical server.
```

```
A general rule of thumb - if steal time is greater than 10% for 20 minutes, the VM is likely in a state that it is running slower than it should.
```

## implemantation of /proc/stat handler

```c
static int show_stat(struct seq_file *p, void *v)
{
	int i, j;
	unsigned long jif;
	u64 user, nice, system, idle, iowait, irq, softirq, steal;
	u64 guest, guest_nice;
	u64 sum = 0;
	u64 sum_softirq = 0;
	unsigned int per_softirq_sums[NR_SOFTIRQS] = {0};
	struct timespec boottime;

	user = nice = system = idle = iowait =
		irq = softirq = steal = 0;
	guest = guest_nice = 0;
	getboottime(&boottime);
	jif = boottime.tv_sec;

	for_each_possible_cpu(i) {
		user += kcpustat_cpu(i).cpustat[CPUTIME_USER];
		nice += kcpustat_cpu(i).cpustat[CPUTIME_NICE];
		system += kcpustat_cpu(i).cpustat[CPUTIME_SYSTEM];
		idle += get_idle_time(i);
		iowait += get_iowait_time(i);
		irq += kcpustat_cpu(i).cpustat[CPUTIME_IRQ];
		softirq += kcpustat_cpu(i).cpustat[CPUTIME_SOFTIRQ];
		steal += kcpustat_cpu(i).cpustat[CPUTIME_STEAL]; ★
		guest += kcpustat_cpu(i).cpustat[CPUTIME_GUEST];
		guest_nice += kcpustat_cpu(i).cpustat[CPUTIME_GUEST_NICE];
		sum += kstat_cpu_irqs_sum(i);
		sum += arch_irq_stat_cpu(i);

		for (j = 0; j < NR_SOFTIRQS; j++) {
			unsigned int softirq_stat = kstat_softirqs_cpu(j, i);

			per_softirq_sums[j] += softirq_stat;
			sum_softirq += softirq_stat;
		}
	}
	sum += arch_irq_stat();

	seq_puts(p, "cpu ");
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(user));
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(nice));
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(system));
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(idle));
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(iowait));
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(irq));
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(softirq));
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(steal)); ★
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(guest));
	seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(guest_nice));
	seq_putc(p, '\n');

	for_each_online_cpu(i) {
		/* Copy values here to work around gcc-2.95.3, gcc-2.96 */
		user = kcpustat_cpu(i).cpustat[CPUTIME_USER];
		nice = kcpustat_cpu(i).cpustat[CPUTIME_NICE];
		system = kcpustat_cpu(i).cpustat[CPUTIME_SYSTEM];
		idle = get_idle_time(i);
		iowait = get_iowait_time(i);
		irq = kcpustat_cpu(i).cpustat[CPUTIME_IRQ];
		softirq = kcpustat_cpu(i).cpustat[CPUTIME_SOFTIRQ];
		steal = kcpustat_cpu(i).cpustat[CPUTIME_STEAL]; ★
		guest = kcpustat_cpu(i).cpustat[CPUTIME_GUEST];
		guest_nice = kcpustat_cpu(i).cpustat[CPUTIME_GUEST_NICE];
		seq_printf(p, "cpu%d", i);
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(user));
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(nice));
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(system));
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(idle));
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(iowait));
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(irq));
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(softirq));
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(steal)); ★
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(guest));
		seq_put_decimal_ull(p, ' ', cputime64_to_clock_t(guest_nice));
		seq_putc(p, '\n');
	}
	seq_printf(p, "intr %llu", (unsigned long long)sum);

	/* sum again ? it could be updated? */
	for_each_irq_nr(j)
		seq_put_decimal_ull(p, ' ', kstat_irqs(j));

	seq_printf(p,
		"\nctxt %llu\n"
		"btime %lu\n"
		"processes %lu\n"
		"procs_running %lu\n"
		"procs_blocked %lu\n",
		nr_context_switches(),
		(unsigned long)jif,
		total_forks,
		nr_running(),
		nr_iowait());

	seq_printf(p, "softirq %llu", (unsigned long long)sum_softirq);

	for (i = 0; i < NR_SOFTIRQS; i++)
		seq_put_decimal_ull(p, ' ', per_softirq_sums[i]);
	seq_putc(p, '\n');

	return 0;
}
```

## CPUTIME_STEAL の定義

```c
/*
 * 'kernel_stat.h' contains the definitions needed for doing
 * some kernel statistics (CPU usage, context switches ...),
 * used by rstatd/perfmeter
 */

enum cpu_usage_stat {
	CPUTIME_USER,
	CPUTIME_NICE,
	CPUTIME_SYSTEM,
	CPUTIME_SOFTIRQ,
	CPUTIME_IRQ,
	CPUTIME_IDLE,
	CPUTIME_IOWAIT,
	CPUTIME_STEAL,
	CPUTIME_GUEST,
	CPUTIME_GUEST_NICE,
	NR_STATS,
};
```

CPUTIME_STEALをがカウントする関数

```c
/*
 * Account for involuntary wait time.
 * @cputime: the cpu time spent in involuntary wait
 */
void account_steal_time(cputime_t cputime)
{
	u64 *cpustat = kcpustat_this_cpu->cpustat;

	cpustat[CPUTIME_STEAL] += (__force u64) cputime;
}
```

## account_steal_time の呼び出し元

```c
/*
 * Account multiple ticks of steal time.
 * @p: the process from which the cpu time has been stolen
 * @ticks: number of stolen ticks
 */
void account_steal_ticks(unsigned long ticks)
{
	account_steal_time(jiffies_to_cputime(ticks));
}
```

struct rq あたりを読んでいかないとどういう実装なのか分からなそう

 * struct rq
 * prev_steal_time

あたりが肝か

```c
static __always_inline bool steal_account_process_tick(void)
{
#ifdef CONFIG_PARAVIRT
	if (static_key_false(&paravirt_steal_enabled)) {
		u64 steal;
		cputime_t steal_ct;

		steal = paravirt_steal_clock(smp_processor_id());

        // #define this_rq()		(&__get_cpu_var(runqueues))
		steal -= this_rq()->prev_steal_time;

		/*
		 * cputime_t may be less precise than nsecs (eg: if it's
		 * based on jiffies). Lets cast the result to cputime
		 * granularity and account the rest on the next rounds.
		 */
		steal_ct = nsecs_to_cputime(steal);
		this_rq()->prev_steal_time += cputime_to_nsecs(steal_ct);

		account_steal_time(steal_ct);
		return steal_ct;
	}
#endif
	return false;
}
```

## struct rq の prev_steal_time

```c
/*
 * This is the main, per-CPU runqueue data structure.
 *
 * Locking rule: those places that want to lock multiple runqueues
 * (such as the load balancing or the thread migration code), lock
 * acquire operations must be ordered by ascending &runqueue.
 */
struct rq {

...

#ifdef CONFIG_PARAVIRT
	u64 prev_steal_time;
#endif
#ifdef CONFIG_PARAVIRT_TIME_ACCOUNTING
	u64 prev_steal_time_rq;
#endif
```

ゲストは

 * PVOP_CALL1
 * pv_time_ops
 * steal_clock

でホストから値を取る

```
static inline u64 paravirt_steal_clock(int cpu)
{
	return PVOP_CALL1(u64, pv_time_ops.steal_clock, cpu);
}
```

 * `pv_time_ops.steal_clock` の初期化は `kvm_guest_init`
   * kvm_steal_clock 関数ポインタ
 * KVM_FEATURE_STEAL_TIME によって、KVM ゲストが steal を計測できる?

```
void __init kvm_guest_init(void)
{
	int i;

	if (!kvm_para_available())
		return;

	paravirt_ops_setup();
	register_reboot_notifier(&kvm_pv_reboot_nb);
	for (i = 0; i < KVM_TASK_SLEEP_HASHSIZE; i++)
		spin_lock_init(&async_pf_sleepers[i].lock);
	if (kvm_para_has_feature(KVM_FEATURE_ASYNC_PF))
		x86_init.irqs.trap_init = kvm_apf_trap_init;

	if (kvm_para_has_feature(KVM_FEATURE_STEAL_TIME)) { ★
		has_steal_clock = 1;
		pv_time_ops.steal_clock = kvm_steal_clock; ★
	}

	if (kvm_para_has_feature(KVM_FEATURE_PV_EOI))
		apic_set_eoi_write(kvm_guest_apic_eoi_write);

	if (kvmclock_vsyscall)
		kvm_setup_vsyscall_timeinfo();

#ifdef CONFIG_SMP
	smp_ops.smp_prepare_boot_cpu = kvm_smp_prepare_boot_cpu;
	register_cpu_notifier(&kvm_cpu_notifier);
#else
	kvm_guest_cpu_init();
#endif

	/*
	 * Hard lockup detection is enabled by default. Disable it, as guests
	 * can get false positives too easily, for example if the host is
	 * overcommitted.
	 */
	watchdog_enable_hardlockup_detector(false);
}
```

kvm_steal_clock の実装。 `&per_cpu(streal_time, ...` を読みとるだけ

 * これはゲストで実行している？ホストで?

```c
static u64 kvm_steal_clock(int cpu)
{
	u64 steal;
	struct kvm_steal_time *src;
	int version;

	src = &per_cpu(steal_time, cpu);
	do {
		version = src->version;
		rmb();
		steal = src->steal;
		rmb();
	} while ((version & 1) || (version != src->version));

	return steal;
}
```

`&per_cpu(streal_time, ...)` の登録?

```
static void kvm_register_steal_time(void)
{
	int cpu = smp_processor_id();
	struct kvm_steal_time *st = &per_cpu(steal_time, cpu);

	if (!has_steal_clock)
		return;

	memset(st, 0, sizeof(*st));

   // http://aya213.blogspot.jp/2009/09/rdmsr-wrmsr-in-c.html
	wrmsrl(MSR_KVM_STEAL_TIME, (slow_virt_to_phys(st) | KVM_MSR_ENABLED));
	pr_info("kvm-stealtime: cpu %d, msr %llx\n",
		cpu, (unsigned long long) slow_virt_to_phys(st));
}
```

#define MSR_KVM_STEAL_TIME  0x4b564d03

```c
int kvm_set_msr_common(struct kvm_vcpu *vcpu, struct msr_data *msr_info)
{
	bool pr = false;
	u32 msr = msr_info->index;
	u64 data = msr_info->data;

	switch (msr) {

...

	case MSR_KVM_STEAL_TIME:

		if (unlikely(!sched_info_on()))
			return 1;

		if (data & KVM_STEAL_RESERVED_MASK)
			return 1;

		if (kvm_gfn_to_hva_cache_init(vcpu->kvm, &vcpu->arch.st.stime,
						data & KVM_STEAL_VALID_BITS,
						sizeof(struct kvm_steal_time)))
			return 1;

		vcpu->arch.st.msr_val = data;

		if (!(data & KVM_MSR_ENABLED))
			break;

		vcpu->arch.st.last_steal = current->sched_info.run_delay;

		preempt_disable();
		accumulate_steal_time(vcpu);
		preempt_enable();

		kvm_make_request(KVM_REQ_STEAL_UPDATE, vcpu);

		break;
```

accumulate_steal_time で streal の計算

```c
static void accumulate_steal_time(struct kvm_vcpu *vcpu)
{
	u64 delta;

	if (!(vcpu->arch.st.msr_val & KVM_MSR_ENABLED))
		return;

	delta = current->sched_info.run_delay - vcpu->arch.st.last_steal;
	vcpu->arch.st.last_steal = current->sched_info.run_delay;
	vcpu->arch.st.accum_steal = delta;
}
```

以下の計算

 * steal は run_delay の差分ってことで OK ?
 * http://d.hatena.ne.jp/yohei-a/20150806/1438869775

```
	delta = current->sched_info.run_delay - vcpu->arch.st.last_steal;
	vcpu->arch.st.last_steal = current->sched_info.run_delay;
	vcpu->arch.st.accum_steal = delta;
```

rq で CPU を待っている時間が delta として計算されているのかな?

```c
/*
 * Expects runqueue lock to be held for atomicity of update
 */
static inline void
rq_sched_info_depart(struct rq *rq, unsigned long long delta)
{
	if (rq)
		rq->rq_cpu_time += delta;
}

static inline void
rq_sched_info_dequeued(struct rq *rq, unsigned long long delta)
{
	if (rq)
		rq->rq_sched_info.run_delay += delta;
}

```c
/*
 * We are interested in knowing how long it was from the *first* time a
 * task was queued to the time that it finally hit a cpu, we call this routine
 * from dequeue_task() to account for possible rq->clock skew across cpus. The
 * delta taken on each cpu would annul the skew.
 */
static inline void sched_info_dequeued(struct task_struct *t)
{
	unsigned long long now = rq_clock(task_rq(t)), delta = 0;

    // rq の「現在時刻」と last_queued の差をとる = delta
	if (unlikely(sched_info_on()))
		if (t->sched_info.last_queued)
			delta = now - t->sched_info.last_queued;
	sched_info_reset_dequeued(t);
	t->sched_info.run_delay += delta;

	rq_sched_info_dequeued(task_rq(t), delta);
}
```

/*
 * Called when a task finally hits the cpu.  We can now calculate how
 * long it was waiting to run.  We also note when it began so that we
 * can keep stats on how long its timeslice is.
 */
// キューイングされてから CPU とったとき
static void sched_info_arrive(struct task_struct *t)
{
	unsigned long long now = rq_clock(task_rq(t)), delta = 0;

	if (t->sched_info.last_queued)
		delta = now - t->sched_info.last_queued;
	sched_info_reset_dequeued(t);
	t->sched_info.run_delay += delta;
	t->sched_info.last_arrival = now;
	t->sched_info.pcount++;

	rq_sched_info_arrive(task_rq(t), delta);
}
```

## task_struct->sched_info の定義

```c
static inline int sched_info_on(void)
{
#ifdef CONFIG_SCHEDSTATS
	return 1;
#elif defined(CONFIG_TASK_DELAY_ACCT)
	extern int delayacct_on;
	return delayacct_on;
#else
	return 0;
#endif
}

...

#if defined(CONFIG_SCHEDSTATS) || defined(CONFIG_TASK_DELAY_ACCT)
struct sched_info {
	/* cumulative counters */
    // 積み重ね? カウンター?
	unsigned long pcount;	      /* # of times run on this cpu */

    // runqueue 待ちした時間
	unsigned long long run_delay; /* time spent waiting on a runqueue */

	/* timestamps */
	unsigned long long last_arrival,/* when we last ran on a cpu */    // 最後に CPU で実行されたタイムスタンプ
    			   last_queued;	/* when we were last queued to run */  // 最後に CPU 実行待ちで キューイング されたタイムスタンプ
};
#endif /* defined(CONFIG_SCHEDSTATS) || defined(CONFIG_TASK_DELAY_ACCT) */
```

構造体の説明を読むと、steal の計算式が読みやすくなる