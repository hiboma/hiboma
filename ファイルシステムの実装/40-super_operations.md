
## [struct super_operations](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L1562) の実装

RAMベースだと全てを実装する必要は無い。

### vboxsfの実装

2.6.32用のvboxsfで実装されるメンバは下記の4つ

 * .clear_inode
   * inode->private から sf_inode_info を取り出して kfree
 * .put_user 
   * umount(2) して super_blockを解放する時に呼ぶ?
   * super_block から sf_glob_info を取り出して、backing_dev を bdi_destroy してる
   * vboxCallUnmapFolder でホストOSのフォルダとのマップを解除
 * .remount_fs
 * .statfs

vboxsfでは実データのinodeはホストOSのファイルシステムが見てるので、特にCRUDな操作を必要としない様子。vboxsfがゲストOSとホストOSの間を透過的にするレイヤになる

#### .statfs

```c
// mountポイントの dentry
// STRUCT_STATFS は struct kstatfs で、ユーザランドに渡したい数値でフィールドを初期化すればよい
static int sf_statfs(struct dentry *dentry, STRUCT_STATFS *stat)
{
    struct super_block *sb = dentry->d_inode->i_sb;
    return sf_get_volume_info(sb, stat);
}

// ...

// ホストOSに statfs を投げてるのかな?
// /vagrant のdf は sharedしているホストOSのファイルシステムのdf と一致する
int sf_get_volume_info(struct super_block *sb, STRUCT_STATFS *stat)
{
    struct sf_glob_info *sf_g;
    SHFLVOLINFO SHFLVolumeInfo;
    uint32_t cbBuffer;
    int rc;

    sf_g = GET_GLOB_INFO(sb);
    cbBuffer = sizeof(SHFLVolumeInfo);
    rc = vboxCallFSInfo(&client_handle, &sf_g->map, 0, SHFL_INFO_GET | SHFL_INFO_VOLUME,
                        &cbBuffer, (PSHFLDIRINFO)&SHFLVolumeInfo);
    // Runtime
    // ホストOSからで発生したエラー -> VirtualBoxのエラー -> ゲストOSのエラーに変換
    if (RT_FAILURE(rc))
        return -RTErrConvertToErrno(rc);

    stat->f_type        = NFS_SUPER_MAGIC; /* XXX vboxsf type? */
    stat->f_bsize       = SHFLVolumeInfo.ulBytesPerAllocationUnit;
    stat->f_blocks      = SHFLVolumeInfo.ullTotalAllocationBytes
                        / SHFLVolumeInfo.ulBytesPerAllocationUnit;
    stat->f_bfree       = SHFLVolumeInfo.ullAvailableAllocationBytes
                        / SHFLVolumeInfo.ulBytesPerAllocationUnit;
    stat->f_bavail      = SHFLVolumeInfo.ullAvailableAllocationBytes
                        / SHFLVolumeInfo.ulBytesPerAllocationUnit;
    stat->f_files       = 1000;
    stat->f_ffree       = 1000; /* don't return 0 here since the guest may think
                                 * that it is not possible to create any more files */
    stat->f_fsid.val[0] = 0;
    stat->f_fsid.val[1] = 0;
    stat->f_namelen     = 255;
    return 0;
}
```

 * df -i で 空き inode の数が 1000 と出るけど、これはハードコードされてる数値で意味はない

```
[vagrant@cent6-build-php ~]$ df -i /vagrant/
Filesystem     Inodes IUsed IFree IUse% Mounted on
/vagrant         1000     0  1000    0% /vagrant
```

### tmpfsの実装

