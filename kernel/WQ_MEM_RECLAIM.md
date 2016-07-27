# WQ_MEM_RECLAIM

## definition

https://www.kernel.org/doc/Documentation/workqueue.txt

```
* Do not forget to use WQ_MEM_RECLAIM if a wq may process work items
  which are used during memory reclaim.  Each wq with WQ_MEM_RECLAIM
  set has an execution context reserved for it.  If there is
  dependency among multiple work items used during memory reclaim,
  they should be queued to separate wq each with WQ_MEM_RECLAIM.
```

```
  WQ_MEM_RECLAIM

	All wq which might be used in the memory reclaim paths _MUST_
	have this flag set.  The wq is guaranteed to have at least one
	execution context regardless of memory pressure.
```

```
* A wq serves as a domain for forward progress guarantee
  (WQ_MEM_RECLAIM, flush and work item attributes.  Work items which
  are not involved in memory reclaim and don't need to be flushed as a
  part of a group of work items, and don't require any special
  attribute, can use one of the system wq.  There is no difference in
  execution characteristics between using a dedicated wq and a system
  wq.
```

```
Forward progress guarantee relies on that workers can be created when
more execution contexts are necessary, which in turn is guaranteed
through the use of rescue workers.  All work items which might be used
on code paths that handle memory reclaim are required to be queued on
wq's that have a rescue-worker reserved for execution under memory
pressure.  Else it is possible that the worker-pool deadlocks waiting
for execution contexts to free up.
```

## Where WQ_MEM_RECLAIM is used?

```c
struct workqueue_struct *__alloc_workqueue_key(const char *fmt,
					       unsigned int flags,
					       int max_active,
					       struct lock_class_key *key,
					       const char *lock_name, ...)
{
	size_t tbl_size = 0;
	va_list args;
	struct workqueue_struct *wq;
	struct pool_workqueue *pwq;

...

	/*
	 * Workqueues which may be used during memory reclaim should
	 * have a rescuer to guarantee forward progress.
	 */
	if (flags & WQ_MEM_RECLAIM) {
		struct worker *rescuer;

		rescuer = alloc_worker();
		if (!rescuer)
			goto err_destroy;

		rescuer->rescue_wq = wq;
		rescuer->task = kthread_create(rescuer_thread, rescuer, "%s",
					       wq->name);
		if (IS_ERR(rescuer->task)) {
			kfree(rescuer);
			goto err_destroy;
		}

        # set rescuer thread to workqueue_struct 
		wq->rescuer = rescuer;
		rescuer->task->flags |= PF_NO_SETAFFINITY;
		wake_up_process(rescuer->task);
	}
```

## What is rescuer_thread? How deadlock occur?

```
 * Regular work processing on a pool may block trying to create a new
 * worker which uses GFP_KERNEL allocation which has slight chance of
 * developing into deadlock if some works currently on the same queue
 * need to be processed to satisfy the GFP_KERNEL allocation.  This is
 * the problem rescuer solves.
```

