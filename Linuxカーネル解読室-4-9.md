# 4.9 POSIX タイマー

 * http://umezawa.dyndns.info/wordpress/?p=3174
   * サンプルコードを読むと使い方大体分かる
     * シグナルを選べる
     * シグナルの代わりにスレッドで通知
     * 複数のタイマをセットできる
 * http://linuxjm.sourceforge.jp/html/LDP_man-pages/man2/clock_getres.2.html

## 4.9.1 時刻管理

 * CLOCK REALTIME
   * 西暦年月日取得
 * CLOCK_MONOTONIC
   * システムの起動時を 0 とする経過時刻

## 4.9.2 インターバルタイマ

