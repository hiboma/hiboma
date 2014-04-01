# 80386 Programmer's Reference Manual

## EXCEPTIONS AND INTERRUPTS

古い本なので SMP, APIC の話は無い。素朴で理解しやすいね

 * 割り込み
   * INTRピン
 * NMI割り込み
   * NMIピン
 * 例外
   * faults, traps, aborts
   * INTO, INT3, INT n, BOUND

## 9.1 IDENTIFYING INTERRUPTS

 * 0 〜 31
   * NMI と例外
 * 32 〜 255
   * 割り込み
   * 割り込みコントローラー(PIC 8259A) を ACK してる際に ID(番号) を取れる

## 9.2 ENABLING AND DISABLING INTERRUPTS

 * NMIハンドラ 〜 IRET の間の NMI は無視される
 * EFLAGS の IF (interrupt-enable flag)
  * IF = 0 割り込み禁止 ... STI
  * IF = 1 割り込み許可 ... CLI

PUSHFで退避、 POPF/IRET で復帰

割り込みと例外の優先度表

```
HIGHEST  フォールト デバッグフォールト
         トラップ INTO, INT n, INT 3
         デバッグトラップ
         デバッグフォールト
         NMI 割り込み
LOWEST   INTR 割り込み
```

例外の方が NMI,割り込みより上位なのだなー

## 9.4 INTERRUPT DESCRIPTOR TABLE

IDT

 * IDTエントリは 8byte
   * IDTRレジスタでIDTのアドレスを取れる
   * LIDT で メモリから IDTR をセット
   * SIDT で IDTR をメモリにストアする