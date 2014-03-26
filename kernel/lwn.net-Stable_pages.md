g# lwn.net Stable pages

 * http://lwn.net/Articles/442355/
 * http://yoshinorimatsunobu.blogspot.jp/2014/03/why-buffered-writes-are-sometimes.html で紹介されている
 
> 1. READ MODIFY WRITE
> 2. WRITE() MAY BE BLOCKED FOR "STABLE PAGE WRITES"
> 3. WAITING FOR JOURNAL BLOCK ALLOCATION IN EXT3/4

2 で Stable pages が問題になるケースとのこの

## writeback と read-only ページの仕組み

 * プロセスが file-backed (mmap, write, PG_private ?) なページに write すると
   * dirty とマークされる
   * backing store に書き込まれないといけない
 * writeback する際に under writeback (PG_writeback) としてフラグがたち read-only にマークされる
   * I/O にキュー される
 * page の write-protection は page の内容の書き換えを防ぐためものでない
   * 追加の writeback を検知するための仕組み
   * writeback 中に page の書き換えを許可している
   
だいだいいい感じに動く

 * ワーストケース ? でも ...
   * 最初の writeback の I/O が始まる前に page 書き換えが起こると
   * 直近に書き換えた内容が、最初と次の I/O で redundant disk (RAID?) に キューイングされる

## writeback 中の page 書き換えがよろしくないケースもある

 * 整合性チェック integrity checking できるデバイスで、ディスクに書き込む内容と 
カーネルの pre-write checksum を比較する
   * カーネルが checksum を計算したとあとに page の内容が書き変わると 疑似? write w error となってしまう
   * Software RAID がコレでコケる

ということでファイルシステムで ___stable page___ という仕組みで writeback 中に page の内容が書き変わらんことを保証しよう

## http://lwn.net/Articles/429295/ のパッチ

 * integrity check が使われるケースでは writeback する前の page のコピーを取っておく
  * コピーについてはユーザ空間では気にする必要ない
  * ページの内容が書き変わる事があってもコピーを参照して integrity check できる
  * integrity check での問題は解決したけど コピーはコスト高い

もっといい方法無いの?  

## http://lwn.net/Articles/442156/ のパッチ

 * writeback する page に write する際は、writeback が終わるまで待つだけにする
   * 先に書いたように writeback する際に page は read-only にマークされる
   * 加えて writeback 中であることを示すフラグがある
 * ___page_mkwrite___
   * read-only page が writable になったことを通知する
   * vm_operations_struct の .page_mkwrite を指す
 * .page_mkwrite を実装してないファイルシステムもある
   * その場合 ___generic_empty_page_mkwrite___ を使う
     * page をロック、 write back が終わるまで待つ、ロックしたページを返す
   * ext2, ext4, FAT で似たような機能のをつくった
   * Btrfs は内部で実装してて必要無かった
   * ext3 は journal との兼ね合いで実装むずかった
     * ext3 を侵害する (めっちゃ変える?) ようなパッチは歓迎されない。で、 ext3 では stable page サポートが無い

## アプリを遅くしてしまう懸念

いいこと尽くめでなくて問題あり

 * ファイルの同じ箇所に書き込みまくるアプリの場合
   * ___stable page___ 実装前は連続した write でも 遅くなる事はなかった
   * 実装後は writeback で待たされるようになった
   * ベンチ取ったら12% のパフォーマンスデグレード
     * 好ましくない結果なのだけど、この問題にぶつかるアプリは少ないンじゃね？ってな合意でマージ
     * 稀
     
あれ、まさに MySQL ... ですよね
これの影響されるアプリに気がつかなかったから? といって存在無い訳でない

 * 数年してディストリビューションやユーザのによって開発されてから現実的な問題を生む
 * it's far too late to go back.  時既におそし〜
   * 問題の問いかけなのかな ?

----   

無効にするパッチ

 * http://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/commit/?id=1d1d1a767206fbe5d4c69493b7e6d2a8d08cc0a0
   * bdi_cap_stable_pages_required で挙動を変える

## CentOS6.5

デバイスが writeback 中に stable page を必要とするかの判定

```c
static inline bool bdi_cap_stable_pages_required(struct backing_dev_info *bdi)
{
	return bdi->capabilities & BDI_CAP_STABLE_WRITES;
}
```

wait_for_stable_page のソース

```c
/**
 * wait_for_stable_page() - wait for writeback to finish, if necessary.
 * @page:	The page to wait on.
 *
 * This function determines if the given page is related to a backing device
 * that requires page contents to be held stable during writeback.  If so, then
 * it will wait for any pending writeback to complete.
 */
void wait_for_stable_page(struct page *page)
{
	struct address_space *mapping = page_mapping(page);
	struct backing_dev_info *bdi = mapping->backing_dev_info;

    // デバイスが stable page を必要としないなら待たずに戻る
	if (!bdi_cap_stable_pages_required(bdi))
		return;
#ifdef CONFIG_NEED_BOUNCE_POOL
	if (mapping->host->i_sb->s_flags & MS_SNAP_STABLE)
		return;
#endif /* CONFIG_NEED_BOUNCE_POOL */

    // stable page で writeback を待つ
	wait_on_page_writeback(page);
}
EXPORT_SYMBOL_GPL(wait_for_stable_page);
```

blk_integrity_register で BDI_CAP_STABLE_WRITES がセットされる

```c
int blk_integrity_register(struct gendisk *disk, struct blk_integrity *template)
{

// ...

        disk->queue->backing_dev_info.capabilities |= BDI_CAP_STABLE_WRITES;

        return 0;
}
EXPORT_SYMBOL(blk_integrity_register);

```

drivers/md/dm-table.c や drivers/scsi/sd_dif.c で呼び出されている
integrity を担保する方法は CRC ? とかいろいろ方法がある様子