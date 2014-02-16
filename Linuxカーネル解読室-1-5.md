
## TODO

 * タイマ割り込みから scheduler_tick までのパスは?
   * ???
   * smp_apic_timer_interrupt
      * I/O APIC での割り込み
   * smp_local_timer_interrupt
      * APIC から割り込みがリダイレクションして Local APIC に転送
   * update_process_times
   * scheduler_tick 
 * CPUキャッシュの整理

## 1.5 プロセススケジューラ

 * 実行可能、待機状態の確認

## 1.5.1　スケジューリングの方針

 * 対話型プロセス
   * TASK_INTERACTIVE(p) で判別される
 * 数値計算プロセス
   * バッチ型 の単語がいきなり出て来るぞ
   * CPUバウンドなプロセス

## 1.5.1.1　対話型プロセスの応答性能向上

 * 対話型 > バッチ型

## 1.5.1.2　優先度の指標

 * 固定優先度
   * task_struct の `int static_privo`
 * 変動優先度
   * task_struct の `int prio`
   * リアルタイムプロセスは変動優先度が max
 * ___preempt___ , ___preemption___
   * preempt_disable, preempt_enable
   * __Nonpreemptive multitasking___ , __Preemptive multitasking__
     * Windows3.1, Mac OS
 * 優先度による preempt
   * プロセススケジューラが優先度を元に切り替えるプロセスを判定 -> プロセスディスパッチャで切り替え

## 1.5.1.3　実行保証

 * 時分割 タイムシェアリング
 * タイムスライス
     * task_struct の `unsigned int time_slice` のこと
     * scheduler_tick でデクリメントされていく
   * 固定優先度を元にタイムスライスを割り当て
     * タイムスライスの割り当ては `static unsigned int task_timeslice(task_t *p)` の実装をみるとよい

** task_timeslice **

タイムスライスを優先度から計算して返す

```
/*
 * task_timeslice() scales user-nice values [ -20 ... 0 ... 19 ]
 * to time slice values: [800ms ... 100ms ... 5ms]
 *
 * The higher a thread's priority, the bigger timeslices
 * it gets during one round of execution. But even the lowest
 * priority thread gets MIN_TIMESLICE worth of execution time.
 */

 // x * (優先度の最大値から prio を引いた数値) * / (ユーザ優先度を2で割る)
 // 最低でも MIN_TIMESLICE は割り当てられる
#define SCALE_PRIO(x, prio) \
	max(x * (MAX_PRIO - prio) / (MAX_USER_PRIO/2), MIN_TIMESLICE)

 // nice を 優先度に変換
#define NICE_TO_PRIO(nice)	(MAX_RT_PRIO + (nice) + 20)

// p->static_prio の数値が低い方がタイムスライスがいっぱいもらえる
static unsigned int task_timeslice(task_t *p)
{
	if (p->static_prio < NICE_TO_PRIO(0))
		return SCALE_PRIO(DEF_TIMESLICE*4, p->static_prio);
	else
		return SCALE_PRIO(DEF_TIMESLICE, p->static_prio);
}
```

** scheduler_tick **

