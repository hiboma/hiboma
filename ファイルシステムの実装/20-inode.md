
## ファイルシステムの root ディレクトリとなる VFS inode の初期化

 * root ディレクトリの VFS inode を割り当て、パーミッション, uid/gid, 各種operations を初期化する必要がある
 * ブロックデバイスベースのファイルシステムの場合は、デバイスからrootディレクトリのinode情報を読み取って適宜初期化する必要がある
   * ext2_fill_super, ext3_fill_super は sb_bread で super_block のブロックを読み込んでる [refs](http://lxr.free-electrons.com/source/fs/ext2/super.c?v=2.6.32#L785)
   * RAMベースの場合は、ファイルシステムの都合で適当に初期化しておけば良い

### tmpfs

 * [shmem_get_inode](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1541)を見るのがよい

### ramfs

 * ramfsの[ramfs_get_inode](http://lxr.free-electrons.com/source/fs/ramfs/inode.c?v=2.6.32#L54)はもっとシンプル
   * simple_dir_operations とは?
   * [mapping_set_gfp_mask](http://lxr.free-electrons.com/source/include/linux/pagemap.h?v=2.6.32#L64) とは?
     * `mapping_set_gfp_mask(inode->i_mapping, GFP_HIGHUSER);`
     * address_space の メモリ割り当てを Highメモリから取る? High メモリ is なに?
     * refs http://seijinoblog.blogspot.jp/2012/03/linux_29.html
   * [mapping_set_unevictable](http://lxr.free-electrons.com/source/include/linux/pagemap.h?v=2.6.32#L38) とは?
     * [Unevictable LRU](https://www.kernel.org/doc/Documentation/vm/unevictable-lru.txt) を読んで理解する
     * アドレス空間全体を AS_UNEVICTABLE としてフラグをセット
     * ramfs の inode ページフレームがが回収されちゃったら困るから、 AS_UNEVICTABLE とするのだろう?

```
Unevictable リストとは文字どおり、強制回収できないリストを表す。この機構は比較的最近実装された
もので、64 bit 環境で 100GB を越える大容量な RAM を搭載した環境におけるページフレーム回収コス
トを減らす目的で導入されている。最新のカーネルドキュメント (*2) によれば、unevictable リストに
属するページは、次の 3 種類のページになる (らしい)。

　・ramfs が所有するページ
　・共有メモリロックのメモリリージョンにマッピングされているページ
　・VM_LOCKED フラグがセットされたメモリリージョンにマッピングされているページ
```

[lkml でお勉強 (その1-2)](http://dev.ariel-networks.com/Members/ohyama/lkml-304a52c95f37-305d306e1-2/)
 
### [struct inode](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L723) 各種メンバ

struct indoe = VFS inode
 
 * i_mode 
    * パーミッションはファイルシステムのポリシーで任意
    * i_mode に S_IFDIR 足しとかないと mount(2) で ENOTDIR `Not a directory` 返すので注意
 * uid,gid
 * atime, mtime, ctime
    * CURRENT_TIMEマクロを使うと現在時刻で初期化できる
 * i_mapping->backing_dev_info 
 * i_mapping->a_ops
 * inode_operations
    * ファイルとディレクトリとで実装内容が違う
 * ファイルの場合は
   * file_operations
 * ディレクトリの場合は
   * dir_operations
 * nlink リンク数
 * ブロック数
   * backing store が RAM の場合、適当な数値を入れてハックする必要があるぽい (tmpfsの例)

__misc__

 * vboxsf はホストOSの共有フォルダの情報を sf_stat で調べて情報を取り、sf_init_inode で適宜埋める様子
   * ホストOSはUNIX系OSとは限らないので汎用的な作りになってる
 * tmpfs の場合 [shmem_get_inode](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1541) で初期化している   
 * その他 dquot_operations, quotactl_ops, export_operations (nfs) は必要なら適宜初期化したらよい様子
 * tmpfs では俺俺の [struct shmem_sb_info](http://lxr.free-electrons.com/source/include/linux/shmem_fs.h?v=2.6.32#L24) を sb->s_fs_info に入れている
   * s_fs_info は `void * s_fs_info /* Filesystem private info */` とあり、ファイルシステム固有の俺俺データを入れとく用途
   * tmpfsでは各種制限が設けられていて、その閾値をぶっ込んでいる
    * [shmem_default_max_blocks](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L110) で ブロックの最大数を [totalram_pages](http://wiki.bit-hive.com/north/pg/%A5%C8%A1%BC%A5%BF%A5%EB%A5%E1%A5%E2%A5%EA)/2 としている
    * [shmem_default_max_inodes](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L115) で inodeの最大数を min(totalram_pages - totalhigh_pages, totalram_pages / 2); にしている
 * tmpfs として利用する場合は MS_NOUSERフラグが落ちてる
