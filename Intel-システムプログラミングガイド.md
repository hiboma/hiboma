# IA-32 インテル アーキテクチャ ソフトウェア デベロッパーズ マニュアル 下巻-システムプログラミングガイド.pdf

 * "CPL" Current Privieage Level
 * "DPL" Descriptor Privieage Level
 * IDT
 * IDTR IDT register (1個しか無いよ)
   * LIDT( Load IDT) , SIDT (Set IDT)
   * IDT はリニアアドレス空間のどこに常駐してもかまわない。8バイト

![](https://f.cloud.github.com/assets/172456/2227492/576344f4-9ac3-11e3-836f-46180e2bd94d.png)

![](https://f.cloud.github.com/assets/172456/2227494/5e59844e-9ac3-11e3-970e-dfdd9f43017d.png)


![](https://f.cloud.github.com/assets/172456/2227495/5e68cd1e-9ac3-11e3-808c-8b1bc168fb5d.png)

 * "CR0 ~ CR"4 Control register 制御レジスタ
   * CR0 PG(Paging 31bit) ... ページングの enable / disable
   * CR0 PE(Protection Enabled?) ... 保護機能
   * CR4 PSE(Paging Size Extenston 4bit)   ... ON にすると 4MBのページ、clear すると 4KB のページ
   * CR4 PAE(Physical Page Extenston 5bit) ... 物理アドレス拡張 36bit (64GB) の物理アドレスでページングできる
      * 他にも PSE-36機能というのが Pentium3 から導入されてて使える
      * CPUID命令 で確認できる
 * "RPL" Required Privilege Level
 * "TLB" Translation Lookaside Buffer (プロセッサ内のデバイス)
   * ページディレクトリ, ページエントリのキャッシュ
   * `バスサイクル`を要求しない
 * "NMI" Non Maskable Interrupt
 * "IF"フラグ STI(割り込みイネーブルフラグセット), CLI(割り込みイネーブルフラグクリア)
 * PUSHF, POPF フラグをpush/pop

## TSS Task State Segment

タスクの実行環境を退避/復帰させるのに使う

 * general register
 * segment register
 * EFLAGS
 * EIP
 * "特権レベル0,1,2 のスタックセグメント"のセグメントセレクタ+スタックポインタ
 * LDTのセグメントセレクタ
 * ページテーブルのベースアドレス

Linux では TSS は使わずに struct tss_struct に退避させる

## ページング

ページングできるセグメント,テーブル

 * コードセグメント
 * データセグメント
 * スタックセグメント
 * システムセグメント
 * GDT
 * IDT

 * Page Directory(PDE 2**10) has Page Tables (PTE 2 ** 10) , Page Tables has Pages
   * Page Table Entry
     * 存在しているかどうか(0bit) => 存在していない場合にアクセスするとページフォルト例外
      * OSが管理するbit

 * デマンドページ、仮想メモリ => 共有メモリ
 * 論理アドレス(farポインタ) = セグメントセレクタ+オフセット

![](https://f.cloud.github.com/assets/172456/2227490/52134ada-9ac3-11e3-9715-4f18d69850c5.png)

 * フラットモデル => Linux

![](https://f.cloud.github.com/assets/172456/2227491/56f18030-9ac3-11e3-91dd-9f5e7e2c2fdd.png)
 
 * 保護されたフラットモデル ( proctected flat model )
 * マルチセグメントモデル
   * ハードウェア依存レベルが高い感

 * セグメントとページングは独立して扱える
 * 論理アドレス => リニアドレス = ( ページング ) => 物理アドレス
 * セグメントセレクタ => セグメントディスクリプタ
 * IA32アーキテクチャのスタックは常に下方に伸張する
 * ブレークポイント
  * INT 3 を埋め込み、例外を発生させる
