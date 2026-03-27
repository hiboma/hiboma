# write(2)でmtimeとctimeを更新する箇所.md

```
write
  vfs_write
    generic_file_aio_write
      mutex_lock(&inode->i_mutex);
      __generic_file_aio_write
        file_update_time
      mutex_unlock(&inode->i_mutex);
```


と、file_update_time で更新している

## file_update_time

```
/**
 *	file_update_time	-	update mtime and ctime time
 *	@file: file accessed
 *
 *	Update the mtime and ctime members of an inode and mark the inode
 *	for writeback.  Note that this function is meant exclusively for
 *	usage in the file write path of filesystems, and filesystems may
 *	choose to explicitly ignore update via this function with the
 *	S_NOCMTIME inode flag, e.g. for network filesystem where these
 *	timestamps are handled by the server.
 */

void file_update_time(struct file *file)
{
	struct inode *inode = file->f_path.dentry->d_inode;
	struct timespec now;
	enum { S_MTIME = 1, S_CTIME = 2, S_VERSION = 4 } sync_it = 0;

	/* First try to exhaust all avenues to not sync */
	if (IS_NOCMTIME(inode))
		return;

	now = current_fs_time(inode->i_sb);
	if (!timespec_equal(&inode->i_mtime, &now))
		sync_it = S_MTIME;

	if (!timespec_equal(&inode->i_ctime, &now))
		sync_it |= S_CTIME;

	if (IS_I_VERSION(inode))
		sync_it |= S_VERSION;

	if (!sync_it)
		return;

	/* Finally allowed to write? Takes lock. */
	if (__mnt_want_write_file(file))
		return;

	/* Only change inode inside the lock region */
	if (sync_it & S_VERSION)
		inode_inc_iversion(inode);
	if (sync_it & S_CTIME)
		inode->i_ctime = now;
	if (sync_it & S_MTIME)
		inode->i_mtime = now;
	mark_inode_dirty_sync(inode);
	__mnt_drop_write(file->f_path.mnt);
}
EXPORT_SYMBOL(file_update_time);
```

## __generic_file_aio_write

rite(2) に渡されたデータをあれこれする前に mtime と ctime が更新されている。 __generic_file_aio_write を見てみる

```c
/**
 * __generic_file_aio_write - write data to a file
 * @iocb:	IO state structure (file, offset, etc.)
 * @iov:	vector with data to write
 * @nr_segs:	number of segments in the vector
 * @ppos:	position where to write
 *
 * This function does all the work needed for actually writing data to a
 * file. It does all basic checks, removes SUID from the file, updates
 * modification times and calls proper subroutines depending on whether we
 * do direct IO or a standard buffered write.
 *
 * It expects i_mutex to be grabbed unless we work on a block device or similar
 * object which does not need locking at all.
 *
 * This function does *not* take care of syncing data in case of O_SYNC write.
 * A caller has to handle it. This is mainly due to the fact that we want to
 * avoid syncing under i_mutex.
 */
ssize_t __generic_file_aio_write(struct kiocb *iocb, const struct iovec *iov,
				 unsigned long nr_segs, loff_t *ppos)
{
	struct file *file = iocb->ki_filp;
	struct address_space * mapping = file->f_mapping;
	size_t ocount;		/* original count */
	size_t count;		/* after file limit checks */
	struct inode 	*inode = mapping->host;
	loff_t		pos;
	ssize_t		written;
	ssize_t		err;

	ocount = 0;
	err = generic_segment_checks(iov, &nr_segs, &ocount, VERIFY_READ);
	if (err)
		return err;

	count = ocount;
	pos = *ppos;

	if (!sb_has_new_freeze(inode->i_sb))
		vfs_check_frozen(inode->i_sb, SB_FREEZE_WRITE);

	/* We can write back this queue in page reclaim */
	current->backing_dev_info = mapping->backing_dev_info;
	written = 0;

	err = generic_write_checks(file, &pos, &count, S_ISBLK(inode->i_mode));
	if (err)
		goto out;

	if (count == 0)
		goto out;

	err = file_remove_suid(file);
	if (err)
		goto out;

	file_update_time(file);

	/* coalesce the iovecs and go direct-to-BIO for O_DIRECT */
	if (unlikely(file->f_flags & O_DIRECT)) {
		loff_t endbyte;
		ssize_t written_buffered;

		written = generic_file_direct_write(iocb, iov, &nr_segs, pos,
							ppos, count, ocount);
		if (written < 0 || written == count)
			goto out;

// ... 略

	} else {
		written = generic_file_buffered_write(iocb, iov, nr_segs,
				pos, ppos, count, written);
	}

out:
	
	current->backing_dev_info = NULL;
	return written ? written : err;
}
```

file_update_time はいろんなところで呼び出されている

```
file_update_time  101 drivers/video/fb_defio.c 	file_update_time(vma->vm_file);
file_update_time 2490 fs/buffer.c      	file_update_time(vma->vm_file);
file_update_time 1105 fs/fuse/file.c   	file_update_time(file);
file_update_time  370 fs/gfs2/file.c   	file_update_time(vma->vm_file);
file_update_time 1517 fs/inode.c       EXPORT_SYMBOL(file_update_time);
file_update_time  264 fs/ncpfs/file.c  	file_update_time(file);
file_update_time 2116 fs/ntfs/file.c   	file_update_time(file);
file_update_time  617 fs/pipe.c        		file_update_time(filp);
file_update_time  974 fs/splice.c      			file_update_time(out);
file_update_time  240 fs/sysfs/bin.c   		file_update_time(file);
file_update_time  578 fs/xfs/linux-2.6/xfs_file.c 		file_update_time(file);
file_update_time 2672 include/linux/fs.h extern void file_update_time(struct file *file);
file_update_time 1762 mm/filemap.c     	file_update_time(vma->vm_file);
file_update_time 2558 mm/filemap.c     	file_update_time(file);
file_update_time  430 mm/filemap_xip.c 	file_update_time(filp);
file_update_time 2435 mm/memory.c      				file_update_time(vma->vm_file);
file_update_time 2460 mm/memory.c      			file_update_time(vma->vm_file);
file_update_time 3152 mm/memory.c      			file_update_time(vma->vm_file);
```
