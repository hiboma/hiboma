# The Logical Design of Operating Systems

## 1. BRIDING THE HARDWARE/USER GAP

 * bridge, gap という表現がよく出て来る
  * hardware --- OS --- user
 * von Neumann
 
### 1.2.2 THE PROCESSOR/DEVICE INTERFACE

 * 割り込みハンドラの擬似コード

    loop
        w  := Memory[ic]  # Fetch next instruction
        ic := ic + 1      # Increment instruction counter
        Execute(w)   
        if interrupt then
        begin
            Store(ic)
            case interrupt_cause of # 割り込みベクタ
                C1 : ic := int1
                C2 : ic := int2
                ...
                Cn : ic := intn
            end {case}
        end
    end {loop}

 * 同期I/O, ポーリング, 割り込み の図解がよく出来ている
 * Direct Memory Access
   * `channel`
   * デバイス用に特化したプロセッサ。メインフレームなんかのチャンネルと同義?

### 1.3.2 PRINCIPLES OF MULTIPROGRAMMING

 * I/Oバウンド、CPUバウンドの図解
 * improve throughput, turnaround time
 * `Multiprogrammed systems`
   * sharing of time  on processors
   * sharing of space in main memory
     * share code resident in memory

> Bridge the gap between the machine and the user level.> The operating system
> must hide many aspects of the actual hardware by providing higher level of instructions

 * Protection
 * synchronization and communication privmitieves
  * Multiprogrammed な環境だから必要よね

 * a multiprogramming operating system に必要とされる機構 を上げている
   * DMA
   * Interrupt mechanism
   * Timer
   * Storage and instruction proctection
   * Dynamic address relocation

割とざっくり

## 1.3.3. OPERATING SYSTEMS AS VIRTUAL MACHINES

  * OS仮想かのVM ではなくて、 Multiprogramming なプロセスから見ると virtual machine に見える
   * Abstraction
     * 仮想メモリ
     * 抽象化/仮想化によって物理的な制限を取り払う

## 1.5. STRUCTURE OF OPERATING SYSTEM

 * A Monolithic Structure
   * User programgs may be viewed as subroutines invokes by the operating system
   * SVC Sueprvisor Call ( not system call )
     * OS と ユーザプログラムが分離されていない => 廃れた

 * The Kernel Approach
   * プロセスによる抽象化
   * 実例) Brinch Hansen 1970
     * RC 4000 Multiprogramming System
     * http://en.wikipedia.org/wiki/RC_4000_Multiprogramming_System
     * メッセージパッシング的な仕組みで動くぽい。プロセス間通信の仕組み

### 1.5.3 A PROCESS HIERARCHY

抽象化によって階層化

 * プロセスを階層化、権限の分離
   * THE (Dijkstra 1968) のプロセスは多階層のモデル。Machもこれに該当する?
   * UNIXはユーザ/カーネルの分離だけ

### 1.5.4 A  FUNCTIONAL HIERARCHY

 * Habermann, Flon, and Cooprider (1976)
   * プロセスではなくて `functions` で階層化

## 2 CONCURRENT PROGRAMMINGS METHODS

 * 高度に nondeterminism 非決定的な環境
  * `sequential process` (= task) プロセスとしてモデル化。
  * OSを複数のプロセスが並行して実行されているモデルとしてみなす

## 2.2.1 PROCESS FLOW GRAPHS

 * プロセスの実行フローをグラフで表現
   * acyclic graph

```
S(a, b) serial connection 
P(a, b) parallel connection
```

 * ネストする flow graph
 * ネストしない flow graph

 * ネストする process flow graphs のサンプルを三つあげている
  * 例1) 数式の計算 = ツリーの深さ => 並列度
    * ツリー上のデータ構造 => 並列計算の用語で表現できる?
 
