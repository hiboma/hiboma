
## [struct inode_operations](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L1518) の実装

nukofs を mount したディレクトリに通常ファイルを作成したいので inode_operations の必要なメンバを実装する

### .lookup

```c
/**
 * This is called when vfs failed to locate dentry in the cache. The
 * job of this function is to allocate inode and link it to dentry.
 * [dentry] contains the name to be looked in the [parent] directory.
 * Failure to locate the name is not a "hard" error, in this case NULL
 * inode is added to [dentry] and vfs should proceed trying to create
 * the entry via other means. NULL(or "positive" pointer) ought to be
 * returned in case of success and "negative" pointer on error
 */
static struct dentry *sf_lookup(struct inode *parent, struct dentry *dentry
```

 * vboxsf の説明には sf_lookup VFS が dentry を cache miss した際に呼ばれる。inode を割り当て、dentry と link する
 * [simple_lookup](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L47) が用意されているので使える

```
ディレクトリ .dir を検索します。dエントリオブジェクト dentry に含まれるファイル名に対応するinodeを見つけるためです
```

### VFS inode の割り当て

 * tmpfs の [shmem_mknod](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1805), [ramfs](http://lxr.free-electrons.com/source/fs/ramfs/inode.c?v=2.6.32#L95) の ramfs_mknod ともにファイル/ディレクトリ作成に .mknod のコールバックを流用している
   * .mknod は [mknod(2)](http://lxr.free-electrons.com/source/fs/namei.c?v=2.6.32#L2094) で呼び出されるコールバック
     * vfs の呼び出しを見ると、通常ファイルでは vfs_create, その他では vfs_mknod を呼び出している
     * 通常ファイルを作るには .create を実装しておかないといけないのね
   * VFS inode は 汎用API ( shmem_get_inode, ramfs_get_inode ) で割り当てている
   * VFS inode を [d_instantiate](http://lxr.free-electrons.com/source/fs/dcache.c?v=2.6.32#L991) と [dget](http://lxr.free-electrons.com/source/include/linux/dcache.h?v=2.6.32#L320) している
     * d_instantiate は VFS inode のデータで dentry を初期化? する
     * dget は参照カウントをインクリメントする = dentry cache との関係?

 * コンストラクタ的なコールバックは自前で実装が必要ぽいけど、デストラクタっぽいのは simple_*** みたいなので事足りるのかな?
   * fs/libfs.c に `Library for filesystems writers` とコメント有るので、ファルシステム作成を支援するライブラリぽい

### .create

 * .create
   * .create は `dentry に対応する通常ファイル用に、新しいディスクinodeを作成します`

### umount(2) をする際に Oops! した [#4](https://github.com/hiboma/nukofs/issues/4)

.create, .mknod を実装して、通常ファイルを作成して umount したら oops

![](https://f.cloud.github.com/assets/172456/1930814/a19ef548-7eb4-11e3-8346-525a55b40c00.png)

 * umount すると [shrink_dcache_for_umount](http://lxr.free-electrons.com/source/fs/dcache.c?v=2.6.32#L715) で superblock にぶら下がった dentry を破棄する
 * [shrink_dcache_for_umount_subtree](http://lxr.free-electrons.com/source/fs/dcache.c?v=2.6.32#L619)
   * .kill_sb を kill_anon_super から kill_litter_super にしたら解決した
     * vboxsf は kill_anon_super だな
   * umount する前に dentry を掃除しておかないとだめぽい
     * `atomic_read(&dentry->d_count) != 0` を満たさないと BUG() を出す [refs](http://lxr.free-electrons.com/source/fs/dcache.c?v=2.6.32#L658)

### unlink(2) が Operation not permitted [#6](https://github.com/hiboma/nukofs/issues/6)

下記の通り、[vfs_unlink](http://lxr.free-electrons.com/source/fs/namei.c?v=2.6.32#L2277) で i_op->unlink が NULL だと -EPERM を返す

```c
int vfs_unlink(struct inode *dir, struct dentry *dentry)
{
	int error = may_delete(dir, dentry, 0);

	if (error)
		return error;

	if (!dir->i_op->unlink)
		return -EPERM;
```

 * ディレクトリの inode_operations に `.unlink = simple_unlink` を実装して解決した
    * ramfs は [simple_unlink](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L287)
      * drop_nlink と dput が肝
      * ハードリンクされている場合は unlink(2) しても inode は残るので `inode->i_ctime = dir->i_ctime = dir->i_mtime = CURRENT_TIME;` している
        * ディレクトリの c_time, mtime が更新されてるのがポイント
    * tmpfs は [shmem_unlink](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1881)
       * [shmem_free_inode](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L258) で superblock の空きinode数をインクリメントしているのが simple_unlink と違う
       * `sbinfo->free_inodes` は tmpfs の inode数上限を管理するための数値
    * vbosf は sf_unlink -> sf_unlink_aux でホストOSとやり取り。
      * ホストOS のinodeとゲストの VFS inode, dentry がどう扱われてるかを覗ける

__misc__

 * ramfs_mknod のコメントに `/* SMP-safe */` とある
 * VFSでは SMP のことは何も考えなくていいのかな

### mkdir(2) が Operation not permitted [#8](https://github.com/hiboma/nukofs/issues/8)

.mkdir, .rmdir を実装する必要がある

 * .mkdir は自前で頑張る。
 * .rmdir は [simple_rmdir](http://lxr.free-electrons.com/ident?v=2.6.32&i=simple_rmdir) で代用できた
   * rmdir -> do_rmdir -> vfs_rmdir -> .rmdir
   * `int vfs_rmdir(struct inode *dir, struct dentry *dentry)` *dir は親ディレクトリかな。dentry は rmdir したいディレクトリのdentry
     * `d_mountpoint(dentry)` で マウントされているかいなかを見る
   * simple_rmdir は [simple_unlink](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L287) 呼び出している
   * 通常ファイルと同じように unlink するけど、親ディレクトリの inode->i_nlink(リンク数) を drop_nlink デクリメントするのが違う
   

### vfs_rename

```c
int vfs_rename(struct inode *old_dir, struct dentry *old_dentry,
	       struct inode *new_dir, struct dentry *new_dentry)
{
	int error;
	int is_dir = S_ISDIR(old_dentry->d_inode->i_mode);
	const char *old_name;

    // rename する対象が一緒なら何もしない
	if (old_dentry->d_inode == new_dentry->d_inode)
 		return 0;

    // 複雑
	error = may_delete(old_dir, old_dentry, is_dir);
	if (error)
		return error;

	if (!new_dentry->d_inode)
		error = may_create(new_dir, new_dentry);
	else
		error = may_delete(new_dir, new_dentry, is_dir);
	if (error)
		return error;

    // rename 元のディレクトリが .rename を実装していなければ -EPERM
	if (!old_dir->i_op->rename)
		return -EPERM;

	vfs_dq_init(old_dir);
	vfs_dq_init(new_dir);

	old_name = fsnotify_oldname_init(old_dentry->d_name.name);

	if (is_dir)
		error = vfs_rename_dir(old_dir,old_dentry,new_dir,new_dentry);
	else
		error = vfs_rename_other(old_dir,old_dentry,new_dir,new_dentry);
	if (!error) {
		const char *new_name = old_dentry->d_name.name;
		fsnotify_move(old_dir, new_dir, old_name, new_name, is_dir,
			      new_dentry->d_inode, old_dentry);
	}
	fsnotify_oldname_free(old_name);

	return error;
}
```

```c
/*
 * The worst of all namespace operations - renaming directory. "Perverted"
 * doesn't even start to describe it. Somebody in UCB had a heck of a trip...
 * Problems:
 *	a) we can get into loop creation. Check is done in is_subdir().
 *	b) race potential - two innocent renames can create a loop together.
 *	   That's where 4.4 screws up. Current fix: serialization on
 *	   sb->s_vfs_rename_mutex. We might be more accurate, but that's another
 *	   story.
 *	c) we have to lock _three_ objects - parents and victim (if it exists).
 *	   And that - after we got ->i_mutex on parents (until then we don't know
 *	   whether the target exists).  Solution: try to be smart with locking
 *	   order for inodes.  We rely on the fact that tree topology may change
 *	   only under ->s_vfs_rename_mutex _and_ that parent of the object we
 *	   move will be locked.  Thus we can rank directories by the tree
 *	   (ancestors first) and rank all non-directories after them.
 *	   That works since everybody except rename does "lock parent, lookup,
 *	   lock child" and rename is under ->s_vfs_rename_mutex.
 *	   HOWEVER, it relies on the assumption that any object with ->lookup()
 *	   has no more than 1 dentry.  If "hybrid" objects will ever appear,
 *	   we'd better make sure that there's no link(2) for them.
 *	d) some filesystems don't support opened-but-unlinked directories,
 *	   either because of layout or because they are not ready to deal with
 *	   all cases correctly. The latter will be fixed (taking this sort of
 *	   stuff into VFS), but the former is not going away. Solution: the same
 *	   trick as in rmdir().
 *	e) conversion from fhandle to dentry may come in the wrong moment - when
 *	   we are removing the target. Solution: we will have to grab ->i_mutex
 *	   in the fhandle_to_dentry code. [FIXME - current nfsfh.c relies on
 *	   ->i_mutex on parents, which works but leads to some truely excessive
 *	   locking].
 */
static int vfs_rename_dir(struct inode *old_dir, struct dentry *old_dentry,
			  struct inode *new_dir, struct dentry *new_dentry)
{
	int error = 0;
	struct inode *target;

	/*
	 * If we are going to change the parent - check write permissions,
	 * we'll need to flip '..'.
	 */
	if (new_dir != old_dir) {
		error = inode_permission(old_dentry->d_inode, MAY_WRITE);
		if (error)
			return error;
	}

	error = security_inode_rename(old_dir, old_dentry, new_dir, new_dentry);
	if (error)
		return error;

	target = new_dentry->d_inode;
	if (target) {
		mutex_lock(&target->i_mutex);
		dentry_unhash(new_dentry);
	}
    
    // マウントポイントは rename できない
	if (d_mountpoint(old_dentry)||d_mountpoint(new_dentry))
		error = -EBUSY;
	else 
		error = old_dir->i_op->rename(old_dir, old_dentry, new_dir, new_dentry);
	if (target) {
		if (!error)
			target->i_flags |= S_DEAD;
		mutex_unlock(&target->i_mutex);
		if (d_unhashed(new_dentry))
			d_rehash(new_dentry);
		dput(new_dentry);
	}
	if (!error)
		if (!(old_dir->i_sb->s_type->fs_flags & FS_RENAME_DOES_D_MOVE))
			d_move(old_dentry,new_dentry);
	return error;
}

static int vfs_rename_other(struct inode *old_dir, struct dentry *old_dentry,
			    struct inode *new_dir, struct dentry *new_dentry)
{
	struct inode *target;
	int error;

	error = security_inode_rename(old_dir, old_dentry, new_dir, new_dentry);
	if (error)
		return error;

	dget(new_dentry);
	target = new_dentry->d_inode;
	if (target)
		mutex_lock(&target->i_mutex);
	if (d_mountpoint(old_dentry)||d_mountpoint(new_dentry))
		error = -EBUSY;
	else
		error = old_dir->i_op->rename(old_dir, old_dentry, new_dir, new_dentry);
	if (!error) {
		if (!(old_dir->i_sb->s_type->fs_flags & FS_RENAME_DOES_D_MOVE))
			d_move(old_dentry, new_dentry);
	}
	if (target)
		mutex_unlock(&target->i_mutex);
	dput(new_dentry);
	return error;
}
```

 * 削除したけど開きっぱなしのでディレクトリは S_DEAD 状態らしい
   * `#define IS_DEADDIR(inode)	((inode)->i_flags & S_DEAD)`
   * `#define S_DEAD		16	/* removed, but still open directory */`

#### tmpfs

simple_unlink を呼ぶ順番が前後してるだけで、 simple_rmdir とほぼ同じ

 * [shmem_rmdir](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1895)
   * [simple_empty](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L272) でディレクトリが空かどうか(dentryのサブディレクトリを走査) みる
   * [shmem_unlink](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1881) をラップしている

### rename(2) が 'Operation not permitted' #17

 * .rename を実装する必要がある
   * ディレクトリとファイルの可能性がある indoe をどう扱うか?

#### tmpfs

 * [shmem_rename](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1911) で実装
   * simple_rename とほぼ同じ実装だが、 shmem_unlink を呼び出す違い
   * i_size に BOGO_DIRENT_SIZE を加減している
     * BOGO_DIRENT_SIZE はアテでいれてるディレクトリのサイズぽい。
     * ramfs ではそのようなことをしないので、ディレクトリのサイズが 0 になる

```c
/*
 * The VFS layer already does all the dentry stuff for rename,
 * we just have to decrement the usage count for the target if
 * it exists so that the VFS layer correctly free's it when it
 * gets overwritten.
 */
static int shmem_rename(struct inode *old_dir, struct dentry *old_dentry,
                        struct inode *new_dir, struct dentry *new_dentry)
{
	struct inode *inode = old_dentry->d_inode;
	int they_are_dirs = S_ISDIR(inode->i_mode);

	if (!simple_empty(new_dentry))
		return -ENOTEMPTY;

	if (new_dentry->d_inode) {
		(void) shmem_unlink(new_dir, new_dentry);
		if (they_are_dirs)
			drop_nlink(old_dir);
	} else if (they_are_dirs) {
		drop_nlink(old_dir);
		inc_nlink(new_dir);
	}

	old_dir->i_size -= BOGO_DIRENT_SIZE;
	new_dir->i_size += BOGO_DIRENT_SIZE;
	old_dir->i_ctime = old_dir->i_mtime =
	new_dir->i_ctime = new_dir->i_mtime =
	inode->i_ctime = CURRENT_TIME;
	return 0;
}
```

#### ramfs

 * [simple_rename](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L308) で実装
   * [simple_empty](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L272) でディレクトリが空かどうかの判定
     * dentry->d_subdirs を見ている。dentry はメモリ上に存在するのでスピンロックかけるだけで高速に判定できるぽい
 * rename(2) 先の dentry が存在するなら unlink(2) しとく
   * sipmle_unlink を使い回しているのが面白い
 * dentry を移動させるので、 drop_nlink と inc_nlink が肝
 * ctime, mtime を更新して終わり

```c
int simple_rename(struct inode *old_dir, struct dentry *old_dentry,
		struct inode *new_dir, struct dentry *new_dentry)
{
	struct inode *inode = old_dentry->d_inode;
	int they_are_dirs = S_ISDIR(old_dentry->d_inode->i_mode);

    // rename は mv とは違う !!!
    // mv 
	if (!simple_empty(new_dentry))
		return -ENOTEMPTY;

    // rename先にファイルが存在している場合は上書きする
	if (new_dentry->d_inode) {
		simple_unlink(new_dir, new_dentry);
		if (they_are_dirs)
			drop_nlink(old_dir);
	} else if (they_are_dirs) {
        // 古いディレクトリのリンクを減らす
		drop_nlink(old_dir);
		inc_nlink(new_dir);
	}

	old_dir->i_ctime = old_dir->i_mtime = new_dir->i_ctime =
		new_dir->i_mtime = inode->i_ctime = CURRENT_TIME;

	return 0;
}
```

#### vboxsf

 * ホストOSに面倒みてもらわないといけない

```c
/**
 * Rename a regular file / directory.
 *
 * @param old_parent    inode of the old parent directory
 * @param old_dentry    old directory cache entry
 * @param new_parent    inode of the new parent directory
 * @param new_dentry    new directory cache entry
 * @returns 0 on success, Linux error code otherwise
 */
static int sf_rename(struct inode *old_parent, struct dentry *old_dentry,
                     struct inode *new_parent, struct dentry *new_dentry)
{
    int err = 0, rc = VINF_SUCCESS;
    struct sf_glob_info *sf_g = GET_GLOB_INFO(old_parent->i_sb);

    TRACE();

    if (sf_g != GET_GLOB_INFO(new_parent->i_sb))
    {
        LogFunc(("rename with different roots\n"));
        err = -EINVAL;
    }
    else
    {
        struct sf_inode_info *sf_old_i = GET_INODE_INFO(old_parent);
        struct sf_inode_info *sf_new_i = GET_INODE_INFO(new_parent);
        /* As we save the relative path inside the inode structure, we need to change
           this if the rename is successful. */
        struct sf_inode_info *sf_file_i = GET_INODE_INFO(old_dentry->d_inode);
        SHFLSTRING *old_path;
        SHFLSTRING *new_path;

        BUG_ON(!sf_old_i);
        BUG_ON(!sf_new_i);
        BUG_ON(!sf_file_i);

        old_path = sf_file_i->path;
        err = sf_path_from_dentry(__func__, sf_g, sf_new_i,
                                  new_dentry, &new_path);
        if (err)
            LogFunc(("failed to create new path\n"));
        else
        {
            int fDir = ((old_dentry->d_inode->i_mode & S_IFDIR) != 0);

            // ホストOS で rename するよ
            // Windows だとなんだっけ ...
            rc = vboxCallRename(&client_handle, &sf_g->map, old_path,
                                new_path, fDir ? 0 : SHFL_RENAME_FILE | SHFL_RENAME_REPLACE_IF_EXISTS);
            if (RT_SUCCESS(rc))
            {
                // inode の drop_nlink, inc_nlink が無いな
                // ホストOSから取るからいらんのかな?
                kfree(old_path);
                sf_new_i->force_restat = 1;
                sf_old_i->force_restat = 1; /* XXX: needed? */
                /* Set the new relative path in the inode. */
                sf_file_i->path = new_path;
            }
            else
            {
                LogFunc(("vboxCallRename failed rc=%Rrc\n", rc));
                err = -RTErrConvertToErrno(rc);
                kfree(new_path);
            }
        }
    }
    return err;
}
```

#### chown(2) の実装

特に何も実装していないのに chown(2) が成功した why?

 * VFS inode のメンバを変更するだけなら特になんもいらん?
 * chown -> sys_fchownat -> chown_common -> notify_change -> [inode_setattr](http://lxr.free-electrons.com/source/fs/attr.c?v=2.6.32#L108) ( -> generic_setattr)
   * バニラカーネルだと inode_setattr, CentOS6カーネルだと generic_setattr で VFS inode のメンバを変更している
 * dirty な inode をブロックデバイスに書き出すのはまた別 -> super_operations の .dirty_inode かな?
 * chown は sys_fchownat をラップしている

RAMベースのファイルシステムの場合は VFS inode だけを扱えばいいので、特に実装がいらんてことになる

### link(2) が Operation not permitted [#15](https://github.com/hiboma/nukofs/issues/15)

 * vfs_link で -EPERM を返す。.link を実装する必要がある
 * ディレクトリの inode_operations の .link であることに注意 (ファイルではない)

```
int vfs_link(struct dentry *old_dentry, struct inode *dir, struct dentry *new_dentry)
{
	struct inode *inode = old_dentry->d_inode;
	int error;

	if (!inode)
		return -ENOENT;

	error = may_create(dir, new_dentry);
	if (error)
		return error;

	if (dir->i_sb != inode->i_sb)
		return -EXDEV;

	/*
	 * A link to an append-only or immutable file cannot be created.
	 */
	if (IS_APPEND(inode) || IS_IMMUTABLE(inode))
		return -EPERM;
	if (!dir->i_op->link)
		return -EPERM;
```

### sys_link

 * マウントポイントが違う場合は EXDEV
   * `struct path` の比較

```c
/**
 * lookup_create - lookup a dentry, creating it if it doesn't exist
 * @nd: nameidata info
 * @is_dir: directory flag
 *
 * Simple function to lookup and return a dentry and create it
 * if it doesn't exist.  Is SMP-safe.
 *
 * Returns with nd->path.dentry->d_inode->i_mutex locked.
 */
struct dentry *lookup_create(struct nameidata *nd, int is_dir)
```

``` c
	error = -EXDEV;
	if (old_path.mnt != nd.path.mnt)
		goto out_release;
```

```c
	mutex_lock(&inode->i_mutex);
	vfs_dq_init(dir);
	/* Make sure we don't allow creating hardlink to an unlinked file */
	if (inode->i_nlink == 0)
		error =  -ENOENT;
	else
		error = dir->i_op->link(old_dentry, dir, new_dentry);
	mutex_unlock(&inode->i_mutex);
```

### ramfs

 * [simple_link](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L255)
   * link元になるファイルの inode の nlink と i_count を増やす
   * link元になるファイルの inode から dentry を d_instantiate
     * 複数の dentry が 一個の inode を参照する => hardlink の仕組み
 * i_nlink は ++ だけど、 i_count は atomic_inc なのだな。うーん

```c
int simple_link(struct dentry *old_dentry, struct inode *dir, struct dentry *dentry)
{
	struct inode *inode = old_dentry->d_inode;

	inode->i_ctime = dir->i_ctime = dir->i_mtime = CURRENT_TIME;
	inc_nlink(inode);
	atomic_inc(&inode->i_count);
	dget(dentry);
	d_instantiate(dentry, inode);
	return 0;
}
```

#### tmpfs

 * [shmem_link](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L1857)
   * [shmem_reserve_inode](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L243)
     * free_inodes をデクリメントして inode数を管理
   * ふつーのディスクベースのファイルシステムでは link を inode としてカウントしない (inode 一個だし)
   * tmpfs の link は dentry 割り当て必要 +  lowmem に貼付けておく + tmpfs の dentry は unlink されるまで削除できない

```c
/*
 * Link a file..
 */
static int shmem_link(struct dentry *old_dentry, struct inode *dir, struct dentry *dentry)
{
	struct inode *inode = old_dentry->d_inode;
	int ret;

	/*
	 * No ordinary (disk based) filesystem counts links as inodes;
	 * but each new link needs a new dentry, pinning lowmem, and
	 * tmpfs dentries cannot be pruned until they are unlinked.
	 */
	ret = shmem_reserve_inode(inode->i_sb);
	if (ret)
		goto out;

	dir->i_size += BOGO_DIRENT_SIZE;
	inode->i_ctime = dir->i_ctime = dir->i_mtime = CURRENT_TIME;
	inc_nlink(inode);
	atomic_inc(&inode->i_count);	/* New dentry reference */
	dget(dentry);		/* Extra pinning count for the created dentry */
	d_instantiate(dentry, inode);
out:
	return ret;
}
```

## symlink  Operation not permitted

simple_symlink などない!!!

### symlink(2)

```
SYSCALL_DEFINE2(symlink, const char __user *, oldname, const char __user *, newname)
{
	return sys_symlinkat(oldname, AT_FDCWD, newname);
}
```

### vfs_symlink

```c
int vfs_symlink(struct inode *dir, struct dentry *dentry, const char *oldname)
{
	int error = may_create(dir, dentry);

	if (error)
		return error;

    // .symlink が無いと Operation not permitted ね。はいはい
	if (!dir->i_op->symlink)
		return -EPERM;

	error = security_inode_symlink(dir, dentry, oldname);
	if (error)
		return error;

	vfs_dq_init(dir);
	error = dir->i_op->symlink(dir, dentry, oldname);
	if (!error)
		fsnotify_create(dir, dentry);
	return error;
}
```

### ramfs

 * [ramfs_symlink]()

```c
static int ramfs_symlink(struct inode * dir, struct dentry *dentry, const char * symname)
{
	struct inode *inode;
	int error = -ENOSPC;

    // kmem_cache_alloc(inode_cachep, GFP_KERNEL) にコケたら ENOSPC を返す
    // 内部的には ENOMEM なんだろうけど、ファイルシステムとしては ENOSPC がただし
	inode = ramfs_get_inode(dir->i_sb, S_IFLNK|S_IRWXUGO, 0);
	if (inode) {
		int l = strlen(symname)+1;
		error = page_symlink(inode, symname, l);
		if (!error) {
			if (dir->i_mode & S_ISGID)
				inode->i_gid = dir->i_gid;
			d_instantiate(dentry, inode);
			dget(dentry);
			dir->i_mtime = dir->i_ctime = CURRENT_TIME;
		} else
			iput(inode);
	}
	return error;
}
```

### tmpfs

 * [shmem_symlink]()
