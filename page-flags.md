
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
 * PG_locked
   * ページキャッシュに pin する
   * ブロック truncation されないようにする (削除?)
 * page_waitqueue(page)
   * ページが unlock されるのを待つqueue
 * PG_uptodate
   * ページの内容が valid であることを示す
   * read が終わった際に ページの内容が uptodate (2時記憶装置と同期) であることを示す
   * I/O エラーが起こった場合は除く
 * 