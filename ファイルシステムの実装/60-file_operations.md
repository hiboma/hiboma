
 * ページフレームとページキャッシュを区別する
 * struct page と mapping とを add_to_page_cache_lru で結びつけたのがページキャッシュ

## [struct file_operations](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L1489) の実装

```
ファイルの読み取りや下記k未などの操作を行う、ファイルシステムごとに固有のファイル操作(file operation)関数群があります
```

 * inode->i_fop メンバ
 * open(2) ないと呼べないよね? ( `struct file` を確保しているのが前提)


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

### read(2) が Invalid argument [#19](https://github.com/hiboma/nukofs/issues/19)

vfs_read が file_operations の .read と .aio_write が無い場合は -EINVAL 返す

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

do_sync_read って書いてるのに aio_read に繋がるのね

 * 2次記憶装置からデータ読んでバッファが uptodate になるのを同期して待つことを指す?
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

TASK_UNINTERRUPTIBLE に移行して待たされるケース

```c
static void wait_on_retry_sync_kiocb(struct kiocb *iocb)
{
	set_current_state(TASK_UNINTERRUPTIBLE);
    // 下層で何かフラグが立たないと TASK_UNINTERRUPTIBLE で待つ
	if (!kiocbIsKicked(iocb))
		schedule();
	else
		kiocbClearKicked(iocb);
	__set_current_state(TASK_RUNNING);
}

/* wait_on_sync_kiocb:
 *	Waits on the given sync kiocb to complete.
 */
ssize_t wait_on_sync_kiocb(struct kiocb *iocb)
{
	while (iocb->ki_users) {
		set_current_state(TASK_UNINTERRUPTIBLE);
		if (!iocb->ki_users)
			break;
		io_schedule();
	}
	__set_current_state(TASK_RUNNING);
	return iocb->ki_user_data;
}
EXPORT_SYMBOL(wait_on_sync_kiocb);
```

```
/*
 * This task is about to go to sleep on IO. Increment rq->nr_iowait so
 * that process accounting knows that this is a task in IO wait state.
 */
void __sched io_schedule(void)
{
	struct rq *rq = raw_rq();

	delayacct_blkio_start();
	atomic_inc(&rq->nr_iowait);
	current->in_iowait = 1;
	schedule();
	current->in_iowait = 0;
	atomic_dec(&rq->nr_iowait);
	delayacct_blkio_end();
}
EXPORT_SYMBOL(io_schedule);
```

aio_read を読んだ後は下層の処理が終わるまで待たされる

generic_file_aio_write

```c

/**
 * generic_file_aio_read - generic filesystem read routine
 * @iocb:	kernel I/O control block
 * @iov:	io vector request
 * @nr_segs:	number of segments in the iovec
 * @pos:	current file position
 *
 * This is the "read()" routine for all filesystems
 * that can use the page cache directly.
 */
ssize_t
generic_file_aio_read(struct kiocb *iocb, const struct iovec *iov,
		unsigned long nr_segs, loff_t pos)
{
	struct file *filp = iocb->ki_filp;
	ssize_t retval;
	unsigned long seg;
	size_t count;
	loff_t *ppos = &iocb->ki_pos;

	count = 0;
	retval = generic_segment_checks(iov, &nr_segs, &count, VERIFY_WRITE);
	if (retval)
		return retval;

	/* coalesce the iovecs and go direct-to-BIO for O_DIRECT */
    // O_DIRECT の場合
    // __dentry_open で address_space の .direct_IO, get_xip_mem が無いと EINVAL
	if (filp->f_flags & O_DIRECT) {
		loff_t size;
		struct address_space *mapping;
		struct inode *inode;

		mapping = filp->f_mapping;
		inode = mapping->host;
		if (!count)
			goto out; /* skip atime */
		size = i_size_read(inode);
		if (pos < size) {
			retval = filemap_write_and_wait_range(mapping, pos,
					pos + iov_length(iov, nr_segs) - 1);
			if (!retval) {
				retval = mapping->a_ops->direct_IO(READ, iocb,
							iov, pos, nr_segs);
			}
			if (retval > 0)
				*ppos = pos + retval;
			if (retval) {
				file_accessed(filp);
				goto out;
			}
		}
	}

	for (seg = 0; seg < nr_segs; seg++) {
		read_descriptor_t desc;

		desc.written = 0;
		desc.arg.buf = iov[seg].iov_base;
		desc.count = iov[seg].iov_len;
		if (desc.count == 0)
			continue;
		desc.error = 0;
		do_generic_file_read(filp, ppos, &desc, file_read_actor);
		retval += desc.written;
		if (desc.error) {
			retval = retval ?: desc.error;
			break;
		}
		if (desc.count > 0)
			break;
	}
out:
	return retval;
}
EXPORT_SYMBOL(generic_file_aio_read);
```

