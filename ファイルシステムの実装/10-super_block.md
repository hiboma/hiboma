
## struct superblock の初期化 fill_super の役割

 * ファイルシステムの superblock と、ファイルシステムの root ディレクトリとなる VFS inode/dentry の割当て、初期化をする必要がある
 * fill_super の型をもつ関数ポインタを実装して get_sb_nodev に渡すことで上記の要件を実装する

なおここでの __inode__ はカーネルのメモリ上で扱われるVFSの `struct inode` のことで、backing store の inode 情報のことではない
backing store の inode 情報を VFSの `struct inode` にマップするのはまた別の話

### vboxsf
 
 * sf_read_super_aux で実装している

### tmpfs
 
 * [shmem_fill_super](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L2305) で実装している

### ramfs

 * [ramfs_fill_super](http://lxr.free-electrons.com/source/fs/ramfs/inode.c?v=2.6.32#L216)

#### ramfs は tmpfs と似ているが下記の違いがある

 * [save_mount_options](http://lxr.free-electrons.com/source/fs/namespace.c?v=2.6.32#L687) で mount(2)のオプション (void *data) を kstrdup する
    * [generic_show_options](http://lxr.free-electrons.com/source/fs/namespace.c?v=2.6.32#L664) を使いたい場合は save_mount_options をあらかじめ呼んで置く必要がある、とコメントがついてる
    * generic_show_options は .show_options のコールバック
 * [ramfs_parse_options](http://lxr.free-electrons.com/source/fs/ramfs/inode.c?v=2.6.32#L184) でマウントオプションのパース。
    * 文字列処理の参考になる
 * 実装のコードはほぼおんなじだけど、__ramfs__ と __rootfs__ と二つのファイルシステムを提供している
   * rootfs の場合は マウントのフラグに MS_NOUSER を足している。ユーザ空間からの mount を許可しない fs なのだった
   * ramfs はユーザ空間から普通にマウントできるやつ

### fill_super の詳細

```
(int *fill_super)(struct super_block *sb, void *data, int silent)
```

`struct super_block *sb` は [get_sb_nodev](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L855) の中で [sget](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L338) -> [alloc_super](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L54 )で割り当てられたもので、下記の各種メンバが初期化されていない

 * .s_blocksize
   * ブロックサイズ
   * ramfs, tmpfs は PAGE_CACHE_SIZE = PAGE_SIZE で指定されている
   * vboxsf は 1024
 * .s_blocksize_bits
   * ブロックサイズをビット値で表した数値 (つまりブロックサイズは2の倍数である必要がある)
   * ramfs, tmpfs は PAGE_CACHE_SHIFT = PAGE_SHIFT = 12 (4096) で指定されている
   * vboxsf は未定義
 * .s_magic
   * マジックナンバー。他のファイルシステムと競合しない数値を選ぶ必要がある
 * .s_maxbytes
   * 最大ファイルサイズ
   * [MAX_LFS_FILESIZE](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L1003)
     * 32bitの場合、ページキャッシュのサイズを上限とする
 * .super_operations
   * vboxfs は sf_super_ops
   * tmpfs は [shmem_ops](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L2488)
   * ramfs は [ramfs_ops](http://lxr.free-electrons.com/source/fs/ramfs/inode.c?v=2.6.32#L160)
 * .s_root
   * root になる dentry
   * rootディレクトリの VFS inode を作り、[d_alloc_root](http://lxr.free-electrons.com/source/fs/dcache.c?v=2.6.32#L1085) で root dentry を割り当てる必要がある
     * tmpfs は [shmem_get_inode](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1541) の [new_inode](http://lxr.free-electrons.com/source/fs/inode.c?v=2.6.32#L655) から inode を作る
       * [alloc_inode](http://lxr.free-electrons.com/source/fs/inode.c?v=2.6.32#L212) で `kmem_cache_alloc(inode_cachep, GFP_KERNEL);` することで inode が割り当てされる
       * shmem_get_inode は root dentry 用以外の inode も割り当てできるように汎用的になっている
     * ramfs は [ramfs_get_inode](http://lxr.free-electrons.com/source/fs/ramfs/inode.c?v=2.6.32#L54)
     * vboxsf は`iget_locked(sb, 0)` で 0番の inode を作る
 * ctime, mtime, atime の粒度?
 
全てのメンバを明示的に初期化しなくてもよい様子

__misc__

 * get_sb_nodev 以外にも [get_sb_pseudo](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L207) などある
   * ファイルシステムのバックエンドに応じて呼び出せばよい?
