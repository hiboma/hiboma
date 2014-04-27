# 3.2 workqueue

> 主にプロセスコンテキストの処理を遅延させるために利用されています

 * 割り込みコンテキストの遅延処理
   * softirq, ksoftirqd, tasklet
 * デバイスドライバ、ブロックI/O、非同期I/O