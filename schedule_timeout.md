# schedule_timeout の実装

 * 2.6.32

## API

 * set_current_state
 * timer
 * schedule

## schedule_timeout

 * timeout が経過するまで待つ
   * お馴染みの TASK_UNINTERRUPTIBLE, TASK_INTERRUPTIBLE
 * set_current_state() で プロセスの state を変えていないとすぐに return する
 * return する時に current が TASK_RUNNING であることが保証される
 * setup_timer_on_stack で timeout を実装している

```c
/**
 * schedule_timeout - sleep until timeout
 * @timeout: timeout value in jiffies
 *
 * Make the current task sleep until @timeout jiffies have
 * elapsed. The routine will return immediately unless
 * the current task state has been set (see set_current_state()).
 *
 * You can set the task state as follows -
 *
 * %TASK_UNINTERRUPTIBLE - at least @timeout jiffies are guaranteed to
 * pass before the routine returns. The routine will return 0
 *
 * %TASK_INTERRUPTIBLE - the routine may return early if a signal is
 * delivered to the current task. In this case the remaining time
 * in jiffies will be returned, or 0 if the timer expired in time
 *
 * The current task state is guaranteed to be TASK_RUNNING when this
 * routine returns.
 *
 * Specifying a @timeout value of %MAX_SCHEDULE_TIMEOUT will schedule
 * the CPU away without a bound on the timeout. In this case the return
 * value will be %MAX_SCHEDULE_TIMEOUT.
 *
 * In all cases the return value is guaranteed to be non-negative.
 */
signed long __sched schedule_timeout(signed long timeout)
{
	struct timer_list timer;
	unsigned long expire;

	switch (timeout)
	{
    // タイマをセットしない
    // エコ?
	case MAX_SCHEDULE_TIMEOUT:
		/*
		 * These two special cases are useful to be comfortable
		 * in the caller. Nothing more. We could take
		 * MAX_SCHEDULE_TIMEOUT from one of the negative value
		 * but I' d like to return a valid offset (>=0) to allow
		 * the caller to do everything it want with the retval.
		 */
		schedule();
		goto out;
	default:
		/*
		 * Another bit of PARANOID. Note that the retval will be
		 * 0 since no piece of kernel is supposed to do a check
		 * for a negative retval of schedule_timeout() (since it
		 * should never happens anyway). You just have the printk()
		 * that will tell you if something is gone wrong and where.
		 */
		if (timeout < 0) {
			printk(KERN_ERR "schedule_timeout: wrong timeout "
				"value %lx\n", timeout);
			dump_stack();
			current->state = TASK_RUNNING;
			goto out;
		}
	}

	expire = timeout + jiffies;

    // タイマをスタックに確保
    // (unsigned long)current で task_strcut のアドレスを取る
	setup_timer_on_stack(&timer, process_timeout, (unsigned long)current);
    // タイマの expire をセット
	__mod_timer(&timer, expire, false, TIMER_NOT_PINNED);
    // 待機
	schedule();
    // タイマを削除?
	del_singleshot_timer_sync(&timer);

	/* Remove the timer from the object tracker */
    // タイマオブジェクトを削除?     
	destroy_timer_on_stack(&timer);

	timeout = expire - jiffies;

 out:
	return timeout < 0 ? 0 : timeout;
}
EXPORT_SYMBOL(schedule_timeout);
```

## process_timeout

 * setup_timer_on_stack でタイムアウトになると発火するコールバック
 * 自分自身を wake_up_process する

```
static void process_timeout(unsigned long __data)
{
	wake_up_process((struct task_struct *)__data);
}
```

スタックにタイマを持っている + 自分自身を wake_up_process するようコールバックを呼ぶのがおもしろ