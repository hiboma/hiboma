# 4.7 タイマーリスト

https://github.com/hiboma/kernel_module_scratch/tree/master/timer でサンプル実装

 * 一定時間後に実行されるコールバックハンドラを登録する仕組み。時限処理
 * 古典UNIX の callout の仕組み
   * しらんがな〜
 * ローカルタイマソフト割り込みのタイミングでタイマが実行される

### add_timer の API

 * expires はタイマの発動時間を指定する
 * timer は自動で削除されないので、追加する側の責任で del_timer で消すこと

```c
	init_timer(&timer);
	timer.expires  = jiffies + 3*HZ; /* 3sec */
	timer.data     = 0;
	timer.function = timer_callback;
	add_timer(&timer);
``` 