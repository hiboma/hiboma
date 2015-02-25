# futex(2)

合わせて読みたい http://www.akkadia.org/drepper/futex.pdf

## ソース

インタフェースはこんなん

```
SYSCALL_DEFINE6(futex, u32 __user *, uaddr, int, op, u32, val,
		struct timespec __user *, utime, u32 __user *, uaddr2,
		u32, val3)
{
	struct timespec ts;
	ktime_t t, *tp = NULL;
	u32 val2 = 0;
	int cmd = op & FUTEX_CMD_MASK;

	if (utime && (cmd == FUTEX_WAIT || cmd == FUTEX_LOCK_PI ||
		      cmd == FUTEX_WAIT_BITSET ||
		      cmd == FUTEX_WAIT_REQUEUE_PI)) {
		if (copy_from_user(&ts, utime, sizeof(ts)) != 0)
			return -EFAULT;
		if (!timespec_valid(&ts))
			return -EINVAL;

		t = timespec_to_ktime(ts);
		if (cmd == FUTEX_WAIT)
			t = ktime_add_safe(ktime_get(), t);
		tp = &t;
	}
	/*
	 * requeue parameter in 'utime' if cmd == FUTEX_*_REQUEUE_*.
	 * number of waiters to wake in 'utime' if cmd == FUTEX_WAKE_OP.
	 */
	if (cmd == FUTEX_REQUEUE || cmd == FUTEX_CMP_REQUEUE ||
	    cmd == FUTEX_CMP_REQUEUE_PI || cmd == FUTEX_WAKE_OP)
		val2 = (u32) (unsigned long) utime;

	return do_futex(uaddr, op, val, tp, uaddr2, val2, val3);
}
```

do_futex で、cmd に応じてディスパッチする

```c
long do_futex(u32 __user *uaddr, int op, u32 val, ktime_t *timeout,
		u32 __user *uaddr2, u32 val2, u32 val3)
{
	int clockrt, ret = -ENOSYS;
	int cmd = op & FUTEX_CMD_MASK;
	int fshared = 0;

    // プロセス間で共有するか否か
	if (!(op & FUTEX_PRIVATE_FLAG))
		fshared = 1;

	clockrt = op & FUTEX_CLOCK_REALTIME;
	if (clockrt && cmd != FUTEX_WAIT_BITSET && cmd != FUTEX_WAIT_REQUEUE_PI)
		return -ENOSYS;

	switch (cmd) {
	case FUTEX_WAIT:
		val3 = FUTEX_BITSET_MATCH_ANY;
	case FUTEX_WAIT_BITSET:
		ret = futex_wait(uaddr, fshared, val, timeout, val3, clockrt);
		break;
	case FUTEX_WAKE:
		val3 = FUTEX_BITSET_MATCH_ANY;
	case FUTEX_WAKE_BITSET:
		ret = futex_wake(uaddr, fshared, val, val3);
		break;
	case FUTEX_REQUEUE:
		ret = futex_requeue(uaddr, fshared, uaddr2, val, val2, NULL, 0);
		break;
	case FUTEX_CMP_REQUEUE:
		ret = futex_requeue(uaddr, fshared, uaddr2, val, val2, &val3,
				    0);
		break;
	case FUTEX_WAKE_OP:
		ret = futex_wake_op(uaddr, fshared, uaddr2, val, val2, val3);
		break;
	case FUTEX_LOCK_PI:
		if (futex_cmpxchg_enabled)
			ret = futex_lock_pi(uaddr, fshared, val, timeout, 0);
		break;
	case FUTEX_UNLOCK_PI:
		if (futex_cmpxchg_enabled)
			ret = futex_unlock_pi(uaddr, fshared);
		break;
	case FUTEX_TRYLOCK_PI:
		if (futex_cmpxchg_enabled)
			ret = futex_lock_pi(uaddr, fshared, 0, timeout, 1);
		break;
	case FUTEX_WAIT_REQUEUE_PI:
		val3 = FUTEX_BITSET_MATCH_ANY;
		ret = futex_wait_requeue_pi(uaddr, fshared, val, timeout, val3,
					    clockrt, uaddr2);
		break;
	case FUTEX_CMP_REQUEUE_PI:
		ret = futex_requeue(uaddr, fshared, uaddr2, val, val2, &val3,
				    1);
		break;
	default:
		ret = -ENOSYS;
	}
	return ret;
```

## FUTEX_WAIT

下記のような構造を追っていく

```
futex_wait
  futex_wait_setup
    get_futex_key
      futex のキーを保持するページをあれこれするぽい
  futex_wait_queue_me
    queue_me
      current をキューに繋ぐ
    schedule()
      TASK_INTERRUPTIBLE / TASK_RUNNING
  unqueue_me
```

#### futex_wait