```c
/*
 * This function gets called by the timer code, with HZ frequency.
 * We call it with interrupts disabled.
 *
 * It also gets called by the fork code, when changing the parent's
 * timeslices.
 */
void scheduler_tick(void)
{
    // CPU ID
    int cpu = smp_processor_id();
    // CPUごとの runqueue
	runqueue_t *rq = this_rq();
	task_t *p = current;
    
    // rdtsc (Read Time Stamp Counter) 命令で CPU のタイムスタンプカウンタから時刻を取る
    // http://www.02.246.ne.jp/~torutk/cxx/clock/cpucounter.html
	unsigned long long now = sched_clock();

    // p->sched_time に前回からの scheduler_tick の時間を入れとく
	update_cpu_clock(p, rq, now);

	rq->timestamp_last_tick = now;

    // idleプロセス?
	if (p == rq->idle) {
		if (wake_priority_sleeper(rq))
			goto out;
        // CPU間のロードバランス
		rebalance_tick(cpu, rq, SCHED_IDLE);
		return;
	}

	/* Task might have expired already, but not scheduled off yet */
	if (p->array != rq->active) {
		set_tsk_need_resched(p);
		goto out;
	}
	spin_lock(&rq->lock);

	/*
	 * The task was running during this tick - update the
	 * time slice counter. Note: we do not update a thread's
	 * priority until it either goes to sleep or uses up its
	 * timeslice. This makes it possible for interactive tasks
	 * to use up their timeslices at their highest priority levels.
	 */
    // リアルタイムプロセスの場合
    // (p)->prio < MAX_RT_PRIO で判別する
	if (rt_task(p)) {
		/*
		 * RR tasks need a special form of timeslice management.
		 * FIFO tasks have no timeslices.
		 */
		if ((p->policy == SCHED_RR) && !--p->time_slice) {
			p->time_slice = task_timeslice(p);
			p->first_time_slice = 0;
			set_tsk_need_resched(p);

			/* put it at the end of the queue: */
			requeue_task(p, rq->active);
		}
		goto out_unlock;
	}

    // 通常のタスクの場合
    // タイムスライスをデクリメントする
	if (!--p->time_slice) {
        // タイムスライスが 0 = 使い切った場合
        // タスクを runqueue から dequeue 
		dequeue_task(p, rq->active);
        // 再スケジューリングが必要であるフラグをたてる
        // thread_info に TIF_NEED_RESCHED をセット
		set_tsk_need_resched(p);
		p->prio = effective_prio(p);

        // タイムスライスの割り当て
		p->time_slice = task_timeslice(p);
        // これ?
		p->first_time_slice = 0;

		if (!rq->expired_timestamp)
			rq->expired_timestamp = jiffies;
		if (!TASK_INTERACTIVE(p) || EXPIRED_STARVING(rq)) {
			enqueue_task(p, rq->expired);
			if (p->static_prio < rq->best_expired_prio)
				rq->best_expired_prio = p->static_prio;
		} else
			enqueue_task(p, rq->active);
	} else {
		/*
		 * Prevent a too long timeslice allowing a task to monopolize
		 * the CPU. We do this by splitting up the timeslice into
		 * smaller pieces.
		 *
		 * Note: this does not mean the task's timeslices expire or
		 * get lost in any way, they just might be preempted by
		 * another task of equal priority. (one with higher
		 * priority would have preempted this task already.) We
		 * requeue this task to the end of the list on this priority
		 * level, which is in essence a round-robin of tasks with
		 * equal priority.
		 *
		 * This only applies to tasks in the interactive
		 * delta range with at least TIMESLICE_GRANULARITY to requeue.
		 */
		if (TASK_INTERACTIVE(p) && !((task_timeslice(p) -
			p->time_slice) % TIMESLICE_GRANULARITY(p)) &&
			(p->time_slice >= TIMESLICE_GRANULARITY(p)) &&
			(p->array == rq->active)) {

			requeue_task(p, rq->active);
			set_tsk_need_resched(p);
		}
	}
out_unlock:
	spin_unlock(&rq->lock);
out:
	rebalance_tick(cpu, rq, NOT_IDLE);
}
```

## 1.5.1.4　:カウンタ方式によるスループットの向上

 * 古典UNIXだとスケジューリングが頻繁に行われて効率が悪かった?
 * ___カウンタ方式___ は何?
 
## 1.5.2　スケジューリング契機

プロセススケジューラが動作するのはいつ?

 * 自ら実行権を手放す場合
   * 1. 事象が成立するために待機状態に遷移
     * TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE
     * I/O, ネットワーク, ロック, sleep 
   * 2. 明示的に他のプロセスに実行権をゆずる
     * カーネルの実行パスが長い場合
     * fork とか?
     * sched_yield ?
 * 実行中プロセスから実行権を奪い取る(プリエンプションする)場合
   * resched_task
   * システムコール、割り込みまで遅延
 * カーネル内プリエンプション
   * 割り込み、遅延処理(taskletとか?), 排他区間以外
   * CONFIG_PREEMPT=y 
   * http://wiki.bit-hive.com/linuxkernelmemo/pg/%A5%D7%A5%EA%A5%A8%A5%F3%A5%D7%A5%B7%A5%E7%A5%F3

