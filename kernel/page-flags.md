## include/linux/page-flags.h

 * PG_reserved
   * swap out されない
   * 存在しないこともある empty_bad_page
 * PG_private
   * ページキャッシュのページに立つフラグ。
   * ファイルシステムのデータ? を含む場合
   * private allocations ?
 * PG_locked
   * I/O の前にセットされて
   * クリアされるのは writeback が始まるとき or read が終わった時
 * PG_writeback
   * writeback が始まる前にセット、終わった時にクリア
   * ディスクに書き出し中ということ ( see. shrink_page_list )
 * PG_locked
   * ページキャッシュに pin する
   * ブロック truncation されないようにする (削除?)
 * PG_reclaim
   * `/* To be reclaimed asap */`
   * なるはやで reclaim されるページ (see. shrink_page_list )
 * page_waitqueue(page)
   * ページが unlock されるのを待つqueue
 * PG_uptodate
   * ページの内容が valid であることを示す
   * read が終わった際に ページの内容が uptodate (2時記憶装置と同期) であることを示す
   * I/O エラーが起こった場合は除く
 * PG_referenced, PG_reclaim
   * 無名ページ、ファイルのページキャッシュの再利用際に使われる
 * PG_error
   * I/O が起こったことを示す
 * PG_arch_1
   * アーキテクチャ依存
 * PG_highmem
   * カーネルの仮想アドレスに永遠にマップされない
   * I/O するには kmap する必要がある
   * struct page は常にカーネルの仮想アドレス空間にマップされる???
 * PG_buddy
   * ページがフリー(未使用?)、buddyシステムにある
 * PG_hwpoison
   * ハードウェアの故障(?)で壊れたページ
   * マシンチェックで不正なECCビット
   * machine check を引き起こすので使ってはいけない
 * PG_compound
 * PG_swapcache
 * PG_unevictable
 * PG_mlocked

----

 * PageLocked
 * PageSwapBacked, SetPageSwapBacked
   * tmpfs, anon, ram, ...  ページの backing store が swap
   * !PageSwapBacked   .... page_is_file_cache
 * SetPageDirty
 * SetPageSwapCache, ClearPageSwapCache
 * SetPageReclaim

 * page_mapped
   * &(page)->_mapcount >= 0

----

## vm_area_struct

 * VM_LOCKED
   * アドレス空間がロック。mlock(2)