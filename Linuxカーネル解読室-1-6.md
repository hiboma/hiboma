## 1.6　プロセススケジューラの実装

> Linuxカーネル2.4以前のプロセススケジューラは非常に単純な構造で、マルチプロセッサシステムであっても、単一のキューに実行可能プロセスをすべてつなぎ、再スケジューリングの度にキューに登録されているすべてのプロセスを検索して、実行権を与えるプロセスを選び出していました。

 * 単一のキュー
   * CPUが増えるにつれてスピンロックが競合しそう
   * 検索がプロセス数に対して O(N)

## 1.6.1　実行優先度ごとのRUNキュー

 * expired
   * タイムスライスが余ってる task
   * active キューが空になったら active に遷移
 * active
   * タイムスライスを使い切った task
   * active -> expired もしくは active -> TASK_UNINTERRUPTIBLE/TASK_INTERRUPTIBLE に遷移
 * キュー内でさらに実行優先度ごとに分類されている
   * struct prio_array_t のこと
 * runqueue に繋がっている限りは必ず CPU の実行が保証される

.6.32  では CFS が導入されているので全然違うことを確認する

### struct runqueue

2.6.15 の時点では struct runqueue だよ

```c
/*
 * This is the main, per-CPU runqueue data structure.
 *
 * Locking rule: those places that want to lock multiple runqueues
 * (such as the load balancing or the thread migration code), lock
 * acquire operations must be ordered by ascending &runqueue.
 */
struct runqueue {
	spinlock_t lock;

	/*
	 * nr_running and cpu_load should be in the same cacheline because
	 * remote CPUs use both these fields when doing load calculation.
	 */
	unsigned long nr_running;
#ifdef CONFIG_SMP
	unsigned long prio_bias;
    // ロードアベレージ?
	unsigned long cpu_load[3];
#endif
	unsigned long long nr_switches;

	/*
	 * This is part of a global counter where only the total sum
	 * over all CPUs matters. A task can increase this counter on
	 * one CPU and if it got migrated afterwards it may decrease
	 * it on another CPU. Always updated under the runqueue lock:
	 */
	unsigned long nr_uninterruptible;

	unsigned long expired_timestamp;
	unsigned long long timestamp_last_tick;
	task_t *curr, *idle;
	struct mm_struct *prev_mm;
    // 優先度ごとのキュー
	prio_array_t *active, *expired, arrays[2];
	int best_expired_prio;
	atomic_t nr_iowait;

#ifdef CONFIG_SMP
    // スケジューリングドメイン
	struct sched_domain *sd;

	/* For active balancing */
	int active_balance;
	int push_cpu;

	task_t *migration_thread;
	struct list_head migration_queue;
#endif

#ifdef CONFIG_SCHEDSTATS
	/* latency stats */
	struct sched_info rq_sched_info;

	/* sys_sched_yield() stats */
	unsigned long yld_exp_empty;
	unsigned long yld_act_empty;
	unsigned long yld_both_empty;
	unsigned long yld_cnt;

	/* schedule() stats */
	unsigned long sched_switch;
	unsigned long sched_cnt;
	unsigned long sched_goidle;

	/* try_to_wake_up() stats */
	unsigned long ttwu_cnt;
	unsigned long ttwu_local;
#endif
};
```

### struct rq

2.6.32 では struct rq だよ

