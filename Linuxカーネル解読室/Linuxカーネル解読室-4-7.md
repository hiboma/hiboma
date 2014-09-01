# 4.7 タイマーリスト

**struct timer_list** の説明の章.

https://github.com/hiboma/kernel_module_scratch/tree/master/timer でサンプル実装書いている

 * 一定時間後に実行されるコールバックハンドラを登録する仕組み。時限処理
 * 古典UNIX の callout の仕組み
   * しらんがな〜
 * ローカルタイマソフト割り込みのタイミングでタイマが実行される
   * `raise_softirq_irqoff(TIMER_SOFTIRQ);`

## 4.7.4 プロセスからの利用

プロセスコンテキストからの利用てことかな

 * schedule_timeout
 * process_timeout
   * `wake_up_process((struct task_struct *)__data);`
 * sleep_on_timeout, interruptible_sleep_on_timeout

kernel/schedule_timeout.md に書いた 

### ローカルCPU の softirq

TIMER_SOFTIRQ が softirq 番号。初期化は下記のコードでされている

```c   
void __init init_timers(void)
{
	int err = timer_cpu_notify(&timers_nb, (unsigned long)CPU_UP_PREPARE,
				(void *)(long)smp_processor_id());

	init_timer_stats();

	BUG_ON(err == NOTIFY_BAD);
	register_cpu_notifier(&timers_nb);
	open_softirq(TIMER_SOFTIRQ, run_timer_softirq);
}
```

softirq を出すのは以下のコード。CPU コアごとに発火する割り込みですぞ

```c
/*
 * Called by the local, per-CPU timer interrupt on SMP.
 */
void run_local_timers(void)
{
	hrtimer_run_queues();
	raise_softirq(TIMER_SOFTIRQ);
}
```

softirq ハンドラは **run_timer_softirq**

 * hrtimer_run_queues ? は後で
 * __run_timers が timer_list を順次見ていって処理するコード

```
/*
 * This function runs timers and the timer-tq in bottom half context.
 */
static void run_timer_softirq(struct softirq_action *h)
{
	struct tvec_base *base = __get_cpu_var(tvec_bases);

	hrtimer_run_pending();

	if (time_after_eq(jiffies, base->timer_jiffies))
		__run_timers(base);
}
```

### add_timer の API

 * expires はタイマの発動時間を指定する
 * timer は自動で削除されない。追加する側の責任で del_timer で消すこと
   * 再度発火させる場合は mod_timer 使う?

```c
	init_timer(&timer);
	timer.expires  = jiffies + 3*HZ; /* 3sec */
	timer.data     = 0;
	timer.function = timer_callback;
	add_timer(&timer);
```

### add_timer_on

~~暇な CPU~~ 忙しいCPUにタイマーリストを設定させる

 * チックレースカーネルで電力消費抑える
 * 暇なCPUの数が多い => チックを抑える事ができる

```
sysctl kernel.timer_migration = 1
```

## 4.8 インターバルタイマー

setitimer, getitimer, alarm の仕組みの説明

 * SIGPROF
 * SIGVTLALRM
   * プロセスが実行中に減るタイマ
 * SIGALRM
   * 絶対時間 = 実時間でのタイマ

## 4.8.1 絶対時間指定タイマー

 * alarm(2), setitimer(2) + ITMER_REAL のこと
 * alarm は精度が秒、setitimer はマイクロ秒かの違いなだけでどちらも do_setitimer でタイマをセットする.

### alarm の実装を追ってみる

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

## 4.8.2 実行時間指定タイマー

----

寄り道

 * tickless カーネル
   * CONFIG_NO_HZ
   * http://www.ibm.com/developerworks/jp/linux/library/l-green-linux/