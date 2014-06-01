
# 4.8 インターバルタイマー

setitimer, getitimer, alarm の仕組みの説明

 * SIGPROF
 * SIGVTLALRM
   * プロセスが実行中に減るタイマ
 * SIGALRM
   * 絶対時間 = 実時間でのタイマ

## 4.8.1 絶対時間指定タイマー

 * alarm(2), setitimer(2) + ITMER_REAL のこと
 * alarm は精度が秒、setitimer はマイクロ秒かの違いなだけでどちらも do_setitimer でタイマをセットする.

### alarm(2) の実装を追ってみる

素朴なインタフェース

```c
/*
 * For backwards compatibility?  This can be done in libc so Alpha
 * and all newer ports shouldn't need it.
 */
SYSCALL_DEFINE1(alarm, unsigned int, seconds)
{
	return alarm_setitimer(seconds);
}
```

alarm_setitimer で、setitimer のインタフェースを使ってタイマをセットする

```c
/**
 * alarm_setitimer - set alarm in seconds
 *
 * @seconds:	number of seconds until alarm
 *		0 disables the alarm
 *
 * Returns the remaining time in seconds of a pending timer or 0 when
 * the timer is not active.
 *
 * On 32 bit machines the seconds value is limited to (INT_MAX/2) to avoid
 * negative timeval settings which would cause immediate expiry.
 */
unsigned int alarm_setitimer(unsigned int seconds)
{
	struct itimerval it_new, it_old;

#if BITS_PER_LONG < 64
	if (seconds > INT_MAX)
		seconds = INT_MAX;
#endif
    // itimerval を秒でセット
	it_new.it_value.tv_sec = seconds;
	it_new.it_value.tv_usec = 0;
	it_new.it_interval.tv_sec = it_new.it_interval.tv_usec = 0;

    // do_setitimer は sys_settitmer でも使ってる
	do_setitimer(ITIMER_REAL, &it_new, &it_old);

	/*
	 * We can't return 0 if we have an alarm pending ...  And we'd
	 * better return too much than too little anyway
	 */
	if ((!it_old.it_value.tv_sec && it_old.it_value.tv_usec) ||
	      it_old.it_value.tv_usec >= 500000)
		it_old.it_value.tv_sec++;

	return it_old.it_value.tv_sec;
}
```

do_setitimer がなかなごっつい

 * tsk->signal->real_timer が struct hrtimer なのが味噌かな?
 * hrtimer is **高精度カーネルタイマ** らしい

```c
int do_setitimer(int which, struct itimerval *value, struct itimerval *ovalue)
{
	struct task_struct *tsk = current;
	struct hrtimer *timer;
	ktime_t expires;

	/*
	 * Validate the timevals in value.
	 */
	if (!timeval_valid(&value->it_value) ||
	    !timeval_valid(&value->it_interval))
		return -EINVAL;

	switch (which) {
	case ITIMER_REAL:
again:
		spin_lock_irq(&tsk->sighand->siglock);
        // プロセスのタイマを取る
		timer = &tsk->signal->real_timer;
		if (ovalue) {
			ovalue->it_value = itimer_get_remtime(timer);
			ovalue->it_interval
				= ktime_to_timeval(tsk->signal->it_real_incr);
		}
		/* We are sharing ->siglock with it_real_fn() */
		if (hrtimer_try_to_cancel(timer) < 0) {
			spin_unlock_irq(&tsk->sighand->siglock);
			goto again;
		}
		expires = timeval_to_ktime(value->it_value);
		if (expires.tv64 != 0) {
			tsk->signal->it_real_incr =
				timeval_to_ktime(value->it_interval);

            // ここでタイマを開始
			hrtimer_start(timer, expires, HRTIMER_MODE_REL);
		} else
			tsk->signal->it_real_incr.tv64 = 0;

		trace_itimer_state(ITIMER_REAL, value, 0);
		spin_unlock_irq(&tsk->sighand->siglock);
		break;
```

> 指定した時間の経過後に実行されるハンドラはit_real_fn関数です。

it_real_fn は copy_singal でセットされている

```c
/*
 * The timer is automagically restarted, when interval != 0
 */
enum hrtimer_restart it_real_fn(struct hrtimer *timer)
{
	struct signal_struct *sig =
		container_of(timer, struct signal_struct, real_timer);

	trace_itimer_expire(ITIMER_REAL, sig->leader_pid, 0);

    // SIGALRM を leader_pid に送っている
	kill_pid_info(SIGALRM, SEND_SIG_PRIV, sig->leader_pid);

	return HRTIMER_NORESTART;
}
```

## 4.8.2 実行時間指定タイマー

----

寄り道

 * tickless カーネル
   * CONFIG_NO_HZ
   * http://www.ibm.com/developerworks/jp/linux/library/l-green-linux/