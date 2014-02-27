# ファイルシステムの実装

### 注意書き

 * 筆者の自習、教育的な用途を目的とした文章です
 * カーネルのバージョンは 2.6.32 ベースで記述しています
 * バニラカーネルのソースを掲載したページへのリンクを貼っているが、CentOSのカーネルはパッチが当たっているので、内容が全然一致しない場合があります
 * backing store を RAM にしたファイルシステムを念頭にしていて、ブロックデバイスのことは考えていません
   * ブロックデバイスベースのファイルシステムは複雑ぽいので、tmpfs と VirtualBox の vboxsf [ソース](https://www.virtualbox.org/wiki/Downloads)を参考に読み解いていく
      * vboxfs のソースは src/VBox/Additions/linux/sharedfolders 以下
   * 追記: tmpfs よりも ramfs の方が素朴な実装なので、最初に読むなら ramfs。ただし、カーネルのAPIをある程度知らないと逆に手がかかりがなさ過ぎるかも
   * 追記: fs/libfs.c の関数群も実装のヒントになる
 * 単語の定義を明確
   * _割り当て_ と書いた場合は、カーネルのメモリ管理APIで実メモリを確保していることを指すようにします (破棄はその逆)
   * _初期化_ と書いた場合は、メモリ割り当てされた構造体の未初期化のフィールドを初期化することを指すようにします
   * _実装_ と書いた場合は、モジュール作成者が任意のコードを書く必要があることを指すようにします
 * [https://github.com/hiboma/nukofs](https://github.com/hiboma/nukofs) に学習用の実装を残しています

## ファイルシステムをカーネルモジュールとして実装する
 
 * Linuxのファイルシステムはカーネルモジュールとして実装できます
   * OSが起動中に動的にロード可能、もしくは削除可能

## ファイルシステムを作るにあたって実装が必要なんだろうまとめ

 * struct file_system_type
   * super_operations
 * fill_super()
 * rootディレクトリの VFS inode
      * [iget_locked](http://lxr.free-electrons.com/source/fs/inode.c?v=2.6.32;a=m68k#L1067) で VFS inode 0番を割り当て
   * struct backing_dev_info
   * struct inode_operations
   * dir_inode_operations
   * address_space_operations ... ページの読み書き
   * file_operations ... VFSのインタフェースを実装 (read,write,...)
   * vm_operations ... 仮想メモリ用???

## memo

### dentry cache

 * do_lookup -> __d_llokup でキャッシュ探索 -> d_revalidate でキャッシュが有効かどうかを validate
   * real_lookup (filesystem-specific lookup action) -> .lookup

### /proc/filesystems の nodev の有無 とは?

`proc/filesystems` を cat すると nodev がついてるファイルシステムとそうでないのがある

```
[vagrant@vagrant-centos65 ~]$ cat /proc/filesystems 
nodev   sysfs
nodev   rootfs
nodev   bdev
nodev   proc
...
        iso9660
nodev   pstore
nodev   mqueue
        ext4
nodev   vboxsf
nodev   nukofs
```

 * `/proc/filesystems` 用に [file_systems_proc_show](http://lxr.free-electrons.com/source/fs/filesystems.c?v=2.6.32#L220) がコールバックとして定義されている
   * `struct file_system_type` の fs_flags に [FS_REQUIRES_DEV](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L175) が立っているかどうかの違いらしい
   * `この種類の全てのファイルシステムは物理ディスクデバイス上に存在する必要がある`
   * FS_REQUIRES_DEV が立ってないファイルシステムは NFS で export もできない?

```c
static int filesystems_proc_show(struct seq_file *m, void *v)
{
	struct file_system_type * tmp;

	read_lock(&file_systems_lock);
	tmp = file_systems;
	while (tmp) {
		seq_printf(m, "%s\t%s\n",
			(tmp->fs_flags & FS_REQUIRES_DEV) ? "" : "nodev",
			tmp->name);
		tmp = tmp->next;
	}
	read_unlock(&file_systems_lock);
	return 0;
}
```

### sparse

 * http://www26.atwiki.jp/funa_tk/pages/33.html
   * __user, __iommem などの検査

### Pseudo-Filesystems

 * 擬似ファイルシステム
   * ユーザランドから mount することを許可しない (MS_NOUSER) ファイルシステム
     * sockfs, pipefs, bdev ..
   * kern_mount でマウントできる
   * .get_sb の flags | MS_NOUSER としておくと、mount 時にこんなんでる

```
mount: wrong fs type, bad option, bad superblock on nukofs,
       missing codepage or helper program, or other error
       (for several filesystems (e.g. nfs, cifs) you might
       need a /sbin/mount.<type> helper program)
       In some cases useful info is found in syslog - try
       dmesg | tail  or so
```

### vfs_write の const char __user *buf をいじる

do_sync_write をラップして遊ぶ

 * vfs_write の引数にある *buf は const がついているので、 kstrdup して変更を入れてみる
   * buf はユーザ空間のアドレスを差しているので、 copy_from_user ? が中でコケてるはず
   * write(2) は`Bad address` EFAULT を返す
   * ユーザ空間のバッファをいじるようなことは御法度である。南無

```c
static ssize_t nukofs_do_sync_write(struct file *filp, const char __user *buf,
			     size_t len, loff_t *ppos)
{
    /* バッファを複製 (長さ確認すべき) */
	char *modified = kstrdup(buf, GFP_KERNEL);

    /* 元の do_sync_write を呼ぶ */
	ssize_t size = do_sync_write(filp, modified, len, ppos);

    /* kstrdup のを kfree */
	kfree(modified);
	return size;
}
```

### /proc/sys/vm/drop_caches

drop_caches に 2 を write すると clean な dentry, inode を解放する

```
echo 2 | sudo tee /proc/sys/vm/drop_caches
```

 * simple_lookup は dentry のキャッシュミスが起こると呼ばれる
   * detnry がクリアされていれば simple_lookup が実行されるかと思いきや違った
   * 下記のようなデバッグの printk を仕込んだので検証

```c
/*
 * Retaining negative dentries for an in-memory filesystem just wastes
 * memory and lookup time: arrange for them to be deleted immediately.
 */
static int simple_delete_dentry(struct dentry *dentry)
{
	return 1;
}

struct dentry *nukofs_lookup(struct inode *dir, struct dentry *dentry, struct nameidata *nd)
{
	printk(KERN_INFO "dentry %s\n", dentry->d_name.name);
	
	static const struct dentry_operations simple_dentry_operations = {
		.d_delete = simple_delete_dentry,
	};

	if (dentry->d_name.len > NAME_MAX)
		return ERR_PTR(-ENAMETOOLONG);
	dentry->d_op = &simple_dentry_operations;
	d_add(dentry, NULL);
	return NULL;
}
```

RAMベースだと dentry は常に dirty 扱い ???

# カーネルモジュール tips

 * ライセンス表記の MODULE_LICENSE を入れておかないと insmod 時に warning がコンソールに出る
   * http://www.tldp.org/LDP/lkmpg/2.6/html/x279.html
 * `__init`, `__exit` のアノテーションをつけておくと、モジュールをロード(アンロード)して関数実行後メモリが解放されてエコらしい
   * http://www.tldp.org/LDP/lkmpg/2.6/html/x245.html
 * CentOS6 では Development Tools と kernel-devel を入れればビルドできる
 * Makefileのひな形

```
obj-m := sample.o
KDIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)
default:
$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) modules
```

 * [kmem_cache](http://www.ibm.com/developerworks/jp/linux/library/l-linux-slab-allocator/) API
   * kmem_cache_create であらかじめ登録しておく必要ある
   * init_once ってなんだ???

 * `address >> PAGE_SHIFT` で PFN (page frame number)
 * `address & (PAGE_SIZE - 1)` でオフセットを出す
 * `S_ISDIR(d_inode->i_mode);` ディレクトリかどうか

# TODO

 * vboxCallWrite がホストOSのプロセスの動きとどう関連するか
   * src/VBox/Additions/common/VBoxGuestLib/VBoxGuestR0LibSharedFolders.c 以下にソース有り
 * alloc_pages
 * SetPageSwapBacked
 * add_to_page_cache