## 1.5.4　マルチプロセッサシステムにおけるプロセススケジューリング

 * ___対称型マルチプロセッサ___
   * マスタ/スレーブ構成
 * プロセスのマイグレーション
 * CPUのキャッシュがあるのでプロセスを同じCPUで固定で実行した方がいいケースがある
   * L1, L2, L3
   * TLB
 * プロセススケジューラは CPU上で独立して動作している
 * CPU アフィニティ
   * sched_setaffinity
   * task_struct の cpuset
 * rebalance_tick で ロードバランシング
   * 2.6.32 だと scheduler_tick -> trigger_load_balance でCPU間でロードバランシングされる

## 1.5.4.1　ハイパースレッディング

 * メモリアクセスで遅延、ストールする
 * レジスタセットを2組持つ
   * 片方のレジスタセットがストールしている間に、別のレジスタセットで命令コードの実行
 * OSからは仮想的なCPUとして見える

## 1.5.4.2　NUMA

2.6.15 だと`#ifdef CONFIG_NUMA` で囲われた部分

* Non-Uniformed Memory Architecture
   * 反対は UMA
 * ノード
   * > ノード間を超えてのプロセス移動はできません。実行性能の劣化が大きいためです。
   * ノード間でのメモリコピーが必要だから?
 * MySQL, OOM killer, numactl
 * exec の際にロードバランシングする
   * 負荷の低いノードはどうやって判定されている?
   * 最近の話 http://gihyo.jp/dev/serial/01/linuxcon_basic/0005
   * sched_domain http://www.kerneldesign.info/wiki/index.php?sched_domain%2Flinux2.6

----

## rebalance_tick

```c
/*
 * rebalance_tick will get called every timer tick, on every CPU.
 *
 * It checks each scheduling domain to see if it is due to be balanced,
 * and initiates a balancing operation if so.
 *
 * Balancing parameters are set up in arch_init_sched_domains.
 */

/* Don't have all balancing operations going off at once */
#define CPU_OFFSET(cpu) (HZ * cpu / NR_CPUS)

static void rebalance_tick(int this_cpu, runqueue_t *this_rq,
			   enum idle_type idle)
{
	unsigned long old_load, this_load;
	unsigned long j = jiffies + CPU_OFFSET(this_cpu);
	struct sched_domain *sd;
	int i;

	this_load = this_rq->nr_running * SCHED_LOAD_SCALE;
	/* Update our load */
	for (i = 0; i < 3; i++) {
		unsigned long new_load = this_load;
		int scale = 1 << i;
		old_load = this_rq->cpu_load[i];
		/*
		 * Round up the averaging division if load is increasing. This
		 * prevents us from getting stuck on 9 if the load is 10, for
		 * example.
		 */
		if (new_load > old_load)
			new_load += scale-1;
		this_rq->cpu_load[i] = (old_load*(scale-1) + new_load) / scale;
	}
    
    for_each_domain(this_cpu, sd) {
		unsigned long interval;

		if (!(sd->flags & SD_LOAD_BALANCE))
			continue;

		interval = sd->balance_interval;
		if (idle != SCHED_IDLE)
			interval *= sd->busy_factor;

		/* scale ms to jiffies */
		interval = msecs_to_jiffies(interval);
		if (unlikely(!interval))
			interval = 1;

		if (j - sd->last_balance >= interval) {
			if (load_balance(this_cpu, this_rq, sd, idle)) {
				/*
				 * We've pulled tasks over so either we're no
				 * longer idle, or one of our SMT siblings is
				 * not idle.
				 */
				idle = NOT_IDLE;
			}
			sd->last_balance += interval;
		}
	}
}
```