```c
/*
 * This is the main, per-CPU runqueue data structure.
 *
 * Locking rule: those places that want to lock multiple runqueues
 * (such as the load balancing or the thread migration code), lock
 * acquire operations must be ordered by ascending &runqueue.
 */
struct rq {
	/* runqueue lock: */
    // rq は CPUごとに用意されているので, 単一のロックを取る場合は競合しない?
    // ロードバランシングやスレッドマイグレーションする場合は 複数の rq スピンロックが必要
    // => 競合を起こす
	spinlock_t lock;

	/*
	 * nr_running and cpu_load should be in the same cacheline because
	 * remote CPUs use both these fields when doing load calculation.
	 */
    // nr_running と cpu_load の キャッシュラインを揃える
	unsigned long nr_running;
	#define CPU_LOAD_IDX_MAX 5
	unsigned long cpu_load[CPU_LOAD_IDX_MAX];
#ifdef CONFIG_NO_HZ
	unsigned long last_tick_seen;
	unsigned char in_nohz_recently;
#endif
	/* capture load from *all* tasks on this cpu: */
	struct load_weight load;
	unsigned long nr_load_updates;
	u64 nr_switches;

    // CFS用のキュー
	struct cfs_rq cfs;
    // リアルタイムプロセス用のキュー
	struct rt_rq rt;

#ifdef CONFIG_FAIR_GROUP_SCHED
	/* list of leaf cfs_rq on this cpu: */
	struct list_head leaf_cfs_rq_list;
#endif
#ifdef CONFIG_RT_GROUP_SCHED
	struct list_head leaf_rt_rq_list;
#endif

	/*
	 * This is part of a global counter where only the total sum
	 * over all CPUs matters. A task can increase this counter on
	 * one CPU and if it got migrated afterwards it may decrease
	 * it on another CPU. Always updated under the runqueue lock:
	 */
	unsigned long nr_uninterruptible;

	struct task_struct *curr, *idle;
	unsigned long next_balance;
	struct mm_struct *prev_mm;

	u64 clock;
	u64 clock_task;

	atomic_t nr_iowait;

#ifdef CONFIG_SMP
	struct root_domain *rd;
	struct sched_domain *sd;

	unsigned long cpu_power;

	unsigned char idle_at_tick;
	/* For active balancing */
	int post_schedule;
	int active_balance;
	int push_cpu;
	/* cpu of this runqueue: */
	int cpu;
	int online;

	unsigned long avg_load_per_task;

	struct task_struct *migration_thread;
	struct list_head migration_queue;

	u64 rt_avg;
	u64 age_stamp;
	u64 idle_stamp;
	u64 avg_idle;
#endif

#ifdef CONFIG_IRQ_TIME_ACCOUNTING
	u64 prev_irq_time;
#endif

	/* calc_load related fields */
	unsigned long calc_load_update;
	long calc_load_active;

#ifdef CONFIG_SCHED_HRTICK
#ifdef CONFIG_SMP
	int hrtick_csd_pending;
	struct call_single_data hrtick_csd;
#endif
	struct hrtimer hrtick_timer;
#endif

#ifdef CONFIG_SCHEDSTATS
	/* latency stats */
	struct sched_info rq_sched_info;
	unsigned long long rq_cpu_time;
	/* could above be rq->cfs_rq.exec_clock + rq->rt_rq.rt_runtime ? */

	/* sys_sched_yield() stats */
	unsigned int yld_count;

	/* schedule() stats */
	unsigned int sched_switch;
	unsigned int sched_count;
	unsigned int sched_switch;

	/* try_to_wake_up() stats */
	unsigned int ttwu_count;
	unsigned int ttwu_local;

	/* BKL stats */
	unsigned int bkl_count;
#endif
};
```

## 1.6.3　CPUごとのRUNキュー

> ただし、RUNキュー間で負荷状態に偏りが出たときは、RUNキュー間で実行待ちプロセスの移動を行いバランスを取ります（load_balance関数）。

 * runqueue の ロードバランシング load_balance
   * runqueue 上のプロセスが対象なので TASK_RUNNING な奴だけ
   * double_rq_lock, double_rq_unlock で二つの runqueue を同時にスピンロック
     * デッドロックを防ぐために runqueue のポインタのサイズを比較してアドレスの小さい方からスピンロックを取る
   * find_busiest_group
     * ドメイン単位?
   * find_busiest_queue
     * runqueue 単位
 * try_to_wak_up で idle なプロセッサを割り当てる