```c
	switch (cmd) {
	case FUTEX_WAIT:
		val3 = FUTEX_BITSET_MATCH_ANY;
	case FUTEX_WAIT_BITSET:
		ret = futex_wait(uaddr, fshared, val, timeout, val3, clockrt);
		break;
```

```c
static int futex_wait(u32 __user *uaddr, int fshared,
		      u32 val, ktime_t *abs_time, u32 bitset, int clockrt)
{
	struct hrtimer_sleeper timeout, *to = NULL;
	struct restart_block *restart;
	struct futex_hash_bucket *hb;

    // /**
    //  * struct futex_q - The hashed futex queue entry, one per waiting task
    //  * @task:		the task waiting on the futex
    //  * @lock_ptr:		the hash bucket lock
    //  * @key:		the key the futex is hashed on
    //  * @pi_state:		optional priority inheritance state
    //  * @rt_waiter:		rt_waiter storage for use with requeue_pi
    //  * @requeue_pi_key:	the requeue_pi target futex key
    //  * @bitset:		bitset for the optional bitmasked wakeup
    //  *
    struct futex_q q;
	int ret;

	if (!bitset)
		return -EINVAL;

	q.pi_state = NULL;
	q.bitset = bitset;
	q.rt_waiter = NULL;
	q.requeue_pi_key = NULL;

     // タイムアウトを指定する場合は、ここでタイムアウト時間を計算するぽい
	if (abs_time) {
		to = &timeout;

		hrtimer_init_on_stack(&to->timer, clockrt ? CLOCK_REALTIME :
				      CLOCK_MONOTONIC, HRTIMER_MODE_ABS);
		hrtimer_init_sleeper(to, current);
		hrtimer_set_expires_range_ns(&to->timer, *abs_time,
					     current->timer_slack_ns);
	}

retry:
	/*
	 * Prepare to wait on uaddr. On success, holds hb lock and increments
	 * q.key refs.
	 */
	ret = futex_wait_setup(uaddr, val, fshared, &q, &hb);
	if (ret)
		goto out;

	/* queue_me and wait for wakeup, timeout, or a signal. */
	futex_wait_queue_me(hb, &q, to);

	/* If we were woken (and unqueued), we succeeded, whatever. */
	ret = 0;
	/* unqueue_me() drops q.key ref */
	if (!unqueue_me(&q))
		goto out;
	ret = -ETIMEDOUT;
	if (to && !to->task)
		goto out;

	/*
	 * We expect signal_pending(current), but we might be the
	 * victim of a spurious wakeup as well.
	 */
	if (!signal_pending(current))
		goto retry;

	ret = -ERESTARTSYS;
	if (!abs_time)
		goto out;

    // シグナルを受けてシステムコールを再開するとき用に、パラメータを保持しておくのかな
	restart = &current_thread_info()->restart_block;
	restart->fn = futex_wait_restart;
	restart->futex.uaddr = (u32 *)uaddr;
	restart->futex.val = val;
	restart->futex.time = abs_time->tv64;
	restart->futex.bitset = bitset;
	restart->futex.flags = FLAGS_HAS_TIMEOUT;

	if (fshared)
		restart->futex.flags |= FLAGS_SHARED;
	if (clockrt)
		restart->futex.flags |= FLAGS_CLOCKRT;

	ret = -ERESTART_RESTARTBLOCK;

out:
	if (to) {
		hrtimer_cancel(&to->timer);
		destroy_hrtimer_on_stack(&to->timer);
	}
	return ret;
}
```

#### futex_wait_queue_me

 * TASK_INTERRUPTIBLE でキューに入る
 * queue_me が、キュー構造の操作
 * タイムアウトが指定された場合は、タイムアウトの時刻を hrtimer_start_expires とやらで計算する

```c
/**
 * futex_wait_queue_me() - queue_me() and wait for wakeup, timeout, or signal
 * @hb:		the futex hash bucket, must be locked by the caller
 * @q:		the futex_q to queue up on
 * @timeout:	the prepared hrtimer_sleeper, or null for no timeout
 */
static void futex_wait_queue_me(struct futex_hash_bucket *hb, struct futex_q *q,
				struct hrtimer_sleeper *timeout)
{
	/*
	 * The task state is guaranteed to be set before another task can
	 * wake it. set_current_state() is implemented using set_mb() and
	 * queue_me() calls spin_unlock() upon completion, both serializing
	 * access to the hash list and forcing another memory barrier.
	 */
	set_current_state(TASK_INTERRUPTIBLE);

    // ここで futex_q のキューに繋ぐ
	queue_me(q, hb);

	/* Arm the timer */
	if (timeout) {
		hrtimer_start_expires(&timeout->timer, HRTIMER_MODE_ABS);
		if (!hrtimer_active(&timeout->timer))
			timeout->task = NULL;
	}

	/*
	 * If we have been removed from the hash list, then another task
	 * has tried to wake us, and we can skip the call to schedule().
	 */
	if (likely(!plist_node_empty(&q->list))) {
		/*
		 * If the timer has already expired, current will already be
		 * flagged for rescheduling. Only call schedule if there
		 * is no timeout, or if it has yet to expire.
		 */
		if (!timeout || timeout->task)
			schedule();
	}
	__set_current_state(TASK_RUNNING);
}
```

