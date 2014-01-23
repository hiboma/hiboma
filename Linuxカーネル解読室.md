# 序章

## 0.1 Linuxカーネルとは

 * __イベント駆動型__
   * システムコール
   * 割り込み

## 0.1.1 UNIX の互換実装

 * __モノリシックカーネル__
 * __マイクロカーネル__
   * Mac OSX もだよ
     * XNU Kernel ___XNU's Not UNIX___
       * Mach microkernel
       * The BSD Layer (FreeBSD由来)
       * libKern
       * I/O Kit
 * マイクロカーネルの実例は???

#### System V の本

![71k140k5bfl _ss500_ gif](https://f.cloud.github.com/assets/172456/1985620/2e21f650-8441-11e3-9865-62d7b7871f15.jpeg)

#### Solaris Internals

![51jyl26gg-l](https://f.cloud.github.com/assets/172456/1985642/8275fcd8-8441-11e3-8eea-1f6a901dc27b.jpg)

#### 4.3BSD

![41okjaranfl _sl500_aa300_](https://f.cloud.github.com/assets/172456/1985643/84f1a764-8441-11e3-8a4a-521bbbf57f22.jpg)

## 0.2 Linuxカーネルのソースコード

 * バニラカーネルのダウンロード
   * https://www.kernel.org/
 * CentOS の kernel SRPM
   * http://vault.centos.org/ から探す
   * http://vault.centos.org/6.5/os/Source/SPackages/kernel-2.6.32-431.el6.src.rpm
 * CPUアーキテクチャの整理
   * ぎょーむ的には i386, x86_64 を中心に見る事になるのを確認

## 0.3 Linuカーネル機能の概要

## 0.4 カーネルプリミティブ

 * ___プリミティブ___ とは?
 * ___非同期___ 

### 0.4.1 プロセススケジューラ

__マルチタクス環境__

 * ___並列に実行されます___ と書いてるけど、マルチコア/マルチCPUが前提になっていて、並行の話が無いような
   * ___parallel___, ___concurrent___ を整理しよう
   * https://twitter.com/tnmt/status/318211278810275840
 * プロセスが実行される とは?
 * 公平性、応答性、スループット
   * どういうアルゴリズムにしたら理想なんだろうかを考えてみる (難しいけど)

### 0.4.2 割り込み処理と遅延処理

 * ___割り込み___
   * ___Interrupt___
   * メタファとして、仕事中に急に呼びかけられて中断させられるという説明
   * コンテキストが変わる
 * ___ハードウェアからの事象___ とは? 何か例が無いと分かりにくそう
   * Ethernetカードにパケットが届いた
    * => パケットをコピーしないといけない
   * HDDの読み取りが終わった
    * => バッファにコピーしないといけない
   * マウス、キーボード
    * => スクロール、クリック、打鍵に応じて描画やキーボード入力
 * ___ソフト割り込み___
   * _割り込み処理を遅延させる仕組み_
 * ___割り込みレベル___
   * 低い優先度の割り込みをマスクする
   * 優先度の高い/低いの説明