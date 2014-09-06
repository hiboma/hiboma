# Operating System Concepts and Techniques

 * logarithmus naturalis ln
 * Affinity
 * Gang Scheduling Co-Scheduling
 * Rate-Monotonic Scheduling、RMS
 * http://ja.wikipedia.org/wiki/レートモノトニックスケジューリング
 * リアルタイムOS向けのアルゴリズム

## 8.1.1 Race Condition

 * C の ++ インクリメントを命令レベルで見る

```
1 load  r1, value
2 inc   r1
3 store r1, value
```

 * 共有されたデータで複数のプロセスの命令が interleave する
   * どのように命令が実行されるか予想できない
   * => race condition
 * instruction 実行中は割り込まれない
   * メモリ間でデータをコピーするmove命令のように例外はある

```
# = が instruction 実行中
----===---===---===---===---
```

## 9.1.1 Deadloack Conditions adn Modeling

 * 3つの必要条件
   * Mutual exclusion
     * 1プロセスだけリソースを確保出来る場合
       * race condition を防ぐには相互排他が必要
       * race condition を放置すれば相互排他は必要ない
   * Hold and wait
     * リソースを確保しつつ、他のリソース待ち
   * Non preemptable resources
     * preemption できないリソース
     * preemption できるリソース ... CPU, ページフレーム

並行性(並列性)を高めるためにOSの実装で避けては通れない条件

   * Circular wait
     * 十分条件

### 9.1.2 Ignoreing Deadlock

 * デッドロックを無視する
  * ok  ... 学生が作ったプログラムがデッドロック => タスクマネージャーで止める
  * not ... 銀行の引き落としなど
  
### 9.1.2 Deadlock Prevention

 * 3つの必要条件のどれかを満たせないようにする
   * パフォマンスに大きく影響する
    * ok) シングルプログラミングな環境。
    * ok) メモリの書き込みは
 * Removing the hold-and-wait condtion
   * 例) 必要なリソースをプロセス起動後に確保、以後リソース確保のリクエストをださない
   * 前もって知る必要がある
     * 見極めが難しい、途中でリソースを解放する場合本当に再利用しないかどうかの判断

### 9.1.2. Deadlock Avoidance

 * prevention との違い
   * 将来的なリソース使用の見積もりをたてリソース割当をしてデッドロックを回避
   * 例) 銀行家のアルゴリズム(ダイクストラ)

### 9.1.5 Deadlock Detection and Recovery

 * Deadlock Detection = circular wait をみつける
   * circular wait が発生している状態 = デッドロックの十分条件 なので
 * Deadlock Recvery
   * kill process, トランザクションのロールバック
 * process table
   * "waiting for (resource)" なフィールドを設ける
 * resource table
   * "possesing process" なフィールドを設ける
 * 二つのフィールドで循環が生じていたらデッドロック?


