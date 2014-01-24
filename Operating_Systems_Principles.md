# [本] Operating_Systems_Principles (1975,1984)

## Opacity ?

> commonly called "transparency" in defiance of that word's normal meaning
> the property of allowing users to remain unaware of all details they need not know
> all that lies beneath the interface provided by the system
>
> The most obvious accomplishment of an operating system is its presentation to the user
> of an interface much easier to use than that of the computing system
> P.4

> In providing a high level of interface, the operating system shields its user from
> more than just the computer's complexity.
>
> The point is that by creating a new interface, the operating system can continue to
> to function without apparent change,
> P.6

> The operating system always provides the only interface its users see. 
> The actual computer is hidden by it.
> P.9

書籍全体を通して、「インタフェースによって内部実装の複雑さ切り離してユーザーに見せるべき」と
いう考え方が一貫している

## Isolation ?

> The isolation provided by protection mechanisms aso contributes to the integrity of the
> high-level interface of the operating system. Only because these mechanisms exists can 
> users be sure that apparent errors in their own programs are not really dutto actionsof some
> other user

プロテクションの仕組みによって分離,他のユーザーのエラーが伝播しないようにする

## Task ?

> A task is the smallest unit of work that can actively contend for system resources
> P.14

タスク = リソースを奪い合うアクティブな最小の単位。
スケジューリングの対象 > プロセス、スレッド

> The task is the entity within the operating system which vies with other similar entities
> on the queue of tasks for resources, especially control of the central processor.
> P.14

* monitors => executives => supervisor と語彙の変遷
* concurrency, parallel ?

> concurrency: that is, more than one process can be executing within the same
> computing system at the same time. This is not to say that simultaneous operation
> is possible;

> parallel processing can only occur where there is a possibility of more than one
> instrution being executed at the same time, such as in a multiprocessing system

CPUの命令レベルで見ると複数の命令が同時に実行されうること == paralell
その条件としてマルチプロセッサ(マルチコア)なシステムが必要

## multiprocessing ?

> We define multiprocessing as the execution of 2 to n instructions in parallel
> on 2 to n central processors in a single computing system
> P.53

 * multiprocessing を 1台の計算機で 2-N の命令が 並列に 2-N の CPUで実行されること と定義する

## mutiprogramming ?

> mutiprogramming is the concurrent interleaved execution of programs in a single
> central processor

 * multiprocessing を プログラムが 1CPUで 並行/interleaved して実行される と定義する

## interrupt ?

> The interrupt is a vital feature which allows operations on various devices to
> go on in parallel and asyncronously and still be able to notify the supervisor
> that its services are needed

## reentable ? 

> A reentrable program or a directly accessed volume may be sharable
> P.44

 * リエントラントなプログラム = 共有可能
 * concurrent, parallel に実行可能?

## Virtual machines

P.59 仮想化についての記述がある。

## Types of Real-Time System

リアルタイムシステムを 2つに区分している

 * 1. the process control system
  * アナログ入力を受け取ってデジタルに変換 なんらかのフィードバックを返し状態をコントロールする
 * 2. the process monitor system
  * 観測するだけ

## Interruputs ?

> The interrupt is a vital feature which allows operating system on various devices to
> go on in parallel and asyncronously and still be able to notify the supervisor that
> its services are needed
> P.74

## Storage Protection

Storage は メインメモリを差している。要注意

> One of the key features needed in a computer to enable concurrent processing of
> several tasks is the ability to protect the main storage area assigned to one
> program from beign altered by another program

concurrent processing にはメインメモリの保護が必要と説く

## Error Recovery

ユーザアプリケーションで発生するエラーを二つに区分する

> The first kind is the violation of system architecture and/or programming restrictions

1. システムアーキテクチャ/制約の違反

 * システムコールの呼び出し
 * パーミッション
 * アドレス違反

> the second is the misuse of system resources, primarily I/O, which occurs when programmers
> do not violate system rules, but do misuse the system in such a way that they get unexpected
> or wrong results
> P.94

2. リソースの誤った使い方

 * メモリ
 * ディスクI/O, 容量
 * 帯域
 * comsumable resource の使い過ぎ?
 
## User Programming Errors

> The Operating System must anticipate the possibility of user programming errors. The greatest
> concern of the operating system designer is normaly that of prevention of accidental (and, occasionaly,
> deliberate) violation of system architecture and/or operating system or other-user address space.

 * ユーザ空間のプログラミングエラーを予期する
   * アドレス空間の保護

## Interfaces between User Programs and Operating System Services

> The nature of the operating system should not be apparent to the user of a language processor. To
> a certain point this can be acomplished. However, it is native to think that programmers of a high-level
> language can make the best use of the operating system facilities provided unless they understand the
> nature of these services and the way they are being implemented.

