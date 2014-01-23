# The design of the UNIX operating system

 * 1986年
 * based on UNIX System V Release 2 supported by AT&T, with some features from Release 3.
   * ソースが無い!

## 1.3.2 Processing Environment

> A program is an executable file, and a process is an instance of the program in execution

## 2.1 ARCHITECURRE OF THE UNIX OPERATING SYSTEM

 * ___trap___ によって kernel level (カーネルモード) に移行している
 * swapper プロセス
   * 古典UNIXでは「スケジューリング」は、プロセスのメモリをメインメモリ/スワップメモリで交換することを指していた様子
     * 6th の sched
   * モダンUNIXではCPU割当のスケジューリングを担うものとして意味になる
     * swapper は、文字通り プロセスの swap を担うもの
     * ___preeempts___ ___quantum___ という単語がでてくる
 * 割り込みが ___special functions in the kernel___ と表現されている
 * カーネル実行パス、といった表現はまだ無い

## 2.2.1 An Overview of the File Subsystem

 * ___index node___ => inode だという説明がでてくる

## 2.2.2 Processes

 * ___a process on a UNIX system is the entity that is created by the fork system call___
   * プロセスは fork した実体である、という捉え方
 * ___region___ ___region table___
   * ___A region is contiguous area of a process's address___
   * ___address space___
   * linuxでいうところのmm_struct 的な物?
     * 属性の管理
      * shared か private の属性をもつ
      * textか、data か (実行可能か、読み取り可能、書き込み可能か )
   * forkした際に region を share することで Copy on Write 的なことができると書いてある
      * Copy On Write 的な手法に言及している ( CoW の名前はでてきていない )
 * u 変数 => Linuxの ___current___ と一緒の使い方ができる
   * 6thと同じで struct user を指してるはず
 * bss とは? => ___block started by symbol___ IBM 7079 というのが由来らしい
 * システムコールのスタックは、必ずスタック最上位に位置する
   * システムコールの引き数をスタックに積むから当たり前か
 * ユーザーモードの時は カーネルスタックは NULL

## 2.2.2.1 Context of a process

 * _Context_ is
   * state
   * text
   * value of its global user variables and data structures
   * registers
   * process table slot
   * u area
   * user and kernel stack

これらのデータを切り替えることを _context switch_ と定義している

## 2.2.2.3 State transitions

 * kernel mode で running なプロセスは他のプロセスから preempt されない
  * 特定の状態で ___non-preemptive___ ではある
  * kernel mode を non-preemptive にすることでデータの一貫性を保ち、排他制御の問題を解決する
 * user mode のプロセスは preempt される
 * kernel running => sleep になる際に context switch 可能になる

Linux では CONFIG_PREEMPT を有効にすると kernel mode で running な場合にも preempt することができる。
プロセスのタイムスライスをより厳密に管理できるので、リアルタイムOS向けの仕様なのかな?

## 3.1 BUFFER HEADERS

 * ?: bufferのサイズはブート時に固定なのだろうか?
 * ___The buffer is the in-memory copy of the disk block___
   * バッファはディスクブロックと一対一で対応する。デバイス番号とブロック番号で一意

 * バッファの状態
   * locked, busy, free, unlocked
   * バッファを再利用する際にはバッファの内容をディスクに書き出す必要がある ___delayed-write___
     * dirty なバッファですな

## 3.2 STRUCTURE OF THE BUFFER POOL

 * アルゴリズムは LRU (Least Recently Used)
   * 最近最も使われていないデータを先に捨てる
     * head に近い => 最近使われてないバッファ
     * リストに返す時に tail に繋ぐ
 * 起動時にフリーリストに繋がれる

LRUの逆でMRU Most Recently Used というアルゴリズムもある。

 * フリーリスト (6th, 4.3BSDだとbfreelist) から探したバッファは B_BUSYとしてマークされる
 
## 3.5

 * buffer の仕組みがあることで、ファイルシステムの一貫性( ___file system integrity___ ) を保ちやすくなる
   * ディスクのブロックがメモリ上にただ一つ存在してかつ排他的に管理されているため。
   * はじOS にも同じ記述

## 4 INTERNAL REPRESENTATION OF FILES

 * iget + iput + bmap = namei
 * alloc, free
 * ialloc, ifree
 * getblk, brelse, bread, breada, bwrite

## 6.1 PROCESS STATES AND TRANSITIONS

プロセスの状態遷移図。状態がどのようなイベントで遷移するのかを足す必要がある

 * 3. TODO:
   * ソース上でどう表現されているのか
 * 7. kernel mode から user mode へ復帰するさいに preempt して context switch する


## 6.2.1 Regions

 * System V は 仮想アドレス空間を ___region___ に分割する
   * Linux は ___memory region___ と呼んでる。 vm_area_struct と同義
 * ___pregion___
   * a private process region table
   * Linux の mm_struct かな
   * pregion の各エントリは read-only, read-write, read-execute などの属性を持つ
   * ファイルテーブル(デスクリプタのテーブル) = private と inode = shared とのアナロジーだという説明がある
 * regsion の考え方は ハードウェアでのメモリ管理の実装とは独立している
   * メモリが ___page___ に分割されるか ___segment___ に分割されるか

## 6.2.2. Pages and Page Tables

