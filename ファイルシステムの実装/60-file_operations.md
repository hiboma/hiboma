## [struct file_operations](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L1489) の実装

```
ファイルの読み取りや下記k未などの操作を行う、ファイルシステムごとに固有のファイル操作(file operation)関数群があります
```

 * inode->i_fop メンバ
 * open(2) ないと呼べないよね? ( `struct file` を確保しているのが前提)

### read(2) が Invalid argument [#19](https://github.com/hiboma/nukofs/issues/19)

 * vfs_read が file_operations の .read と .aio_write が無い場合は -EINVAL 返す

```c
ssize_t vfs_read(struct file *file, char __user *buf, size_t count, loff_t *pos)
{
	ssize_t ret;

	if (!(file->f_mode & FMODE_READ))
		return -EBADF;
	if (!file->f_op || (!file->f_op->read && !file->f_op->aio_read))
		return -EINVAL;
	if (unlikely(!access_ok(VERIFY_WRITE, buf, count)))
		return -EFAULT;

	ret = rw_verify_area(READ, file, pos, count);
	if (ret >= 0) {
		count = ret;
		if (file->f_op->read)
			ret = file->f_op->read(file, buf, count, pos);
		else
			ret = do_sync_read(file, buf, count, pos);
		if (ret > 0) {
			fsnotify_access(file->f_path.dentry);
			add_rchar(current, ret);
		}
		inc_syscr(current);
	}

	return ret;
}
```

 * do_sync_read って書いてるのに aio_read に繋がるのね

```c
ssize_t do_sync_read(struct file *filp, char __user *buf, size_t len, loff_t *ppos)
{
	struct iovec iov = { .iov_base = buf, .iov_len = len };
	struct kiocb kiocb;
	ssize_t ret;

	init_sync_kiocb(&kiocb, filp);
	kiocb.ki_pos = *ppos;
	kiocb.ki_left = len;

	for (;;) {
		ret = filp->f_op->aio_read(&kiocb, &iov, 1, kiocb.ki_pos);
		if (ret != -EIOCBRETRY)
			break;
		wait_on_retry_sync_kiocb(&kiocb);
	}

	if (-EIOCBQUEUED == ret)
		ret = wait_on_sync_kiocb(&kiocb);
	*ppos = kiocb.ki_pos;
	return ret;
}
```

### write(2) が Invalid argument [#11](https://github.com/hiboma/nukofs/issues/11)

 * [sys_write](http://lxr.free-electrons.com/source/fs/read_write.c?v=2.6.32#L389) -> [vfs_write](http://lxr.free-electrons.com/source/fs/read_write.c?v=2.6.32#L332)
   * 以下の通り、file_operations の .write または aio_write を実装しておかないと EINVAL を返す

```c
ssize_t vfs_write(struct file *file, const char __user *buf, size_t count, loff_t *pos)
{
	ssize_t ret;

	if (!(file->f_mode & FMODE_WRITE))
		return -EBADF;
	if (!file->f_op || (!file->f_op->write && !file->f_op->aio_write))
		return -EINVAL;
	if (unlikely(!access_ok(VERIFY_READ, buf, count)))
		return -EFAULT;

	ret = rw_verify_area(WRITE, file, pos, count);
	if (ret >= 0) {
		count = ret;
		if (file->f_op->write)
			ret = file->f_op->write(file, buf, count, pos);
		else
			ret = do_sync_write(file, buf, count, pos);
		if (ret > 0) {
			fsnotify_modify(file->f_path.dentry);
			add_wchar(current, ret);
		}
		inc_syscw(current);
	}

	return ret;
}
```

`struct file_operations` の .write, .aio_write を実装しよう ↓

#### .write と .aio_write だけ初期化してみたところ panic

![](https://f.cloud.github.com/assets/172456/1949504/47a3daf4-810c-11e3-934c-21473ef89139.png)

 * `struct address_space_operations` の実装も必要だった様子
   * generic_file_aio_write がページキャッシュにデータを載せるため
      * O_DIRECT を指定した際に呼ばれる generic_file_direct_write と比較するとページキャッシュの差が分かりやすい?
      * generic_file_buffered_write の有無 によって差がでる
   * .write_begin, .write_end が必要
     * [simple_write_begin](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L353), [simple_write_end](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L391) が用意されている
     * simple_write_begin は strct *page を割り当て、[simple_prepare_write](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L341) で page の中身をゼロクリア
       * ここでの page は PG_locked
   * .write_page はいらんみたい => ???

#### ramfs, tmpfs

 * [do_sync_write](http://lxr.free-electrons.com/source/fs/ramfs/file-mmu.c?v=2.6.32#L40) を使ってる
   * do_sync_write は file_->f_op->aio_write を呼び出してる。 結局 .aio_write が必要なのかn
   * `const char __user *buf` は `struct iovec iov` にまとめられる
 * [generic_file_aio_write](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L2464)
   * `mutex_lock(&inode->i_mutex)` -> inode 単位で直列化
   * [__generic_file_aio_write](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L2334)
     * `current->backing_dev_info = mapping->backing_dev_info`
     * [generic_file_buffered_write](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L2304)
       * [generic_perform_write](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L2212)
       * address_space_operations の .write_begin , .write_end が呼ばれる => 後述

aio は [POSIX AIO](http://linuxjm.sourceforge.jp/html/LDP_man-pages/man7/aio.7.html) とは違う(よね)
