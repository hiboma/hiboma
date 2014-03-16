# 2.3 ハードウェア割り込み処理

## 2.3.1 割り込みの種類

#### 割り込み Intterupt

![](http://sourceforge.jp/projects/linux-kernel-docs/wiki/2.3%E3%80%80ハードウェア割り込み処理/attach/fig2-1.png)

 * External Interruputs 外部デバイスの割り込み
   * ネットワークカード、端末装置、SCSIホストアダプタ
 * IPI = Inter Processor Interrupts プロセッサ間割り込み
 * タイマー割り込み
   * ローカルタイマー
     * APIC ? 
   * グローバルタイマー
 * NMI = Non Maskable Interrupts
   * ハードウェアの故障などの通知

#### 例外 Exception

> このほか、割り込みによく似たものとして「例外」があります。割り込みが外的要因であるのに対し、CPUの動作自体によって引き起こされた事象の場合を「例外」と呼びます。

 * CPU内部で発生した事象
   * 0 除算, 数値演算例外, ページフォルト, ...
 * フォルト
 * トラップ
 * アボート

[例外と割り込み](https://github.com/hiboma/hiboma/blob/master/linux-0.0.1.md#例外割り込み) で復習しよう