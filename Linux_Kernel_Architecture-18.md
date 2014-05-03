# 18 Page Reclaim and Swapping

page を evict する方法

 * swapout 
 * mmap されたページを pageout = **syncronize**
 * file backed だけど内容書き換えれないページを破棄

**page reclaim**