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

 * alarm(2), settitmer(2) + ITMER_REAL

## 4.8.2 実行時間指定タイマー

----

寄り道

 * tickless カーネル
   * CONFIG_NO_HZ
   * http://www.ibm.com/developerworks/jp/linux/library/l-green-linux/