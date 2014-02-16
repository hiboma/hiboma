## 1.5 プロセススケジューラ

 * 実行可能、待機状態の確認

## 1.5.1　スケジューリングの方針

 * 対話型プロセス
   * TASK_INTERACTIVE
 * 数値計算プロセス
   * バッチ型 の単語がいきなり出て来るぞ

## 1.5.1.1　対話型プロセスの応答性能向上

 * 対話型 > バッチ型

## 1.5.1.2　優先度の指標

 * 固定優先度
 * 変動優先度
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
   * ってどこで管理してるんだっけ?
     * task_struct に `unsigned int time_slice` がある。scheduler_tick でデクリメントされていく
   * 固定優先度を元にタイムスライスを割り当て
     * `static unsigned int task_timeslice(task_t *p)` の実装をみるとよい
 * scheduler_tick

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


## 1.5.1.4　カウンタ方式によるスループットの向上

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