```c
/*
 * find_busiest_queue - find the busiest runqueue among the cpus in group.
 */
static runqueue_t *find_busiest_queue(struct sched_group *group,
	enum idle_type idle)
{
	unsigned long load, max_load = 0;
	runqueue_t *busiest = NULL;
	int i;

	for_each_cpu_mask(i, group->cpumask) {
        // ここで「負荷」を返す
		load = __source_load(i, 0, idle);

		if (load > max_load) {
			max_load = load;
			busiest = cpu_rq(i);
		}
	}

	return busiest;
}
``` 

__source_load

```c
/*
 * Return a low guess at the load of a migration-source cpu.
 *
 * We want to under-estimate the load of migration sources, to
 * balance conservatively.
 */
static inline unsigned long __source_load(int cpu, int type, enum idle_type idle)
{
	runqueue_t *rq = cpu_rq(cpu);

    // TASK_RUNNING なプロセス数
	unsigned long running = rq->nr_running;

    // ???
	unsigned long source_load, cpu_load = rq->cpu_load[type-1],

    // #define SCHED_LOAD_SCALE	128UL	/* increase resolution of load */
    // 現在の負荷。 SCHED_LOAD_SCALEは 解像度???
		load_now = running * SCHED_LOAD_SCALE;

	if (type == 0)
		source_load = load_now;
	else
		source_load = min(cpu_load, load_now);

	if (running > 1 || (idle == NOT_IDLE && running))
		/*
		 * If we are busy rebalancing the load is biased by
		 * priority to create 'nice' support across cpus. When
		 * idle rebalancing we should only bias the source_load if
		 * there is more than one task running on that queue to
		 * prevent idle rebalance from trying to pull tasks from a
		 * queue with only one running task.
		 */
         // runqueue の優先度 prio_bias を乗算
		source_load = source_load * rq->prio_bias / running;

	return source_load;
}
```

> また、プロセスの起床時（後述try_to_wake_up関数）にもアイドル状態のプロセッサにそのプロセスを割り付けることにより、負荷バランスを保つようになっています。

