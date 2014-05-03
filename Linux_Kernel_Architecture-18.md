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