UNIXに限定した話でないと前置き。ページでメモリ管理するハードウェアのお話。

 * 物理メモリをページに分割して管理する
   * ページサイズは 512 ~ 4096 bytes
   * メモリのアドレスは "ページ番号 + バイトオフセット" で特定できる
     * 2**32 の物理メモリがあった場合 => 2**22 のページ番号と 10bitのバイトオフセットでアドレッシングできる
     * ブロックデバイスの ブロック番号 + オフセットのアナロジと説明
 * ページでのメモリ管理の利点
   * 物理メモリを連続して割当る必要がない / また順番も考慮しなくてよい
   * フラグメント化を減らせる
 * page table で 論理ページ番号 => 物理ページ番号の管理をする
   * page table のエントリは 読み書き可能かといった情報をもつ (マシン?アーキテクチャ依存)
 * プロセスが仮想アドレス空間を外れたアドレスを指すとハードウェアが exception を出す
   * machine/trap.c の T_SEGFLT か? ( プロセスには SIGSEGV を飛ばす )
 * write-protected text region (読み取り専用メモリリージョン) に書き込もうとすると exception を出す
   * machine/trap.c の T_PROTFLT か? ( プロセスには SIGBUS を飛ばす )

segmentation fault, page fault かな?

## 6.2.3 Layout of the Kernel

## 6.4

 * 割り込みハンドラはプロセスコンテキスの静的なデータを変更することは、ふつーやらない
   * 動的なデータ (プロセスのリンクリスト、ロック、セマフォ、sleep待ちのwakeup) などを扱う、でいいのかな?

## 6.4.1 Interrupts and Exceptions

 * ___interruput vector___ 割り込みベクタの説明
 * 割り込みハンドラのスタックをカーネルスタックで扱う実装と、グローバルな割り込み用スタックを用意する実装とがある
   * グローバルな割り込みスタックを使うと context switch の必要せず戻れる???
 * システムコールの呼び出し中にディスクからの割り込みがあってタイマ割り込みがさらに入る、というスタックの図がある
   * 三段組になる
   
## 6.4.2 System call

> a special case of an interruput handler

 * 擬似コードの内容が4.3BSDと大体一緒なので、実装は4.3BSDを読んでおけばよい
 * MS-DOSは ファンクションリクエスト と呼ぶようですな
 * システムコールへの引き数の渡し方
   * パラメータ渡し
   * レジスタ ... Linux
   * スタックに積む
 * システムコールの返り値、エラー通知の仕方
   * 成功時
     * PS レジスタの carry bit をクリアする
   * 失敗時
     * PS レジスタの carry bit を立てる
     * レジスタ0 に errno を入れる

## 8 PROCESS SCHEDULING AND TIME

 * カーネルモードからユーザーモードに戻る時に優先度を再計算する
 * 定期的にユーザーモードプロセスの優先度を再調整する
 
### 8.1 PROCESS SCHEDULING

 * UNIX のスケジューラは ___round robin with multilevel feedback___
   * ラウンドロビン + 多段フィードバック のアルゴリズム で実装されている
   * UNIX とあるけど、ここでは System V だけ?
 * user proirities, kernel priorities とに分けられる
   * kernel priorities は、sleep 状態から wakeup した際の優先度を指す
     * user-level prioritiy のプロセスは カーネルモードからユーザーモードに戻る際に preempt される
     * kernel-level prioritiy のプロセスは sleep する際に preempt される
   * I/O処理待ちのキューは高い優先度が当てられている
     * すでにバッファを獲得している。
     * リソース(バッファ等)を早く解放することで、他プロセスをブロックさせることが少なくなり、 context switch も減ってスループットを向上できる
  * タイマ割り込みのハンドラでユーザーモードの優先度が再計算される
    * 一つのプロセスがCPUを占有 ( 他のプロセスを starvation させない )させないように。
   
### 8.1.1 Algorithm

 * 最も優先度の高い ___ready to run and loaded in memory___ なプロセスが preempt される
 * 優先度の高いプロセスが複数ある場合は、 round robin 方式で、キューでの待ち時間が一番長いプロセスに preempt される
 
### 8.1.2 Scheduling Parameters

 * 低レイヤでリソースを掴んで sleepしているプロセスは 他のプロセスを"ブロック"しやすい
   * コンテキストスイッチの原因になる
   * ボトルネックになってしまうので、高い優先度をあててリソースの解放を促し スループットの向上を図る
   * 優先度はユーザーモードに戻る際に再調整される ( 高い優先度のまま戻る分けにいかん )
 * タイマ割り込みハンドラは 1秒ごとに優先度調整をする
   * 優先度調整されることでスケジューリングを起こす状態を作る

4.3BSD では ___hardclock(), softclock()___ が用意されている

## 9.2 DEMAND PAGING

 * ___restartable instructions___ と ___pages___ の組み合わせ = page fault (demand paging) の仕組み
   * やり直しできる命令セット
 * ___locality___
 * ___working set___
   * 最後に参照した n 個のページ群
 * ___window of the working set___
   * n を指す
   * working set に含まれていないページを参照 => ページフォルトする、という考え方
  
オペシス本 6.6.5章あたりに にも書かれていること

## 9.2.3 Page Faults

 * Validity Fault Hnadler, Protection Fault Hahndler 二つのページフォルトハンドラを実装する
   * VAX では Validity Fault と Protection Fault はそれぞれ別のベクタで管理されている
   * x86ではベクタは一緒で、スタックに載った error code の内容で判別する
 * Protection Fault Hahndler
   * 4.3BSD, 4.4BSD では Protection Fault は SIGBUS 呼び出して終了。CoWが無いので

## APPENDIX - SYSTEM CALLS

昔話系

 * mknod(filename, 0400000, device) でディレクトリを作成することが可能だった (今のLinuxは x )
   * レギュラーファイルは作成不可
   * rename(2), rmdir(2), mkdir(2) は存在しない
     * ディレクトリを open(2) して read(2) して中身を直接読み取る事も可能( Linux x )