```c
/***
 * try_to_wake_up - wake up a thread
 * @p: the to-be-woken-up thread
 * @state: the mask of task states that can be woken
 * @sync: do a synchronous wakeup?
 *
 * Put it on the run-queue if it's not already there. The "current"
 * thread is always on the run-queue (except when the actual
 * re-schedule is in progress), and as such you're allowed to do
 * the simpler "current->state = TASK_RUNNING" to mark yourself
 * runnable without the overhead of this.
 *
 * returns failure only if the task is already active.
 */
static int try_to_wake_up(task_t *p, unsigned int state, int sync)
{
	int cpu, this_cpu, success = 0;
	unsigned long flags;
	long old_state;
	runqueue_t *rq;
#ifdef CONFIG_SMP
	unsigned long load, this_load;
	struct sched_domain *sd, *this_sd = NULL;
	int new_cpu;
#endif

    // 割り込み禁止 + スピンロッk
	rq = task_rq_lock(p, &flags);
	old_state = p->state;
	if (!(old_state & state))
		goto out;

    // ?
	if (p->array)
		goto out_running;

    // タスクの実行CPU を取る
    // task_thread_info(p)->cpu
    // task_thread_info の `__u32			cpu;		/* current CPU */` を指す
	cpu = task_cpu(p);
	this_cpu = smp_processor_id();

#ifdef CONFIG_SMP
    // task_running は runqueue->curr == p かどうかを見る
    // task が CPU上で実行中なので何もしない?
	if (unlikely(task_running(rq, p)))
		goto out_activate;

	new_cpu = cpu;

	schedstat_inc(rq, ttwu_cnt);
	if (cpu == this_cpu) {
		schedstat_inc(rq, ttwu_local);
		goto out_set_cpu;
	}

	for_each_domain(this_cpu, sd) {
		if (cpu_isset(cpu, sd->span)) {
			schedstat_inc(sd, ttwu_wake_remote);
			this_sd = sd;
			break;
		}
	}

	if (unlikely(!cpu_isset(this_cpu, p->cpus_allowed)))
		goto out_set_cpu;

	/*
	 * Check for affine wakeup and passive balancing possibilities.
	 */
	if (this_sd) {
		int idx = this_sd->wake_idx;
		unsigned int imbalance;

		imbalance = 100 + (this_sd->imbalance_pct - 100) / 2;

		load = source_load(cpu, idx);
		this_load = target_load(this_cpu, idx);

		new_cpu = this_cpu; /* Wake to this CPU if we can */

		if (this_sd->flags & SD_WAKE_AFFINE) {
			unsigned long tl = this_load;
			/*
			 * If sync wakeup then subtract the (maximum possible)
			 * effect of the currently running task from the load
			 * of the current CPU:
			 */
			if (sync)
				tl -= SCHED_LOAD_SCALE;

			if ((tl <= load &&
				tl + target_load(cpu, idx) <= SCHED_LOAD_SCALE) ||
				100*(tl + SCHED_LOAD_SCALE) <= imbalance*load) {
				/*
				 * This domain has SD_WAKE_AFFINE and
				 * p is cache cold in this domain, and
				 * there is no bad imbalance.
				 */
				schedstat_inc(this_sd, ttwu_move_affine);
				goto out_set_cpu;
			}
		}

		/*
		 * Start passive balancing when half the imbalance_pct
		 * limit is reached.
		 */
		if (this_sd->flags & SD_WAKE_BALANCE) {
			if (imbalance*this_load <= 100*load) {
				schedstat_inc(this_sd, ttwu_move_balance);
				goto out_set_cpu;
			}
		}
	}

	new_cpu = cpu; /* Could not wake to this_cpu. Wake to cpu instead */
out_set_cpu:
	new_cpu = wake_idle(new_cpu, p);
	if (new_cpu != cpu) {
		set_task_cpu(p, new_cpu);
		task_rq_unlock(rq, &flags);
		/* might preempt at this point */
		rq = task_rq_lock(p, &flags);
		old_state = p->state;
		if (!(old_state & state))
			goto out;
		if (p->array)
			goto out_running;

		this_cpu = smp_processor_id();
		cpu = task_cpu(p);
	}

out_activate:
#endif /* CONFIG_SMP */
	if (old_state == TASK_UNINTERRUPTIBLE) {
		rq->nr_uninterruptible--;
		/*
		 * Tasks on involuntary sleep don't earn
		 * sleep_avg beyond just interactive state.
		 */
		p->activated = -1;
	}

	/*
	 * Tasks that have marked their sleep as noninteractive get
	 * woken up without updating their sleep average. (i.e. their
	 * sleep is handled in a priority-neutral manner, no priority
	 * boost and no penalty.)
	 */
	if (old_state & TASK_NONINTERACTIVE)
		__activate_task(p, rq);
	else
		activate_task(p, rq, cpu == this_cpu);
	/*
	 * Sync wakeups (i.e. those types of wakeups where the waker
	 * has indicated that it will leave the CPU in short order)
	 * don't trigger a preemption, if the woken up task will run on
	 * this cpu. (in this case the 'I will reschedule' promise of
	 * the waker guarantees that the freshly woken up task is going
	 * to be considered on this CPU.)
	 */
	if (!sync || cpu != this_cpu) {
		if (TASK_PREEMPTS_CURR(p, rq))
			resched_task(rq->curr);
	}
	success = 1;

out_running:
	p->state = TASK_RUNNING;
out:
	task_rq_unlock(rq, &flags);

	return success;
}
```

## 1.6.4 アイドルプロセス

 * runqueue には登録されていない
 * runqueue->idle のことか?

## 1.6.5 カレントプロセス

![](http://sourceforge.jp/projects/linux-kernel-docs/wiki/1.6%E3%80%80プロセススケジューラの実装/thumb/310x154/fig1-10.png)

 * runqueue->curr
 * current
   * ESP の下位ビットをマスク -> thread_info を出す
   * thread_info -> task_struct

----

 * schedstat_inc
   * runqueue に統計情報のフィールドをインクリメント