tmpfs の [shmem_ops](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L2488) で実装されているメンバは下記の通り 

 * [.alloc_inode](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L2377), .destroy_inode
   * kmem_cache_alloc, kmem_cache_free で shmem_inode_info のメモリを割当/解放
      * shmem_inode_info の .vfs_inode メンバを `struct inode` として返す
   * RAMベースの場合、自前でメモリ抱えて inode を返さないといけないのかな?
 * [.statfs](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1780)
   * statfs(2) のデータを `struct kstatfs` に埋めて返す
   * ブロックサイズ、空き/使用済みブロック、空き/使用済みinode数 などを入れる 
 * [.remount_fs](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L2237)
   * remount の際に呼ばれてそう。マウントオプションのパースは自分で頑張る必要がある
 * [.show_options](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L2279)
   * ファイルシステム固有のオプションを表示する、とのこと
   * seq_printf で任意の文字列をユーザランドに渡せる
 * .delete_inode 
   * ___メモリ上にあるVFSのinodeとディスク上のデータ、メタデータを削除します___
     * truncate?の場合は inode についた pages を truncate_inode_pages でページキャッシュから解放している
     * shmem_free_inode で 空きinode数をインクリメント
     * その後 clear_inode する。 super_operations の s_op が定義されていれば 呼び出す様子
 * .drop_inode
 * [.put_user](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L2299)
   * sb->s_fs_info を kfree してるだけ。任意の操作を入れといたらいいのかな?

### ramfs

 * .statfs は simple_statfs

### df で Function not implemented [#13](https://github.com/hiboma/nukofs/issues/13)

```
[vagrant@vagrant-centos65 vagrant]$ df -h
df: `/mnt/nukofs': Function not implemented
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       7.3G  1.3G  5.7G  19% /
tmpfs           295M     0  295M   0% /dev/shm
/vagrant        931G  273G  658G  30% /vagrant
```

 * .statfs を simple_statfs にしとくと Function ... は出なくなるけど、容量の数値は出ない

```
# $ strace df
statfs("/mnt/nukofs", {f_type=0xca10, f_bsize=4096, f_blocks=0, f_bfree=0, f_bavail=0, f_files=0, f_ffree=0, f_fsid={0, 0}, f_namelen=255, f_frsize=4096}) = 0
```

 * f_blocks, f_bfree, f_bavail, ... が 0 だと、 何もオプションつけない df じゃ出力されん
   * df -a で確認できる

```sh
#       -a, --all
#              include dummy file systems
$ df -a
[vagrant@vagrant-centos65 vagrant]$ df -a
Filesystem     1K-blocks      Used Available Use% Mounted on
/dev/sda1        7635048   1353516   5893692  19% /
proc                   0         0         0    - /proc
sysfs                  0         0         0    - /sys
devpts                 0         0         0    - /dev/pts
tmpfs             301788         0    301788   0% /dev/shm
none                   0         0         0    - /proc/sys/fs/binfmt_misc
/vagrant       975922976 286194092 689728884  30% /vagrant
nukofs                 0         0         0    - /mnt/nukofs
```

 * .shmem_statfs のように `struct kstatfs` に何かしら数値いれとくと空き容量や空きブロックをユーザランドに返せる
   * 当たり前だけど、これらの数値はファイルシステムの実装で加減して管理しとくもの

```c
static int shmem_statfs(struct dentry *dentry, struct kstatfs *buf)
{
	struct shmem_sb_info *sbinfo = SHMEM_SB(dentry->d_sb);

	buf->f_type = TMPFS_MAGIC;
	buf->f_bsize = PAGE_CACHE_SIZE;
	buf->f_namelen = NAME_MAX;
	if (sbinfo->max_blocks) {
		buf->f_blocks = sbinfo->max_blocks;
		buf->f_bavail =
		buf->f_bfree  = sbinfo->max_blocks -
				percpu_counter_sum(&sbinfo->used_blocks);
	}
	if (sbinfo->max_inodes) {
		buf->f_files = sbinfo->max_inodes;
		buf->f_ffree = sbinfo->free_inodes;
	}
	/* else leave those fields 0 like simple_statfs */
	return 0;
}
```

__memo__

 * backing store が ブロックデバイスでなければ .dirty_inode, .write_inode, .write_super, は実装しなくてよい
    * メモリ上のデータがdirtyでもブロックデバイスのデータと同期する必要がないから
 * 2.6.25 未満では .read_inode の実装が必要
