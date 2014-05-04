# 18 Page Reclaim and Swapping

page を evict する方法

 * swapout 
 * mmap されたページを pageout = **syncronize**
 * file backed だけど内容書き換えれないページを破棄

**page reclaim**

## 18.1

 * 古典UNIXでは **swapping** はプロセス全部を追いやる事を意味していた
 * 今日ではページ単位で書き出す
   * fine-grained swapping out of process data

## 18.1.1 Swappable Pages

 * MAP_ANONYMOUS なページ
   * file と結びついてない。もしくは /dev/zero
   * mmap で作られた stack
 * MAP_PRIVATE
   * malloc で heap
   * IPC用に使われるページ。 shared memory
 * カーネルのページは **絶対に** swapout されない

##  18.1.3 Page-Swapping Algorithms

**FIFO**

```
      New                 Old
[] => [][][][][][][][][][][] => [] swapout 
 \
  \_ page fault

```

 * page がリンクリストになってる
 * page fault すると新しく参照されたページはリストの先頭に来る
 * FIFO のキューサイズを有限にしておく
 * キューの末端のページが *drop off* して swapout される
 * 再度必要になったら page fault で page を読み込んで先頭に配置する

**Second Chance**


```

[0] で push

[0] => [0][1][0][1][1][1][1][1][1][1] => [0] swapout 
 \                                 /
  `<------------------------------`

```

 * ハードウェア管理のビットを追加
 * 参照されると 1
 * kernel がビットを落とす
 * リストの末尾にくると、ビットが立っていたらビットを落として FIFO の先頭に配置
   * new page として扱われるのと一緒
 * ビットが立っていなかったら swapout される

page が頻繁に参照されているかどうかを扱える

## LRU Algorithm


1## 18.2.1 Organization of the Swap Area

 * ファイルシステム無しのパーティションでも動作
 * ファイルシステムで固定長のファイルでも動作
 
**slots**
 
 * と呼ばれる単位に分割される
 * ページがおさまるように 4KiB

**clustering**

 * 連続したページをまとめて扱う
 * 256 page

priority

 * 複数の swap 領域の priority が同じ場合は round robin で書き込み
 
 * どのページがどの swap パーティションにあるかをメモリに保持する
 * used/free を bitmap で管理

mkswap(3), swapon(3), swapon(2)

## 18.2.2 Checking Memory Utilization

swapout する際にメモリ使用量を診る

 * kswapd が定期的にみてる
 * **direct reclaim**
   * buddy システムやバッファでページを必要とする際に swapout
 * どうしても足らなきゃOOM

## 18.2.3 Selecting Pages to Be Swapped Out

 * rough-grained LRU
 * zone ごとに 2つの LRUリスト
   * active
   * inactive
 * 古い実装。今は Split LRU

## 18.2.5 Shrinking Kernel Caches

 * **shrinkers**

## 18.6 Page Reclaim

 * **swap policy**
   * どのページを swapped out するべき?
 * **page reclaim**
   * free した page をすぐに利用

## 18.6.1 Overview

 * カーネルの実行パスで page reclaim** する **direct page reclaim** と kswapd
   * どちらも shrink_zone を呼び出す
 * NUMA では kswapd は 各 node にいて zone の面倒を見てる

 
  