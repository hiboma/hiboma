
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