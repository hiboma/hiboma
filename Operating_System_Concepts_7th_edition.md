# Operating_System_Concepts_7th_edition.txt

## 7 Deadlocks

 * システムコール/ライブラリコールでの例
  * Request => open(2), malloc()
  * use
  * Release => close(2), free()

 * physical resource , logical resource
  * Logical Desigin ... では serially resource と consumable resource と表記
  
### 7.2.2 Resource Allocation Graph

 * vertices V 頂点 と edges E
   * nodes N と E でないのだな。
   * Pi -> Rj request edge
   * Rj -> Pi assignment edge

 * 毎度おなじみ四つの必要条件
   * Mutual execution ( not sharable な resource )
   * Hold and wait
   * No Preemption
   * Circular Wait
     * resource の数が one instance の場合にのみデッドロックの必要充分条件

### 7.7 Recovery From Deadlock
   
### 7.7.2 Resource Preemption

 * 短期的に見れば OOM Killer は resource preemption の動作をする
   * Reduce Edge
   * kill すべきプロセスを探す => OOM の スコア 