> Many problems in which the primary data structure is a tree can be logically
> described in terms of parallel computations

   * 例2) ソート
     * i回でソートできる 2 way マージソートの場合
     * ソートするリスト 2 ** i-1 に分割されて 2**i にマージされる
      *それぞれのソートパスは並列して実行できる

 * 例3) matrix multiplication
   * 行列計算

## 2.2.2 COBEGIN / COEND

 * Dijkstra 1968

```
cobegin C1|C2|...|Cn coend
```

 * Ci  autonomous segument of code (独立したプログラムでプロセスとして起動する
   * C1...Cn が並行して実行されることを示す記法
 * cobegin/coend 式は S, P に変換して記述することができる

```
P(C1, P(C2, .... P(...,Cn) ...))

# ここで code segument Ci は Pi1, Pi2 ... Pim のシーケンスに分解できる

S(Pi1, S(Pi2, .... S( ...., pim) ... ))
```     

 * P/S式, cobegin/coend式 ともに nested flow graphs を記述するにとどまる

2-1d のフローは P6 を遅延させて wait させてよいのであれば、 nested flow graphs に変換することもできる

### 2.2.3 THE FORK, JOIN, AND QUIT PRIMITIVES

 * Conway 1963, Deniis and Van Horn 1966
   * http://www.princeton.edu/~rblee/ELE572Papers/Fall04Readings/ProgramSemantics_DennisvanHorn.pdf
 * データを共有しているので、プロセスよりスレッドを思い浮かべた方が直感的
   * UNIXの例
   * Mesa?の例
     * http://en.wikipedia.org/wiki/Mesa_(programming_language)
     * プロセスをオブジェクトとして扱う。変数として受け渡しできたり。

### 2.2.4 EXPLICIT PROCESS DECLARATIONS

 * Ada 言語 http://ja.wikipedia.org/wiki/Ada

```
process p
  # 静的に宣言されるプロセス
  process p1
    declarations for p1
  begin
   ...
  end
  # 動的に生成できるプロセス
  process type p2
    declarations for p2
  begin
   ...
  end
begin

  ...
  q := new p2 # 任意のタイミングでのスレッド生成、もしくはプロセスのfork
  ...
end
```

### 2.3 THE CRITICAL SECTION PROBLEM

 * クリティカルセクション
  * 共有するデータの扱い方
  * FETCH, STORE のタイミングが非決定的 => 意図しない計算
  * 排他制御 `mutual execution` する

 * ビジーループによるロック(スピンロック?)の実装例が載っている
  * ビット演算でフラグがたっているかどうかでアトミックになるのだろうか? => それっぽい
  * pthread で無理矢理実装
    * 一方のスレッドがロックを占有することもある
    * ビジーウェイト中にシステムコール読んだりすると均一っぽくなる, けど目的と違う

```
// file://_/c/pthread-mutex.c

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

static bool c1 = true;
static bool c2 = true;
static int turn  = 1;
static int count = 100000;
static int count_a_called = 0;
static int count_b_called = 0;

void * handle_thread_c1(void *arg)
{
  while(count > 0) {
    c1 = false;
    turn = 1;
    while(c2^turn != 1) { asm("nop;"); }
    c1 = true;
    if(count <= 0)
      break;
    count--;
    count_a_called++;
    asm("nop;");
  }
}

void * handle_thread_c2(void *arg)
{
  while(count > 0) {
    c2 = false;
    turn = 2;
    while(c1^turn != 2) { asm("nop;"); }
    c2 = true;
    if(count <= 0)
      break;
    count--;
    count_b_called++;
    asm("nop;");
  }
}

/* here come the code */
int main(int argc, char *argv[]){

  pthread_t thread_c1, thread_c2;
  pthread_create(&thread_c1, NULL, handle_thread_c1, NULL);
  pthread_create(&thread_c2, NULL, handle_thread_c2, NULL);
  sleep(5);
  printf("count: %d %d %d \n", count, count_a_called, count_b_called);
  abort();
  exit(0);
}
```

### 2.3.2 COOPERATING SYSTEM

 * クリティカルセクションの問題は、リソースの奪い合い(compete) の問題
 * compete しないで cooperating する
   * producer / consumer モデル
   * [ Prodcuer ] -----> [ shared buffer ] ----> [ Consumer ]
   * producer, consumer が並行して動作できる。共有のデータを上書きしない
   * producer, consumer が同期、通信、シグナリングできる仕組みが必要 

### 2.4 SEMAPHORE PRIMITIVES

 * セマフォ (Dijkstra 1965)
  * P(s)
   * 下げる
   * negative でもよい
  * V(s) 上げる
   * fetch && incremnt && store
   * indivisible action ( atomic な操作?)
   
  * critical section 用のロック、同期機構として使う
   
複数プロセスがセマフォを同時に獲得する場合順番は保証されない

 * `binary semaphore` = `mutex`
  * mutex はサンプルコードの変数名として出るだけで、そういう primitives があるという説明ではない
  
### 2.4.4 IMPREMENTING SEMAPHORE OPERATIONS

 * セマフォを使った同期の仕組み
   * クリティカルセクションのロックの話とは別

    var s: semaphore
    s: = 0;   # 最初からゼロなので P(s) がブロックする 
    cobegin
    p1: begin
         :
        P(s)  { Wait for signal from p2 } # ブロックする。p2 が V(s) すると再開する
         :
        end
    
    p2: begin
         :
        V(s)  { Send wakeup signal to p1} # p1 を起床させる
         :
        end
    coend

    function TS(X: Boolean): Boolean
    begin
      TS := X:
      X := false
    end {TS}

 * ビジーループでの実装

    # sb は セマフォ
    Pb ... while !TS(sb) do; { wait loop }
    Vb ... sb = True

 * 割り込みの禁止
   * セマフォ獲得中に割り込みハンドラを実行することでのデッドロック防止
     * マルチプロセッサの場合、ローカルCPUの割り込みを禁止しただけじゃ他CPUからのアクセスを防げない
     * 他プロセッサを排他するには mutex が必要 => Pb, Vb

 * context switch を利用しての実装
   * process を suspension (`blocking`)
   * Linux の セマフォが プロセスをsleepさせてブロッキング
   
### 2.6.32 Linux のセマフォの実装 P(s) = down(struct semaphore * ), V(s) = up(struct semaphore *)

 * struct semaphore
   * wait_list で待ちプロセスの管理 => FIFO キュー

    /* Please don't access any members of this structure directly */
    struct semaphore {
    	spinlock_t		lock;
    	unsigned int		count;
    	struct list_head	wait_list;
    };

 * P(s)
  * down(struct semaphore *sem) で呼び出しできる

    /**
     * down - acquire the semaphore
     * @sem: the semaphore to be acquired
     *
     * Acquires the semaphore.  If no more tasks are allowed to acquire the
     * semaphore, calling this function will put the task to sleep until the
     * semaphore is released.
     *
     * Use of this function is deprecated, please use down_interruptible() or
     * down_killable() instead.
     */
    void down(struct semaphore *sem)
    {
    	unsigned long flags;
    
    	spin_lock_irqsave(&sem->lock, flags);

    	if (likely(sem->count > 0))
    		sem->count--;
    	else
           // sem->count が 0 以下だと待つ
    		__down(sem);
    	spin_unlock_irqrestore(&sem->lock, flags);
    }
    EXPORT_SYMBOL(down);

 * セマフォ獲得を試みみる間は TASK_UNINTERRUPTIBLE にされる

    static noinline void __sched __down(struct semaphore *sem)
    {
    	__down_common(sem, TASK_UNINTERRUPTIBLE, MAX_SCHEDULE_TIMEOUT);
    }

 * @ セマフォごとに待ち行列を持つ
   * => semaphore_waiter を sem->wait_lit に繋げてセマフォ獲得でブロックしているプロセスを管理する実装
 * @ context switch して busy loop を避ける
   * => schedule_timeout() の中で schedule() する実装
 * @ 割り込みを禁止する
   * => spin_lock_irqsave で実装

    /*
     * Because this function is inlined, the 'state' parameter will be
     * constant, and thus optimised away by the compiler.  Likewise the
     * 'timeout' parameter for the cases without timeouts.
     */
    static inline int __sched __down_common(struct semaphore *sem, long state,
    								long timeout)
    {
    	struct task_struct *task = current;
    	struct semaphore_waiter waiter;
    
    	list_add_tail(&waiter.list, &sem->wait_list);
    	waiter.task = task;
    	waiter.up = 0;
    
    	for (;;) {
    		if (signal_pending_state(state, task))
    			goto interrupted;
    		if (timeout <= 0)
    			goto timed_out;
    		__set_task_state(task, state);
    		spin_unlock_irq(&sem->lock);
    		timeout = schedule_timeout(timeout);
    		spin_lock_irq(&sem->lock);
            // 別の場所で起床?
    		if (waiter.up)
    			return 0;
    	}
    
     timed_out:
    	list_del(&waiter.list);
    	return -ETIME;
    
     interrupted:
    	list_del(&waiter.list);
    	return -EINTR;
    }

 * V(s)
   * up(struct semaphore *sem)

    /**
     * up - release the semaphore
     * @sem: the semaphore to release
     *
     * Release the semaphore.  Unlike mutexes, up() may be called from any
     * context and even by tasks which have never called down().
     */
    void up(struct semaphore *sem)
    {
    	unsigned long flags;

    	spin_lock_irqsave(&sem->lock, flags);
    	if (likely(list_empty(&sem->wait_list)))
    		sem->count++;
    	else
    		__up(sem);
    	spin_unlock_irqrestore(&sem->lock, flags);
    }
    EXPORT_SYMBOL(up);

 * P(s) = down() で ブロックしているプロセスが起床するように waiter->up = 1
   * list_add_tail => list_first_entry で管理しているので、キューとして扱われている

    static noinline void __sched __up(struct semaphore *sem)
    {
    	struct semaphore_waiter *waiter = list_first_entry(&sem->wait_list,
    						struct semaphore_waiter, list);
    	list_del(&waiter->list);
    	waiter->up = 1;
    	wake_up_process(waiter->task);
    }

 * wake_up_process => try_to_wake_up でプロセスを起床、run queue に繋ぐ
   * @ CPUのマイグレーション ?

### 2.6 CONDITIONAL CRITICAL REGION

 * セマフォの P,V 操作のミス
  * P, V の操作を 一対にして配置しないといけない
    * 実行パスの漏れがあってはいけない
  * P の回数だけが多い => クリティカルリージョンに入れない。デッドロック
  * V の回数だけが多い => 複数のプロセスがクリティカルリージョンに入る
  * コードの可読性

 * CCR Conditional Critical Region
   * ブロック記法でクリティカルリージョンであることの可読性が高い

    region B do 
      S
    end

 * 実装例が少ない
   * ローカル変数

## 3. Proces and Resource Control

 * kernel, nucleus
   * primitive operations and process

 * kernel operations
   * prcess creation, destruction, IPC
   * resource allocating, releasing
   * I/O
   * interruputs

 * プロセスツリーの形成

* 3.2 DATA STRUCTURES FOR PROCESSES AND RESOURCES

 * プロセスやリソースの表現 
   * 状態、一意性、アカウティングの情報
   * `control blocks` `descriptors` と呼ばれる data structures

### 3.2.1 PROCESS DESCRIPTORS

task_struct 的なデータ構造の説明

 * 別名 `PCB process control block`
   * VAX だと PCB と呼んでる
   * Identification
     * ユニークに識別するためのデータ。pidに相当
     * 書籍では Id が string として扱われていて、int pid に相当するデータは無い
   * State Vector
     * s0, s1, ...., si, .... , プロセスの実行は次に実行される命令のベクタで表現される。状態
     * プログラムカウンタ (= instruction counter), レジスタ
   * Status Information
     * running, ready, blocked, ...
     * 書籍では blocked = sleeping の状態
   * Other Information
     * プロセスの親子関係の情報
     * プライオリティ
     * プロセスアカウンティング

uid,gid に相当するデータについての記述が無い

### 3.2.2 RESOURCES DESCRIPTORS

 * `resource` リソース とは ? by Weiderman(1971)
   * resusable by process during their activity
   * stable    by ...
   * requested ...
   * used      ...
   * released  ...
    * ハードウェアのコンポーネントを指す用語に適用される

  * データやプログラムなどのも `resource`
    * `serially resusable`
    * `serial basis` ... 1度に1プロセスだけが利用する形式で共有される

`resource` のデータに必要なもの

 * An inventory list
 * A waiting list
 * An allocator

その他の `serially resusable`

  * `consumable` な resource
    * synchronization, communication で使われる
      * セマフォのようなIPCで使われるメッセージ
      * メモリのようなシステムに返却するリソースとは性格が違う

 * `logically blocked`
   * serially resource consumable resource は、確保できない場合にブロックされる
   * プロセスをブロックさせるものは何でも `resource` である。

### Inventory List

 * リソースの実体の管理
   * bitma, ストレージのブロックのtable、バッファのlist ... などで表現される

### Waiting Process List

 * r->wainters
   * リソース獲得待ちでブロックしているプロセスのリスト, queue
     * リスト管理
     * ブロックしているプロセスにシグナルを飛ばす方式
       * thundering hurd ???

### Allocator

 * r->waiters の queue からリクエストを取り除く

### 3.2.3 The processor resource

 * CPUは他のリソースとは区別して扱う
    * CPU割当待ちを `logically blocked` と見なさない
      * CPUをリンクリストではなくて Array で管理
        * 全CPUを走査する必要があり、効率が大事
      * CPU待ちのプロセスは `readly list RL` (runqueue) として管理
        * プライオリティつくことで、FIFOで割当される訳じゃない
        * 単純なリンクリストでは実装できない

### 3.2.4 Implementation of queues

runqueue のこと

 * readly list RL を priority queue とする
   * プライオリティ別に queue を持つ
   * Insert(), Remove() の操作が発生する
     * => Linux だと 2重リンクリストで ok

### 3.3 BASIC OPERATIONS ON PROCESSES AND RESOURCES

### 3.3.1 process Control
 * プロセスの管理方法
   * Create, Destroy, Suspend (sleep), Activate(wakeup), Change_Priority

### 3.5 SCHEDULING METHODS

## 4 The Deadlock Problem

> Finally, deadlock studies attempt to partially answer one of the fundamental questions
> in computer schience: Can a process progress to completion ?

* 4.2 A SYSTEMS MODEL

 * 表記

```
     i
   S -> T                       # プロセス pi が system state を S から T にする

   <ρ, π>                     # system は二つのペアからなる
   ρ は {S, T, U, V ... }      # ρ は system states の集合
   π    {p1, p2, p  ... }      # π は process の集合

   p1                           # partial function 部分関数
   pi : ρ -> {ρ}              # from systems states info nonempty subsets of system states
```

 * process が request, acquite, release resouce などで systable state を変えられない場合 `blocked` である
   * S->T で T が存在しない場合、 pi は 状態S でブロックされる
 * process S でブロックし続けまた将来的に何の操作も発生しない場合、デッドロックしている。
 * pi が S でデッドロックしている場合 S は deadlock state と呼ばれる。
 * 取りうる state が deadlock satte でないように制限することで、デッドロックは防げる
   * S->T で T が deadlock state でない場合 は safe state

## 4.3.1 Reusable REsource Graphs

 * プロセスリソース graph
  * serially reusable resource (SR) をグラフ化する
  * 図示すると単純だけど、graph として式化すると大分ややこしい印象

```
    <N, E>
    N                           # N は nodes を示す
    E                           # E は edges を示す

    π = { p1, p2, p3 ... pn }  # π は Processs nodes の集合
    ρ = { R1, R2, R3 ... Rm }  # ρ は Resource nodes の集合

    # プロセス同士、またはリソース同士のグラフは形成されない

    Rj = { .... }               # Resource node は tj の要素を持つ
```    

 * エッジの向きでリクエストか割当かを表記する
 
``` 
    e = (Pi, Rj)                # Request edge を示す    Pi->Rj
    e = (Rj, Pi)                # Assignment edge を示す Rj->pi
                                # Request edge, Assignment edge 共に E の中に含まれる
```

 * |(a,b)| ノードa から ノードb へのエッジを考える
   * Rj は tj 以上の assignment をしない (Rj が tj の要素しか持たないので)

```
    Σi |(Rj, pi)| ≦ tj          # 任意の pi へ割り当てた Rj の和は tj 以下
    |(Rj, pi)|+|(pi, Rj)| ≦ tj   # Request edges + Allocation edges の和は units の数を超えない
```

 * Request => Acquisition => Release

> Note that processes are nondeterministic; subject to preceding restrictions,
> any operation by any process is possible at anytime

プロセスの(挙動は) 比決定的

### 4.3.2 Deadlock Detection

> Theoram 1. The Deadlock Theoram
> S is a deadlokc state if and only if the reusable resource graph of S is not completely reducible

S が completely reducible でないことは S がデッドロックの状態であることと同値

 * 必要条件の証明
   * S は deadlock state である かつ pi が S の中でデッドロックされている
   * S -> T する T について、 pi が T でブロックしている
     * graph reductions は process operations に相当する
     * 最終的な irreducible な状態は pi をブロックする

 * 十分条件の証明
   * S が completely reducible でないと仮定する

> Theoram 2. The Cyble Theoram
> A cycle in a reusable resource graph is a necessary condition for deadlock

リソースグラフが循環している状態は、デッドロックの必要条件

> Theoram 3.                         i
> If S is not a deadlock state and S -> T, then T is a deadlock state
> if and only if the operation by pi is a requeste and pi is deadlocked in T.

S がデッドロックした状態でなく、S->T があり、T がデッドロック状態であることは
pi がリクエストを出していて、T でデッロックしているのと同値

> オペレーティングシステムの基礎
> preemptive resource の割当てではデッドロックは起こらない

CPUが該当する。リソース獲得の競合が発生した場合でも、リソースの解放(preemption)を任意に起こせるので。
ただし preemption のコストが高くスラッシングが発生するような状況ではデッドロック状態に近似する


### 4.3.4 Recovery from Deadlock

 * 1. process terminations
   * デッドロックになった最初のプロセスを強制終了。最悪全てのプロセスを止める必要。
 * 2. resource preemption
   * デッドロックしたプロセスにリソースをpreemption する
   
 * プロセス停止のコストが低いものを止めるのが実践的な方針
   * プロセスの優先度
   * プロセスをやり直しして、現在の状態になるまでのコスト (rollback)
   * 外的なコスト (誰が利用しているジョブなのか)
   
 * terminate process
  * => release resoufce
  * => reduce graph
  
 * デッドロック状態S から復帰するためのコストは
   * pi を destroy するコスト
   * pi を 止めて、その状態から復帰するためのコスト
     * どのプロセスを選択するかに依る
   
用語 outstanding requests 未処理のリクエスト

## 5. Main Storage Management

 * fixed partition
 * variable partition
   * fragmentation と compaction
 * Overlay
 * Single Segmentation
 * Multibple Segmentation
 * Paging
   * page frames ... 物理メモリの分割単位
   * pages       ... namge space の分割