#### queue_me

 * リアルタイムプロセスの場合は、優先度順に起床される仕組みになっている
   * PDF に書いてある記述と違うな
 * 他は FIFO 

```c
/**
 * queue_me() - Enqueue the futex_q on the futex_hash_bucket
 * @q:	The futex_q to enqueue
 * @hb:	The destination hash bucket
 *
 * The hb->lock must be held by the caller, and is released here. A call to
 * queue_me() is typically paired with exactly one call to unqueue_me().  The
 * exceptions involve the PI related operations, which may use unqueue_me_pi()
 * or nothing if the unqueue is done as part of the wake process and the unqueue
 * state is implicit in the state of woken task (see futex_wait_requeue_pi() for
 * an example).
 */
static inline void queue_me(struct futex_q *q, struct futex_hash_bucket *hb)
{
	int prio;

	/*
	 * The priority used to register this element is
	 * - either the real thread-priority for the real-time threads
	 * (i.e. threads with a priority lower than MAX_RT_PRIO)
	 * - or MAX_RT_PRIO for non-RT threads.
	 * Thus, all RT-threads are woken first in priority order, and
	 * the others are woken last, in FIFO order.
	 */
	prio = min(current->normal_prio, MAX_RT_PRIO);

	plist_node_init(&q->list, prio);
	plist_add(&q->list, &hb->chain);
	q->task = current;
	spin_unlock(&hb->lock);
}
```

#### futex_wait_setup

 * get_futex_key がじゅうよう

```
/**
 * futex_wait_setup() - Prepare to wait on a futex
 * @uaddr:	the futex userspace address
 * @val:	the expected value
 * @fshared:	whether the futex is shared (1) or not (0)
 * @q:		the associated futex_q
 * @hb:		storage for hash_bucket pointer to be returned to caller
 *
 * Setup the futex_q and locate the hash_bucket.  Get the futex value and
 * compare it with the expected value.  Handle atomic faults internally.
 * Return with the hb lock held and a q.key reference on success, and unlocked
 * with no q.key reference on failure.
 *
 * Returns:
 *  0 - uaddr contains val and hb has been locked
 * <1 - -EFAULT or -EWOULDBLOCK (uaddr does not contain val) and hb is unlcoked
 */
static int futex_wait_setup(u32 __user *uaddr, u32 val, int fshared,
			   struct futex_q *q, struct futex_hash_bucket **hb)
{
	u32 uval;
	int ret;

	/*
	 * Access the page AFTER the hash-bucket is locked.
	 * Order is important:
	 *
	 *   Userspace waiter: val = var; if (cond(val)) futex_wait(&var, val);
	 *   Userspace waker:  if (cond(var)) { var = new; futex_wake(&var); }
	 *
	 * The basic logical guarantee of a futex is that it blocks ONLY
	 * if cond(var) is known to be true at the time of blocking, for
	 * any cond.  If we queued after testing *uaddr, that would open
	 * a race condition where we could block indefinitely with
	 * cond(var) false, which would violate the guarantee.
	 *
	 * A consequence is that futex_wait() can return zero and absorb
	 * a wakeup when *uaddr != val on entry to the syscall.  This is
	 * rare, but normal.
	 */
retry:
	q->key = FUTEX_KEY_INIT;
	ret = get_futex_key(uaddr, fshared, &q->key, VERIFY_READ);
	if (unlikely(ret != 0))
		return ret;

retry_private:
	*hb = queue_lock(q);

	ret = get_futex_value_locked(&uval, uaddr);

	if (ret) {
		queue_unlock(q, *hb);

		ret = get_user(uval, uaddr);
		if (ret)
			goto out;

		if (!fshared)
			goto retry_private;

		put_futex_key(fshared, &q->key);
		goto retry;
	}

	if (uval != val) {
		queue_unlock(q, *hb);
		ret = -EWOULDBLOCK;
	}

out:
	if (ret)
		put_futex_key(fshared, &q->key);
	return ret;
}
```

#### get_futex_key

