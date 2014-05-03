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