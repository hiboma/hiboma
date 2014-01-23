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

## 0.3 Linuカーネル機能の概要

## 0.4 カーネルプリミティブ

 * __プリミティブ__ とは?

### 0.4.1 プロセススケジューラ

__マルチタクス環境__

 * ___並列に実行されます___ と書いてるけど、並行の話が無いような
   * ___parallel___, ___concurrent___
   * https://twitter.com/tnmt/status/318211278810275840
 * プロセスが実行される とは?
 * 公平性、応答性、スループット
   * どういうアルゴリズムにしたら理想なんだろうかを考えてみる (難しいけど)

### 0.4.2 割り込み処理と遅延処理

 * ___Interrupt___