```c
/*
 * Check this_cpu to ensure it is balanced within domain. Attempt to move
 * tasks if there is an imbalance.
 *
 * Called with this_rq unlocked.
 */
static int load_balance(int this_cpu, runqueue_t *this_rq,
			struct sched_domain *sd, enum idle_type idle)
{
	struct sched_group *group;
	runqueue_t *busiest;
	unsigned long imbalance;
	int nr_moved, all_pinned = 0;
	int active_balance = 0;
	int sd_idle = 0;

	if (idle != NOT_IDLE && sd->flags & SD_SHARE_CPUPOWER)
		sd_idle = 1;

	schedstat_inc(sd, lb_cnt[idle]);

	group = find_busiest_group(sd, this_cpu, &imbalance, idle, &sd_idle);
	if (!group) {
		schedstat_inc(sd, lb_nobusyg[idle]);
		goto out_balanced;
	}

	busiest = find_busiest_queue(group, idle);
	if (!busiest) {
		schedstat_inc(sd, lb_nobusyq[idle]);
		goto out_balanced;
	}

	BUG_ON(busiest == this_rq);

	schedstat_add(sd, lb_imbalance[idle], imbalance);

	nr_moved = 0;
	if (busiest->nr_running > 1) {
		/*
		 * Attempt to move tasks. If find_busiest_group has found
		 * an imbalance but busiest->nr_running <= 1, the group is
		 * still unbalanced. nr_moved simply stays zero, so it is
		 * correctly treated as an imbalance.
		 */
		double_rq_lock(this_rq, busiest);
		nr_moved = move_tasks(this_rq, this_cpu, busiest,
					imbalance, sd, idle, &all_pinned);
		double_rq_unlock(this_rq, busiest);

		/* All tasks on this runqueue were pinned by CPU affinity */
		if (unlikely(all_pinned))
			goto out_balanced;
	}

	if (!nr_moved) {
		schedstat_inc(sd, lb_failed[idle]);
		sd->nr_balance_failed++;

		if (unlikely(sd->nr_balance_failed > sd->cache_nice_tries+2)) {

			spin_lock(&busiest->lock);

			/* don't kick the migration_thread, if the curr
			 * task on busiest cpu can't be moved to this_cpu
			 */
			if (!cpu_isset(this_cpu, busiest->curr->cpus_allowed)) {
				spin_unlock(&busiest->lock);
				all_pinned = 1;
				goto out_one_pinned;
			}

			if (!busiest->active_balance) {
				busiest->active_balance = 1;
				busiest->push_cpu = this_cpu;
				active_balance = 1;
			}
			spin_unlock(&busiest->lock);
			if (active_balance)
				wake_up_process(busiest->migration_thread);

			/*
			 * We've kicked active balancing, reset the failure
			 * counter.
			 */
			sd->nr_balance_failed = sd->cache_nice_tries+1;
		}
	} else
		sd->nr_balance_failed = 0;

	if (likely(!active_balance)) {
		/* We were unbalanced, so reset the balancing interval */
		sd->balance_interval = sd->min_interval;
	} else {
		/*
		 * If we've begun active balancing, start to back off. This
		 * case may not be covered by the all_pinned logic if there
		 * is only 1 task on the busy runqueue (because we don't call
		 * move_tasks).
		 */
		if (sd->balance_interval < sd->max_interval)
			sd->balance_interval *= 2;
	}

	if (!nr_moved && !sd_idle && sd->flags & SD_SHARE_CPUPOWER)
		return -1;
	return nr_moved;

out_balanced:
	schedstat_inc(sd, lb_balanced[idle]);

	sd->nr_balance_failed = 0;

out_one_pinned:
	/* tune up the balancing interval */
	if ((all_pinned && sd->balance_interval < MAX_PINNED_INTERVAL) ||
			(sd->balance_interval < sd->max_interval))
		sd->balance_interval *= 2;

	if (!sd_idle && sd->flags & SD_SHARE_CPUPOWER)
		return -1;
	return 0;
}
```
