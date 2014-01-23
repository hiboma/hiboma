* Computer Architecture and Implementation

* 1.

 * von Neumann model 1946
  * Princetonアーキテクチャ
  * Harvard アーキテクチャというのもあるらしい

 * memory, processor, I/O system の組み合わせ
   * `nested state machine`
   * memory   上の情報 ... `process state`
   * register 上の情報 ... `processor state`
     * processor state の save/restore による switch => context switch
     * OSのレイヤで見ると context swtich は プロセスのスケジューリング
     * general registers, dedicated registers
 * ALU `arthimetic and logic`
 * ISA `Instruction set architecture`
  * The ISA is the programmer's view of the computer
    * ハードウェアによって実装
  * interaction with memory
  * I/O capbilibties
  
 * 命令の実行は3つのステップのサイクル
  * fetch => decode => execute
  
* 1.2.2 INSTRUCTION INTERPRETATION CYCLE

* 1.2.3 LIMITATIONS OF THE VON NEUMANN INSTRUCTION SET ARCHITECTURE  
  
 * self-modifying code
   * 配列のインデクシング?
   * => インデックスレジスタのこと
   
 * modular programming was unknown
   * base register が無い
   
 * program counter is and implemented register
  * 単純に加算するだけの PC ということ ? 
  * => architected program counter: stored/restored 可能

* 1.3 HITORICAL NOTES

 * TODO: Indexing ? インデックスレジスタ?
  * Mark 1
  
/_/howm/images/Computer_Architecture_and_Implementation.txt-20130303031724.png
  
    * Ferannti Corp , 1946-1949
    * virtual memory !

 * Subroutines の実装
   * EDSAC
   
/_/howm/images/Computer_Architecture_and_Implementation.txt-20130303031644.png
   
   * プログラムカウンタを save/restore する命令が必要
     * `programm counter became architeced, permitting its contents to be saved and restored`
     * von Neumann ISA ではプログラムカウンタを操作できない(単純にインクリメントするだけ) サブルーチンを実行できない
     
* 3. INSTRUCTION SET ARCHITECTURE

* 3.0 INTRODUCTION

> Functions and data that are provided in the ISA called "architected"
> Functions and data that are provided by programming "programmed"

 * ISAによって提供される => 設計

## Interrupts and Exceptions

 * Internal, Synchronous, Asyncrnous のおなじみの区分。
 * サブルーチンのデザインと似たところがあるが
   * ステートの保存、パラメータ渡しなどは使われない => 割り込みのタイミングが予期出来ないので。
   * prcoessor state, process state の退避は使われる

 * von Neumann の ISA では割り込みはサポートできない
   * リターンアドレスの保存の問題のため
   * process state ( メモリ ) もしくは processor state ( レジスタ ) に保存できる

 * 命令がパイプライン化されている場合、割り込みはまた別の問題を抱える => 6章
 
## SAVING STATE

実行時の状態を退避しておく

 * サブルーチンの呼び出しと同じ様に、割り込み時にプログタムカウンタを退避する
  * ハードウェアスタック or 専用レジスタ への退避
  * 専用レジスタは割り込みをネストして扱えない制約。初期のアーキテクチャ。
  
## INDENTIFICATION OF INTERRUPT SOURCE

割り込みをかけたソースを特定する方法

 * ポーリング
   * ポーリングをかけるオーダーは 割り込み優先度のオーダーになる??
 * vectored interruput 割り込みベクタ
   * ソースが割り込みのシグナルと一緒に識別子も送る => ベクタを特定できる
   
## RESTORING STATE

状態の復帰

 * プログラムカウンタや process/processor state の復帰
 
## OTHER CONSIDARATIONS

 * `restart`
   * 割り込みがかかった命令からのやり直し、
 * `continutation` 
   * 命令実行の状態を保存しておいて、再開できる
   
ページフォルトハンドラを実装するのに必要

 * 優先度をもうけて割り込みがネストする場合に対応する
   * 優先度の低い割り込みがキューイングされる。
   * (プライオリティ順にキューイングされるだけで FIFOなキューとして用意されるのではない

 * マスカブル
 * ノンマスカブル

* 4. MEMORY SYSTEMS

* 4.2 PGED VIRTUAL MEMORY

 * http://www.cs.utexas.edu/~witchel/372/lectures/15.VirtualMemory.pdf
 
 * page fault rate
  * ページフォルトを起こす割合 (ランダムに分配 = distribution した場合)

        size of real memory
  1 - ----------------------
      size of virtual memory

  * 実際には局所性が作用するので、より小さい値を取る (≒キャッシュヒット率)

        number of references found in real memory
  1 - ------------------------------------------
            total number of references

  * Spartial Locality 空間局所性
    * instruction-address stream
    * (条件分岐が無い限り)命令はアドレス順に実行されていくので空間局所性が高い
    * `look ahead` ... 先読み
  * Temporal Locality 時間局所性
    * data-address stream 
    * 一度利用したデータは再利用される可能性が高い。ループの中など。
    * `look behind`

  * Direct Translation
    * Page Table によるアドレス変換。
    * アドレスサイズが大きくなるとページテーブルのサイズも大きくなるので効率が悪い
  * Multilevel Direct Translation 多段ページテーブル
    * x86のページディレクトリ
  * Inverted Translation 逆引きページテーブル
    * Hash を使う, corrision
    * page name (仮想アドレスの上位ビット) をハッシュ化して、ページテーブルのインデックス番号にする
      * 
    * ハッシュが衝突するので linked list
      * linked list を辿って一致するエントリが見つからない場合、ページフォルト
      * PowerPC 32bit http://www.freescale.co.jp/doc/MPCFPE32BJ_R1a.pdf

    
displacement ... 変位。オフセットと同じ意味で使われている
