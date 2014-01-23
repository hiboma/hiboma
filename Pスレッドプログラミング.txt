# Pスレッドプログラミング

 * 並行処理で起こる同期やデッドロックの問題は並列処理でも起こりうる

## 5. スケジューリング

 * 多対1モデルがコルーチンとして扱われている
   * 広義な意味での「coroutine」として注釈がついている
 * 2レベルモデル
   * 1対1 + 多対多のハイブリッド

 * スレッドスケジューリング
 * Process Contention Scope (Unbound Thread)
   * プロセス競合範囲スケジューリング
     * synchronization
     * preemption
     * yield
     * time shareing
   * 多対1で使う。スケジューリングがプロセスローカル = カーネルを介さない

LWP に Bound される/されない => Unbound/Bound ということだろう

 * System Contention Scope (Bound Thread)
   * システム競合範囲スケジューリング
   * 1対1 ? or 多対多で使う。カーネルがスケジューリング