```c
/**
 * rescuer_thread - the rescuer thread function
 * @__rescuer: self
 *
 * Workqueue rescuer thread function.  There's one rescuer for each
 * workqueue which has WQ_MEM_RECLAIM set.
 *
 * Regular work processing on a pool may block trying to create a new
 * worker which uses GFP_KERNEL allocation which has slight chance of
 * developing into deadlock if some works currently on the same queue
 * need to be processed to satisfy the GFP_KERNEL allocation.  This is
 * the problem rescuer solves.
 *
 * When such condition is possible, the pool summons rescuers of all
 * workqueues which have works queued on the pool and let them process
 * those works so that forward progress can be guaranteed.
 *
 * This should happen rarely.
 */
static int rescuer_thread(void *__rescuer)
{
	struct worker *rescuer = __rescuer;
	struct workqueue_struct *wq = rescuer->rescue_wq;
	struct list_head *scheduled = &rescuer->scheduled;

	set_user_nice(current, RESCUER_NICE_LEVEL);

	/*
	 * Mark rescuer as worker too.  As WORKER_PREP is never cleared, it
	 * doesn't participate in concurrency management.
	 */

    // #define PF_WQ_WORKER	0x00000020	/* I'm a workqueue worker */
	rescuer->task->flags |= PF_WQ_WORKER;
repeat:
	set_current_state(TASK_INTERRUPTIBLE);

	if (kthread_should_stop()) {
		__set_current_state(TASK_RUNNING);
		rescuer->task->flags &= ~PF_WQ_WORKER;
		return 0;
	}

	/* see whether any pwq is asking for help */
	spin_lock_irq(&wq_mayday_lock);

   // mayday => SOS
	while (!list_empty(&wq->maydays)) {
        // 救済したい workqueue のプール?
		struct pool_workqueue *pwq = list_first_entry(&wq->maydays,
					struct pool_workqueue, mayday_node);
		struct worker_pool *pool = pwq->pool;
		struct work_struct *work, *n;

		__set_current_state(TASK_RUNNING);
		list_del_init(&pwq->mayday_node);

		spin_unlock_irq(&wq_mayday_lock);

		/* migrate to the target cpu if possible */
		worker_maybe_bind_and_lock(pool);
		rescuer->pool = pool;

		/*
		 * Slurp in all works issued via this workqueue and
		 * process'em.
		 */
		WARN_ON_ONCE(!list_empty(&rescuer->scheduled));
		list_for_each_entry_safe(work, n, &pool->worklist, entry)
			if (get_work_pwq(work) == pwq)
				move_linked_works(work, scheduled, &n);

		process_scheduled_works(rescuer);

		/*
		 * Leave this pool.  If keep_working() is %true, notify a
		 * regular worker; otherwise, we end up with 0 concurrency
		 * and stalling the execution.
		 */
		if (keep_working(pool))
			wake_up_worker(pool);

		rescuer->pool = NULL;
		spin_unlock(&pool->lock);
		spin_lock(&wq_mayday_lock);
	}

	spin_unlock_irq(&wq_mayday_lock);

	/* rescuers should never participate in concurrency management */
	WARN_ON_ONCE(!(rescuer->flags & WORKER_NOT_RUNNING));
	schedule();
	goto repeat;
}
```

## How to rescue?

#### mayday

 * using `mod_timer`
 * `MAYDAY_INTERVAL		= HZ / 10,	/* and then every 100ms */`

```
static int init_worker_pool(struct worker_pool *pool)
{

...

	setup_timer(&pool->mayday_timer, pool_mayday_timeout,
		    (unsigned long)pool);
```

```c
static void pool_mayday_timeout(unsigned long __pool)
{
	struct worker_pool *pool = (void *)__pool;
	struct work_struct *work;

	spin_lock_irq(&wq_mayday_lock);		/* for wq->maydays */
	spin_lock(&pool->lock);

    // /* Do we need a new worker?  Called from manager. */
    // static bool need_to_create_worker(struct worker_pool *pool)
    // {
    // 	return need_more_worker(pool) && !may_start_working(pool);
    // }

	if (need_to_create_worker(pool)) {
		/*
		 * We've been trying to create a new worker but
		 * haven't been successful.  We might be hitting an
		 * allocation deadlock.  Send distress signals to
		 * rescuers.
		 */
		list_for_each_entry(work, &pool->worklist, entry)
			send_mayday(work);
	}

	spin_unlock(&pool->lock);
	spin_unlock_irq(&wq_mayday_lock);

	mod_timer(&pool->mayday_timer, jiffies + MAYDAY_INTERVAL);
}
```

 * `/* mayday mayday mayday */`

```c
static void send_mayday(struct work_struct *work)
{
	struct pool_workqueue *pwq = get_work_pwq(work);
	struct workqueue_struct *wq = pwq->wq;

	lockdep_assert_held(&wq_mayday_lock);

	if (!wq->rescuer)
		return;

	/* mayday mayday mayday */
	if (list_empty(&pwq->mayday_node)) {
		list_add_tail(&pwq->mayday_node, &wq->maydays);
		wake_up_process(wq->rescuer->task);
	}
}
```