```c
/**
 * get_futex_key() - Get parameters which are the keys for a futex
 * @uaddr:	virtual address of the futex
 * @fshared:	0 for a PROCESS_PRIVATE futex, 1 for PROCESS_SHARED
 * @key:	address where result is stored.
 * @rw:		mapping needs to be read/write (values: VERIFY_READ,
 *              VERIFY_WRITE)
 *
 * Returns a negative error code or 0
 * The key words are stored in *key on success.
 *
 * For shared mappings, it's (page->index, vma->vm_file->f_path.dentry->d_inode,
 * offset_within_page).  For private mappings, it's (uaddr, current->mm).
 * We can usually work out the index without swapping in the page.
 *
 * lock_page() might sleep, the caller should not hold a spinlock.
 */
static int
get_futex_key(u32 __user *uaddr, int fshared, union futex_key *key, int rw)
{
	unsigned long address = (unsigned long)uaddr;
	struct mm_struct *mm = current->mm;
	struct page *page, *page_head;
	int err, ro = 0;

    // futex のアドレスがアラインされているかどうか
	/*
	 * The futex address must be "naturally" aligned.
	 */
	key->both.offset = address % PAGE_SIZE;
	if (unlikely((address % sizeof(u32)) != 0))
		return -EINVAL;
	address -= key->both.offset;

    // PROCESS_PRIVATE の場合は、自プロセスの mm_struct とアドレスを key に保持する
    // futex(2) に指定したアドレスに write 可能かどうかを access_ok(VERIFY_WRITE) で見る
    // このアドレスを利用して、スレッド間のロックの仕組みを実現するのでしょう
	/*
	 * PROCESS_PRIVATE futexes are fast.
	 * As the mm cannot disappear under us and the 'key' only needs
	 * virtual address, we dont even have to find the underlying vma.
	 * Note : We do have to check 'uaddr' is a valid user address,
	 *        but access_ok() should be faster than find_vma()
	 */
	if (!fshared) {
		if (unlikely(!access_ok(VERIFY_WRITE, uaddr, sizeof(u32))))
			return -EFAULT;
		key->private.mm = mm;
		key->private.address = address;
		get_futex_key_refs(key);  /* implies MB (B) */
		return 0;
	}

   // PROCESS_PRIVATE じゃないので、プロセス間の futex
   // 他のプロセスと共有できる、実ページを探す必要がある
again:
	err = get_user_pages_fast(address, 1, 1, &page);
	/*
	 * If write access is not required (eg. FUTEX_WAIT), try
	 * and get read-only access.
	 */
	if (err == -EFAULT && rw == VERIFY_READ) {
		err = get_user_pages_fast(address, 1, 0, &page);
		ro = 1;
	}
	if (err < 0)
		return err;
	else
		err = 0;

#ifdef CONFIG_TRANSPARENT_HUGEPAGE

//...

#else
	page_head = compound_head(page);
	if (page != page_head) {
		get_page(page_head);
		put_page(page);
	}
#endif

	lock_page(page_head);

	/*
	 * If page_head->mapping is NULL, then it cannot be a PageAnon
	 * page; but it might be the ZERO_PAGE or in the gate area or
	 * in a special mapping (all cases which we are happy to fail);
	 * or it may have been a good file page when get_user_pages_fast
	 * found it, but truncated or holepunched or subjected to
	 * invalidate_complete_page2 before we got the page lock (also
	 * cases which we are happy to fail).  And we hold a reference,
	 * so refcount care in invalidate_complete_page's remove_mapping
	 * prevents drop_caches from setting mapping to NULL beneath us.
	 *
	 * The case we do have to guard against is when memory pressure made
	 * shmem_writepage move it from filecache to swapcache beneath us:
	 * an unlikely race, but we do need to retry for page_head->mapping.
	 */
	if (!page_head->mapping) {
		int shmem_swizzled = PageSwapCache(page_head);
		unlock_page(page_head);
		put_page(page_head);
		if (shmem_swizzled)
			goto again;
		return -EFAULT;
	}

	/*
	 * Private mappings are handled in a simple way.
	 *
	 * NOTE: When userspace waits on a MAP_SHARED mapping, even if
	 * it's a read-only handle, it's expected that futexes attach to
	 * the object not the particular process.
	 */
     // ANON なページの場合
     // fork して? mmap とかで共有しているページ?
	if (PageAnon(page_head)) {
		/*
		 * A RO anonymous page will never change and thus doesn't make
		 * sense for futex operations.
		 */
        // 読み取り専用だー 使えんわー         
		if (ro) {
			err = -EFAULT;
			goto out;
		}

		key->both.offset |= FUT_OFF_MMSHARED; /* ref taken on mm */
		key->private.mm = mm;
		key->private.address = address;
     // ANON じゃない場合。こっちは何?
     // 共有メモリ (内部実装は tmpfs) のことかｎ?
     // inode-based key is ???
	} else {
		key->both.offset |= FUT_OFF_INODE; /* inode-based key */
		key->shared.inode = page_head->mapping->host;
		key->shared.pgoff = page_head->index;
	}

	get_futex_key_refs(key); /* implies MB (B) */

out:
	unlock_page(page_head);
	put_page(page_head);
	return err;
}
```