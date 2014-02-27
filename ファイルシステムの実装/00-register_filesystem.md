## モジュールの modules_init で register_filesystem を呼びファイルシステムを登録する
 
独自のファイルシステムをカーネルに登録するには [struct file_system_type](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L1745) を定義する

 * カーネルモジュールの modules_init マクロに定義した関数内で [register_filesystem](http://lxr.free-electrons.com/source/fs/filesystems.c?v=2.6.32#L56) で登録したらよい
 * 削除するときは  modules_exits マクロに定義した関数内で [unregister_filesystem](http://lxr.free-electrons.com/source/fs/filesystems.c?v=2.6.32#L90) を呼べばよい
 
register_filesystem は file_system_type の [fs_supers](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L1753) リストに繋げるだけで、後述する .get_sb, .kill_sb の super_block の操作は何もしない
 
## struct file_system_type の実装

ファイルシステム名の登録( _/proc/filesystems_ で参照できる ) とsuper_block のコンストラクタ/デストラクタを実装する

 * struct fils_system_type の .get_sb と .kill_sb メンバの実装が必要
   * とはいえ１から全て書く必要は無くて、ひな形として流用できる関数が用意しされているので利用する
 * .get_sb
   * [get_sb_nodev](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L855) をラップすればよい
     * デバイスを持たないファイルシステムで superblock を取得するための関数 [#](http://filesystem.g.hatena.ne.jp/n314/20080325/1206426881)
     * get_sb_nodev の中で [sget](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L338) が superblock *sb のメモリを割り当ててくれる
       * [alloc_super](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L54) で `kzalloc(sizeof(struct super_block),  GFP_USER);` で割当
    * fill_super 関数ポインタを実装して superblock のメンバを初期化する必要がある
 * kill_sb 
   * [kill_litter_super](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L703) は [kill_anon_super](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L689) のラッパーで[d_genocide](http://lxr.free-electrons.com/source/fs/dcache.c?v=2.6.32#L2176) を使えばよい
     * kill_litter_super は [d_genocide](http://lxr.free-electrons.com/source/fs/dcache.c?v=2.6.32#L2176) を呼び出す。
       * root dentry から辿って全てのサブディレクトリ以下の dentry の参照カウントをデクリメントする
       * デクリメントするだけで dentry の破棄はしないぽい
     * [kill_anon_super](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L689) -> [generic_shutdown_super](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L693) で [shrink_dcache_for_umount](http://lxr.free-electrons.com/source/fs/super.c?v=2.6.32#L302) を呼んで dentry のキャッシュを破棄する

__misc__

 * .get_sb メンバは 2.6.39 まで。それ以降は .mount になる (vboxfsを参照)
   * get_sb_nodev が変わり mount_nodev になる
 * kill_anon_super の ___anon___ は super_block と結びついた block device が無いことを指すのだろう (anonymouse page 的な)

## register_file_system したら次はマウントする

ファイルシステムを登録したら vfs_kern_mount でマウントできる

```
struct vfsmount vfs_kern_mount(struct file_system_type *type, int flags, const char *name, void *data)
```

vfs_kern_mount はカーネル内でマウントするAPIで、ユーザランドから mount(2) してもよい。


 * MS_NOUSER フラグ
   * カーネル内部でマウントするものでユーザランドからマウントするもんじゃないことを指定 [#](http://linux.derkeiler.com/Mailing-Lists/Kernel/2005-01/2024.html)
   * MS_NOUSER をつけておいて、vfs_kern_mount でカーネルモジュール内でマウントするファイルシステムがある (pipefs?)
     * Pseudo-Filesystems の項を参照
 * magic
 * ブロックサイズ
 * super_ops
 * root ディレクトリの初期化
  * dentry
  * inode
