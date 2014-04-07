# 3.1 割り込み処理の遅延

 * ハードウェア割り込みハンドラ
   * 要応答性
 * その他は softirq, tasklet で遅延処理する
   * softirq, tasklet 実行中は割り込み可能なので、ハードウェア割り込みの応答性を確保

## 3.1.1 マルチプロセッサへの対応

 * 同種のハードウェア割り込み単一のCPUでのみ実行可能
 * softirq は並列実行可能
   * ハードウェア割り込みを softirq に委譲させてスケーラビリティを確保m
   * softirqハンドラは、ハードウェア割り込みを受けたCPU上で実行される
     * CPUキャッシュ++

## 3.1.2 ソフト割り込みスタック

 * ハードウェア割り込みがネストする可能性がある
 * 大きめに確保
 * プロセスのスタックを利用 (thread_info)

```
struct thread_info

+------------------------+
|                        |
|          ^             |
|          |             |
+------------------------+
| タイマ割り込みハンドラ |
+------------------------+
|    SCSI割り込み        |
+------------------------+
|    TCP/IP softirq      |
+------------------------+
|                        |
|   システムコール処理   |
|                        |
+------------------------+
```

## 3.1.3 ソフト割り込み


```c
void open_softirq(int nr, void (*action)(struct softirq_action *))
{
	softirq_vec[nr].action = action;
}

// #!ruby で書いた場合
// 
// softirq_vec[nr] = lambda { ... }
//
```

```c
// linux-2.6.32-431
enum
{
	HI_SOFTIRQ=0,
	TIMER_SOFTIRQ,
	NET_TX_SOFTIRQ,
	NET_RX_SOFTIRQ,
	BLOCK_SOFTIRQ,        // New!
	BLOCK_IOPOLL_SOFTIRQ, // New!
	TASKLET_SOFTIRQ,
	SCHED_SOFTIRQ,        // New!
	HRTIMER_SOFTIRQ,      // New!
	RCU_SOFTIRQ,	/* Preferable RCU should always be the last softirq */

	NR_SOFTIRQS
};
```