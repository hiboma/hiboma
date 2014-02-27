 
## struct backing_dev_info とは?

* アドレス空間の背後にある周辺機器(peripheral device)を __Backing store__ と呼ぶ (refs Linux Kernel Architecture p.957 )
* ふつーはブロックデバイスだけど、もちろんRAMベースもある。

backing store のメタデータを入れておくのが [struct backing_dev_info](http://lxr.free-electrons.com/source/include/linux/backing-dev.h?v=2.6.32#L60)

 * [bdi_init](http://lxr.free-electrons.com/source/mm/backing-dev.c?v=2.6.32#L651 ) で登録
 * [bdi_destroy](http://lxr.free-electrons.com/source/mm/backing-dev.c?v=2.6.32#L693) で解除

### struct backing_dev_info のメンバ

 * ra_pages 
   * 先読みするページの最大数を指定(readahead pages)
   * RAMだと先読みいらんし、ブロックデバイスだけで有効かな
 * capabilities 
   * ページを backing store と同期(write back)する際のポリシーなどを指定
   * ブロックデバイスだと必要だけど RAM だといらん 
   * mmap できるかなども指定するぽい   
   * [各種フラグ](http://lxr.free-electrons.com/source/include/linux/backing-dev.h?v=2.6.32#L200)
     * BDI_CAP_NO_ACCT_AND_WRITEBACK
     * BDI_CAP_NO_ACCT_DIRTY RAM backing store だとページが dirty かどうかの判定いらん
       * これらのフラグがどうやって利用されてるかが謎。
 * dev 
   * struct device 入れておく。 RAM backing store だと null 入れておkらしい
   
他にもいろいろ面白そうなメンバあるけど、ブロックデバイスじゃないと関係なさそうな空気   
