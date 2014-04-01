# 80386 Programmer's Reference Manual

## EXCEPTIONS AND INTERRUPTS

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