do_generic_file_read は強そうだ ...

```c
/**
 * do_generic_file_read - generic file read routine
 * @filp:	the file to read
 * @ppos:	current file position
 * @desc:	read_descriptor
 * @actor:	read method
 *
 * This is a generic file read routine, and uses the
 * mapping->a_ops->readpage() function for the actual low-level stuff.
 *
 * This is really ugly. But the goto's actually try to clarify some
 * of the logic when it comes to error handling etc.
 */
static void do_generic_file_read(struct file *filp, loff_t *ppos,
		read_descriptor_t *desc, read_actor_t actor)
{
	struct address_space *mapping = filp->f_mapping;
	struct inode *inode = mapping->host;
    // 先読み情報
	struct file_ra_state *ra = &filp->f_ra;
	pgoff_t index;
	pgoff_t last_index;
	pgoff_t prev_index;
	unsigned long offset;      /* offset into pagecache page */
	unsigned int prev_offset;
	int error;

	index = *ppos >> PAGE_CACHE_SHIFT;
	prev_index = ra->prev_pos >> PAGE_CACHE_SHIFT;
	prev_offset = ra->prev_pos & (PAGE_CACHE_SIZE-1);
	last_index = (*ppos + desc->count + PAGE_CACHE_SIZE-1) >> PAGE_CACHE_SHIFT;
	offset = *ppos & ~PAGE_CACHE_MASK;

	for (;;) {
		struct page *page;
		pgoff_t end_index;
		loff_t isize;
		unsigned long nr, ret;

		cond_resched();
find_page:
        // radixツリーからページキャッシュ探すぞう
		page = find_get_page(mapping, index);
		if (!page) {
            // ページキャッシュの先読みを同期的に行う
			page_cache_sync_readahead(mapping,
					ra, filp,
					index, last_index - index);
            // ページキャッシュ無し
			page = find_get_page(mapping, index);
			if (unlikely(page == NULL))
				goto no_cached_page;
		}

        // ----- page 確保とページキャッシュ追加ができてる ------
		if (PageReadahead(page)) {
			page_cache_async_readahead(mapping,
					ra, filp, page,
					index, last_index - index);
		}

        // page と disk の内容が同期されていない
		if (!PageUptodate(page)) {
			if (inode->i_blkbits == PAGE_CACHE_SHIFT ||
					!mapping->a_ops->is_partially_uptodate)
				goto page_not_up_to_date;
            // PG_locked が取れるか否か
			if (!trylock_page(page))

            // ---- page が PG_locked -----
				goto page_not_up_to_date;
			/* Did it get truncated before we got the lock? */
			if (!page->mapping)
				goto page_not_up_to_date_locked;

            // ? update する ?
			if (!mapping->a_ops->is_partially_uptodate(page,
								desc, offset))
				goto page_not_up_to_date_locked;
			unlock_page(page);
            // ---- page が PG_locked 終わり -----
		}
page_ok:
		/*
		 * i_size must be checked after we know the page is Uptodate.
		 *
		 * Checking i_size after the check allows us to calculate
		 * the correct value for "nr", which means the zero-filled
		 * part of the page is not copied back to userspace (unless
		 * another truncate extends the file - this is desired though).
		 */

		isize = i_size_read(inode);
		end_index = (isize - 1) >> PAGE_CACHE_SHIFT;
		if (unlikely(!isize || index > end_index)) {
			page_cache_release(page);
			goto out;
		}

		/* nr is the maximum number of bytes to copy from this page */
		nr = PAGE_CACHE_SIZE;
		if (index == end_index) {
			nr = ((isize - 1) & ~PAGE_CACHE_MASK) + 1;
			if (nr <= offset) {
				page_cache_release(page);
				goto out;
			}
		}
		nr = nr - offset;

		/* If users can be writing to this page using arbitrary
		 * virtual addresses, take care about potential aliasing
		 * before reading the page on the kernel side.
		 */
		if (mapping_writably_mapped(mapping))
			flush_dcache_page(page);

		/*
		 * When a sequential read accesses a page several times,
		 * only mark it as accessed the first time.
		 */
		if (prev_index != index || offset != prev_offset)
			mark_page_accessed(page);
		prev_index = index;

		/*
		 * Ok, we have the page, and it's up-to-date, so
		 * now we can copy it to user space...
		 *
		 * The actor routine returns how many bytes were actually used..
		 * NOTE! This may not be the same as how much of a user buffer
		 * we filled up (we may be padding etc), so we can only update
		 * "pos" here (the actor routine has to update the user buffer
		 * pointers and the remaining count).
		 */
         // ページを確保して、ページの内容も update されたので
         // ユーザ空間にコピーする (actor の中)
         
		ret = actor(desc, page, offset, nr);
		offset += ret;
		index += offset >> PAGE_CACHE_SHIFT;
		offset &= ~PAGE_CACHE_MASK;
		prev_offset = offset;

		page_cache_release(page);
		if (ret == nr && desc->count)
			continue;
		goto out;

page_not_up_to_date:
		/* Get exclusive access to the page ... */
		error = lock_page_killable(page);
		if (unlikely(error))
			goto readpage_error;

page_not_up_to_date_locked:
		/* Did it get truncated before we got the lock? */
		if (!page->mapping) {
			unlock_page(page);
			page_cache_release(page);
			continue;
		}

		/* Did somebody else fill it already? */
		if (PageUptodate(page)) {
			unlock_page(page);
			goto page_ok;
		}

readpage:
		/*
		 * A previous I/O error may have been due to temporary
		 * failures, eg. multipath errors.
		 * PG_error will be set again if readpage fails.
		 */
		ClearPageError(page);
		/* Start the actual read. The read will unlock the page. */
        // readpage で 読む
		error = mapping->a_ops->readpage(filp, page);

		if (unlikely(error)) {
			if (error == AOP_TRUNCATED_PAGE) {
				page_cache_release(page);
				goto find_page;
			}
			goto readpage_error;
		}

		if (!PageUptodate(page)) {
            // TASK_KILLABLE でロックを取る
			error = lock_page_killable(page);
			if (unlikely(error))
				goto readpage_error;

            // ------- TASK_KILLABLE ------ 
			if (!PageUptodate(page)) {
				if (page->mapping == NULL) {
					/*
					 * invalidate_inode_pages got it
					 */
					unlock_page(page);
                    // ------- TASK_KILLABLE 終わり ------  
					page_cache_release(page);
					goto find_page;
				}
				unlock_page(page);
				shrink_readahead_size_eio(filp, ra);
				error = -EIO;
				goto readpage_error;
			}
			unlock_page(page);
           // ------- TASK_KILLABLE 終わり ------
		}

		goto page_ok;

readpage_error:
		/* UHHUH! A synchronous read error occurred. Report it */
		desc->error = error;
		page_cache_release(page);
		goto out;

no_cached_page:
		/*
		 * Ok, it wasn't cached, so we need to create a new
		 * page..
		 */
        // __GFP_COLD フラグ付きで page を確保する
		page = page_cache_alloc_cold(mapping);
		if (!page) {
			desc->error = -ENOMEM;
			goto out;
		}

        // ページを割り当てたのでページキャッシュに追加
		error = add_to_page_cache_lru(page, mapping,
						index, GFP_KERNEL);
		if (error) {
			page_cache_release(page);
			if (error == -EEXIST)
				goto find_page;
			desc->error = error;
			goto out;
		}
		goto readpage;
	}

out:
	ra->prev_pos = prev_index;
	ra->prev_pos <<= PAGE_CACHE_SHIFT;
	ra->prev_pos |= prev_offset;

	*ppos = ((loff_t)index << PAGE_CACHE_SHIFT) + offset;
	file_accessed(filp);
}
```

actor

 * ユーザ空間にページの中身をコピーする

```c
int file_read_actor(read_descriptor_t *desc, struct page *page,
			unsigned long offset, unsigned long size)
{
	char *kaddr;
	unsigned long left, count = desc->count;

	if (size > count)
		size = count;

	/*
	 * Faults on the destination of a read are common, so do it before
	 * taking the kmap.
	 */
	if (!fault_in_pages_writeable(desc->arg.buf, size)) {
		kaddr = kmap_atomic(page, KM_USER0);
		left = __copy_to_user_inatomic(desc->arg.buf,
						kaddr + offset, size);
		kunmap_atomic(kaddr, KM_USER0);
		if (left == 0)
			goto success;
	}

    // kmap_atomic と kmap の違いは?

	/* Do it the slow way */
	kaddr = kmap(page);
	left = __copy_to_user(desc->arg.buf, kaddr + offset, size);
	kunmap(page);

	if (left) {
		size -= left;
		desc->error = -EFAULT;
	}
success:
	desc->count = count - size;
	desc->written += size;
	desc->arg.buf += size;
	return size;
}
```
