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
	unsigned int sched_goidle;

	/* try_to_wake_up() stats */
	unsigned int ttwu_count;
	unsigned int ttwu_local;

	/* BKL stats */
	unsigned int bkl_count;
#endif
};
```

## 1.6.3　CPUごとのRUNキュー

 * runqueue の ロードバランシング load_balance
   * runqueue 上のプロセスが対象なので TASK_RUNNING な奴だけ
 * try_to_wak_up で idle なプロセッサを割り当てる

## 1.6.4 アイドルプロセス

 * runqueue には登録されていない
 * runqueue->idle のことか?

## 1.6.5 カレントプロセス

![](http://sourceforge.jp/projects/linux-kernel-docs/wiki/1.6%E3%80%80プロセススケジューラの実装/thumb/310x154/fig1-10.png)

 * runqueue->curr
 * current
   * ESP の下位ビットをマスク -> thread_info を出す
   * thread_info -> task_struct
