## 1.7　事象の待ち合わせ

 * 実行可能状態
   * TASK_RUNNING
 * 待機状態
   * TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE

## 1.7.1 待機処理

 * ___待機の対象となる可能性のあるカーネルオブジェクト___
   * [wait_queue_head_t](https://github.com/hiboma/kernel_module_scratch/tree/master/wait_queue_head_t)

```c
struct __wait_queue_head {
	spinlock_t lock;
	struct list_head task_list;
};
typedef struct __wait_queue_head wait_queue_head_t;
```

**sleep_on**

```c
 void sleep_on(wait_queue_head_t *q)
 {
         // 下記三行は ソースでは SLEEP_ON_VAR マクロで定義されている
         // 2.6.32: sleep_on_common に書き直されている
         unsigned long flags;
         // この関数スコープで queue を実現できるので、スタックに確保されている
         wait_queue_t wait;
         init_waitqueue_entry(&wait, current); ――<51>

         // 2.6.32: __set_current_state に書き直されている
         current->state = TASK_UNINTERRUPTIBLE; ――<52>
         spin_lock_irqsave(&q->lock,flags);
         // ただのリスト操作
         __add_wait_queue(q, &wait); ――<53>
         spin_unlock(&q->lock);

         // TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE なら deactivate_task で
         // runqueue から外される
         schedule(); ――<54>

         spin_lock_irq(&q->lock);
         __remove_wait_queue(q, &wait); ――<55>
         spin_unlock_irqrestore(&q->lock, flags);
 }
```

## 1.7.2 起床処理

> もし起床させたプロセスのほうが、現在実行中のプロセスより実行優先度が高かった場合、プロセススケジューラに対してプリエンプト要求も送ります。

 * wake_up_*_sync 群はプリエンプトしない (実行中のプロセスが継続される)
 * try_to_wake_up で プリエンプトするか否かを決定する

 ```c
// try_to_wake_up

	/*
	 * Sync wakeups (i.e. those types of wakeups where the waker
	 * has indicated that it will leave the CPU in short order)
	 * don't trigger a preemption, if the woken up task will run on
	 * this cpu. (in this case the 'I will reschedule' promise of
	 * the waker guarantees that the freshly woken up task is going
	 * to be considered on this CPU.)
	 */
    // 1. sync が立ってなければプリエンプションする
    // 2. 別のCPU ならプリエンプションする
	if (!sync || cpu != this_cpu) {
       // ((p)->prio < (rq)->curr->prio) 優先度の比較
		if (TASK_PREEMPTS_CURR(p, rq))
            // TIF_NEED_RESCHED を立てる
			resched_task(rq->curr);
	}
```

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

	rq = task_rq_lock(p, &flags);
	old_state = p->state;
    // ???
	if (!(old_state & state))
		goto out;

    // 優先度??
	if (p->array)
		goto out_running;

	cpu = task_cpu(p);
	this_cpu = smp_processor_id();

#ifdef CONFIG_SMP
    // rq で p が TASK_RUNNING でCPU使ってる場合は out_activate
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

int fastcall wake_up_process(task_t *p)
{
	return try_to_wake_up(p, TASK_STOPPED | TASK_TRACED |
				 TASK_INTERRUPTIBLE | TASK_UNINTERRUPTIBLE, 0);
}

EXPORT_SYMBOL(wake_up_process);
```

## 1.7.4　子プロセスのスケジューリング

>forkシステムコールによって子プロセスが生成されたときは、この子プロセスを実行状態としてスケジューリング対象に加えます（wake_up_forked_process関数）

バニラカーネルにはそんな関数ないぞう

> 子プロセスの実行優先度は親プロセスから引き継ぎ*2、親プロセスと同じRUNキューの親プロセスの前に挿入し、プリエンプト要求を発生させます（set_need_resched関数）。

```c
// http://www.tsri.com/jeneral/kernel/kernel/sched.c/pm/PM-WAKE_UP_FORKED_PROCESS.html
/*
 * wake_up_forked_process - wake up a freshly forked process.
 *
 * This function will do some initial scheduler statistics housekeeping
 * that must be done for every newly created process.
 */
void wake_up_forked_process(task_t * p)
{
	unsigned long flags;
	runqueue_t *rq = task_rq_lock(current, &flags);

	BUG_ON(p->state != TASK_RUNNING);

	/*
	 * We decrease the sleep average of forking parents
	 * and children as well, to keep max-interactive tasks
	 * from forking tasks that are max-interactive.
	 */
	current->sleep_avg = JIFFIES_TO_NS(CURRENT_BONUS(current) *
		PARENT_PENALTY / 100 * MAX_SLEEP_AVG / MAX_BONUS);

	p->sleep_avg = JIFFIES_TO_NS(CURRENT_BONUS(p) *
		CHILD_PENALTY / 100 * MAX_SLEEP_AVG / MAX_BONUS);

	p->interactive_credit = 0;

    // 優先度を引き継ぐ
	p->prio = effective_prio(p);
	set_task_cpu(p, smp_processor_id());

	if (unlikely(!current->array))
		__activate_task(p, rq);
	else {
		p->prio = current->prio;
        // ???親プロセスの前 ???
		list_add_tail(&p->run_list, &current->run_list);
        // 優先度キューも引き継ぐ
		p->array = current->array;
		p->array->nr_active++;
		nr_running_inc(rq);
	}
	task_rq_unlock(rq, &flags);
}
```

> また子プロセスを生成したとき、親プロセスは実行割り当て時間の半分を子プロセスに譲るようになっています。

do_fork -> sched_fork の中にコードがある

```c
/*
 * Perform scheduler related setup for a newly forked process p.
 * p is forked by current.
 */
void fastcall sched_fork(task_t *p, int clone_flags)

// ...

	/*
	 * Share the timeslice between parent and child, thus the
	 * total amount of pending timeslices in the system doesn't change,
	 * resulting in more scheduling fairness.
	 */
	local_irq_disable();
    // p が子プロセス current が親
    // 親プロセスのタイムスライスの半分( >> 1 ) を割り当て
    // システム全体でのタイムスライスの総量は変わらない
	p->time_slice = (current->time_slice + 1) >> 1;
	/*
	 * The remainder of the first timeslice might be recovered by
	 * the parent if the child exits early enough.
	 */
    // ???
	p->first_time_slice = 1;

    // 親のタイムスライスを半分
	current->time_slice >>= 1;
	p->timestamp = sched_clock();
	if (unlikely(!current->time_slice)) {
		/*
		 * This case is rare, it happens when the parent has only
		 * a single jiffy left from its timeslice. Taking the
		 * runqueue lock is not a problem.
		 */
		current->time_slice = 1;
		scheduler_tick();
	}
	local_irq_enable();
	put_cpu();
```