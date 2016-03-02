# vm.dirty_expire_centisecs

## 定義

```c
	{
		.ctl_name	= VM_DIRTY_EXPIRE_CS,
		.procname	= "dirty_expire_centisecs",
		.data		= &dirty_expire_interval,
		.maxlen		= sizeof(dirty_expire_interval),
		.mode		= 0644,
		.proc_handler	= &proc_dointvec,
	},
```

## 参照箇所

```
/*
 * Periodic writeback of "old" data.
 *
 * Define "old": the first time one of an inode's pages is dirtied, we mark the
 * dirtying-time in the inode's address_space.  So this periodic writeback code
 * just walks the superblock inode list, writing back any inodes which are
 * older than a specific point in time.
 *
 * Try to run once per dirty_writeback_interval.  But if a writeback event
 * takes longer than a dirty_writeback_interval interval, then leave a
 * one-second gap.
 *
 * older_than_this takes precedence over nr_to_write.  So we'll only write back
 * all dirty pages if they are all attached to "old" mappings.
 */
static void wb_kupdate(unsigned long arg)
{
	unsigned long oldest_jif;
	unsigned long start_jif;
	unsigned long next_jif;
	long nr_to_write;
	struct writeback_control wbc = {
		.bdi		= NULL,
		.sync_mode	= WB_SYNC_NONE,
		.older_than_this = &oldest_jif, ★
		.nr_to_write	= 0,
		.nonblocking	= 1,
		.for_kupdate	= 1,
		.range_cyclic	= 1,
		.range_start	= 0,
		.range_end 	= LLONG_MAX,
	};

	sync_supers();
 
    // oldest_jif より古い dirty inode を writeback する
	oldest_jif = jiffies - msecs_to_jiffies(dirty_expire_interval * 10);
	start_jif = jiffies;
	next_jif = start_jif + msecs_to_jiffies(dirty_writeback_interval * 10);
	nr_to_write = global_page_state(NR_FILE_DIRTY) +
			global_page_state(NR_UNSTABLE_NFS) +
			(inodes_stat.nr_inodes - inodes_stat.nr_unused);
	trace_mm_pdflush_kupdate(nr_to_write);
	while (nr_to_write > 0) {
		wbc.encountered_congestion = 0;
		wbc.nr_to_write = max_writeback_pages;
		writeback_inodes(&wbc);
		if (wbc.nr_to_write > 0) {
			if (wbc.encountered_congestion)
				blk_congestion_wait(WRITE, HZ/10);
			else
				break;	/* All the old data is written */
		}
		nr_to_write -= max_writeback_pages - wbc.nr_to_write;
	}
	if (time_before(next_jif, jiffies + HZ))
		next_jif = jiffies + HZ;
	if (dirty_writeback_interval)
		mod_timer(&wb_timer, next_jif);
}
```

```c
/*
 * Write out a superblock's list of dirty inodes.  A wait will be performed
 * upon no inodes, all inodes or the final one, depending upon sync_mode.
 *
 * If older_than_this is non-NULL, then only write out inodes which
 * had their first dirtying at a time earlier than *older_than_this.
 *
 * If we're a pdlfush thread, then implement pdflush collision avoidance
 * against the entire list.
 *
 * WB_SYNC_HOLD is a hack for sys_sync(): reattach the inode to sb->s_dirty so
 * that it can be located for waiting on in __writeback_single_inode().
 *
 * Called under inode_lock.
 *
 * If `bdi' is non-zero then we're being asked to writeback a specific queue.
 * This function assumes that the blockdev superblock's inodes are backed by
 * a variety of queues, so all inodes are searched.  For other superblocks,
 * assume that all inodes are backed by the same queue.
 *
 * FIXME: this linear search could get expensive with many fileystems.  But
 * how to fix?  We need to go from an address_space to all inodes which share
 * a queue with that address_space.  (Easy: have a global "dirty superblocks"
 * list).
 *
 * The inodes to be written are parked on sb->s_io.  They are moved back onto
 * sb->s_dirty as they are selected for writing.  This way, none can be missed
 * on the writer throttling path, and we get decent balancing between many
 * throttled threads: we don't want them all piling up on __wait_on_inode.
 */
static void
sync_sb_inodes(struct super_block *sb, struct writeback_control *wbc)
{
	const unsigned long start = jiffies;	/* livelock avoidance */

	if (!wbc->for_kupdate || list_empty(&sb->s_io))
		list_splice_init(&sb->s_dirty, &sb->s_io);

	while (!list_empty(&sb->s_io)) {
		struct inode *inode = list_entry(sb->s_io.prev,
						struct inode, i_list);
		struct address_space *mapping = inode->i_mapping;
		struct backing_dev_info *bdi = mapping->backing_dev_info;
		long pages_skipped;

		if (!bdi_cap_writeback_dirty(bdi)) {
			list_move(&inode->i_list, &sb->s_dirty);
			if (sb == blockdev_superblock) {
				/*
				 * Dirty memory-backed blockdev: the ramdisk
				 * driver does this.  Skip just this inode
				 */
				continue;
			}
			/*
			 * Dirty memory-backed inode against a filesystem other
			 * than the kernel-internal bdev filesystem.  Skip the
			 * entire superblock.
			 */
			break;
		}

		if (wbc->nonblocking && bdi_write_congested(bdi)) {
			wbc->encountered_congestion = 1;
			if (sb != blockdev_superblock)
				break;		/* Skip a congested fs */
			list_move(&inode->i_list, &sb->s_dirty);
			continue;		/* Skip a congested blockdev */
		}

		if (wbc->bdi && bdi != wbc->bdi) {
			if (sb != blockdev_superblock)
				break;		/* fs has the wrong queue */
			list_move(&inode->i_list, &sb->s_dirty);
			continue;		/* blockdev has wrong queue */
		}

		/*
		 * Was this inode dirtied after sync_sb_inodes was called?
		 * This keeps sync from extra jobs and livelock.
		 */
		if (inode_dirtied_after(inode, start))
			break;

		/* Was this inode dirtied too recently? */
		if (wbc->older_than_this &&
		    inode_dirtied_after(inode, *wbc->older_than_this))
			break;

		/* Is another pdflush already flushing this queue? */
		if (current_is_pdflush() && !writeback_acquire(bdi))
			break;

        // dirty で古いページかかえてる inode を writeback
		BUG_ON(inode->i_state & I_FREEING);
		__iget(inode);
		pages_skipped = wbc->pages_skipped;
		__writeback_single_inode(inode, wbc);
		if (wbc->sync_mode == WB_SYNC_HOLD) {
			inode->dirtied_when = jiffies;
			list_move(&inode->i_list, &sb->s_dirty);
		}
		if (current_is_pdflush())
			writeback_release(bdi);
		if (wbc->pages_skipped != pages_skipped) {
			/*
			 * writeback is not making progress due to locked
			 * buffers.  Skip this inode for now.
			 */
			list_move(&inode->i_list, &sb->s_dirty);
		}
		spin_unlock(&inode_lock);
		iput(inode);
		cond_resched();
		spin_lock(&inode_lock);
		if (wbc->nr_to_write <= 0)
			break;
	}
	return;		/* Leave any unwritten inodes on s_io */
}
```

```
/*
 * Write out an inode's dirty pages.  Called under inode_lock.  Either the
 * caller has ref on the inode (either via __iget or via syscall against an fd)
 * or the inode has I_WILL_FREE set (via generic_forget_inode)
 */
static int
__writeback_single_inode(struct inode *inode, struct writeback_control *wbc)
{
	wait_queue_head_t *wqh;

	if (!atomic_read(&inode->i_count))
		WARN_ON(!(inode->i_state & (I_WILL_FREE|I_FREEING)));
	else
		WARN_ON(inode->i_state & I_WILL_FREE);

	if ((wbc->sync_mode != WB_SYNC_ALL) && (inode->i_state & I_LOCK)) {
		list_move(&inode->i_list, &inode->i_sb->s_dirty);
		return 0;
	}

	/*
	 * It's a data-integrity sync.  We must wait.
	 */
	if (inode->i_state & I_LOCK) {
		DEFINE_WAIT_BIT(wq, &inode->i_state, __I_LOCK);

		wqh = bit_waitqueue(&inode->i_state, __I_LOCK);
		do {
			spin_unlock(&inode_lock);
			__wait_on_bit(wqh, &wq, inode_wait,
							TASK_UNINTERRUPTIBLE);
			spin_lock(&inode_lock);
		} while (inode->i_state & I_LOCK);
	}
	return __sync_single_inode(inode, wbc);
}
```

```c
/*
 * Write a single inode's dirty pages and inode data out to disk.
 * If `wait' is set, wait on the writeout.
 *
 * The whole writeout design is quite complex and fragile.  We want to avoid
 * starvation of particular inodes when others are being redirtied, prevent
 * livelocks, etc.
 *
 * Called under inode_lock.
 */
static int
__sync_single_inode(struct inode *inode, struct writeback_control *wbc)
{
	unsigned dirty;
	struct address_space *mapping = inode->i_mapping;
	struct super_block *sb = inode->i_sb;
	int wait = wbc->sync_mode == WB_SYNC_ALL;
	int ret;

	BUG_ON(inode->i_state & I_LOCK);

	/* Set I_LOCK, reset I_DIRTY */
	dirty = inode->i_state & I_DIRTY;
	inode->i_state |= I_LOCK;
	inode->i_state &= ~I_DIRTY;

	spin_unlock(&inode_lock);

    // address space を書き出し
	ret = do_writepages(mapping, wbc);

	/* Don't write the inode if only I_DIRTY_PAGES was set */
	if (dirty & (I_DIRTY_SYNC | I_DIRTY_DATASYNC)) {
		int err = write_inode(inode, wait);
		if (ret == 0)
			ret = err;
	}

	if (wait) {
		int err = filemap_fdatawait(mapping);
		if (ret == 0)
			ret = err;
	}

	spin_lock(&inode_lock);
	inode->i_state &= ~I_LOCK;
	if (!(inode->i_state & I_FREEING)) {
		if (!(inode->i_state & I_DIRTY) &&
		    mapping_tagged(mapping, PAGECACHE_TAG_DIRTY)) {
			/*
			 * We didn't write back all the pages.  nfs_writepages()
			 * sometimes bales out without doing anything. Redirty
			 * the inode.  It is still on sb->s_io.
			 */
			if (wbc->for_kupdate) {
				/*
				 * For the kupdate function we leave the inode
				 * at the head of sb_dirty so it will get more
				 * writeout as soon as the queue becomes
				 * uncongested.
				 */
				inode->i_state |= I_DIRTY_PAGES;
				list_move_tail(&inode->i_list, &sb->s_dirty);
			} else {
				/*
				 * Otherwise fully redirty the inode so that
				 * other inodes on this superblock will get some
				 * writeout.  Otherwise heavy writing to one
				 * file would indefinitely suspend writeout of
				 * all the other files.
				 */
				inode->i_state |= I_DIRTY_PAGES;
				inode->dirtied_when = jiffies;
				list_move(&inode->i_list, &sb->s_dirty);
			}
		} else if (inode->i_state & I_DIRTY) {
			/*
			 * Someone redirtied the inode while were writing back
			 * the pages.
			 */
			list_move(&inode->i_list, &sb->s_dirty);
		} else if (atomic_read(&inode->i_count)) {
			/*
			 * The inode is clean, inuse
			 */
			list_move(&inode->i_list, &inode_in_use);
		} else {
			/*
			 * The inode is clean, unused
			 */
			list_move(&inode->i_list, &inode_unused);
		}
	}
	wake_up_inode(inode);
	return ret;
}
```

```c
int do_writepages(struct address_space *mapping, struct writeback_control *wbc)
{
	int ret;

	if (wbc->nr_to_write <= 0)
		return 0;
	wbc->for_writepages = 1;
	if (mapping->a_ops->writepages)
		ret = mapping->a_ops->writepages(mapping, wbc);
	else
		ret = generic_writepages(mapping, wbc);
	wbc->for_writepages = 0;
	return ret;
}

static inline int
generic_writepages(struct address_space *mapping, struct writeback_control *wbc)
{
	return mpage_writepages(mapping, wbc, NULL);
}
```

```
/**
 * mpage_writepages - walk the list of dirty pages of the given
 * address space and writepage() all of them.
 * 
 * @mapping: address space structure to write
 * @wbc: subtract the number of written pages from *@wbc->nr_to_write
 * @get_block: the filesystem's block mapper function.
 *             If this is NULL then use a_ops->writepage.  Otherwise, go
 *             direct-to-BIO.
 *
 * This is a library function, which implements the writepages()
 * address_space_operation.
 *
 * If a page is already under I/O, generic_writepages() skips it, even
 * if it's dirty.  This is desirable behaviour for memory-cleaning writeback,
 * but it is INCORRECT for data-integrity system calls such as fsync().  fsync()
 * and msync() need to guarantee that all the data which was dirty at the time
 * the call was made get new I/O started against them.  If wbc->sync_mode is
 * WB_SYNC_ALL then we were called for data integrity and we must wait for
 * existing IO to complete.
 */
int
mpage_writepages(struct address_space *mapping,
		struct writeback_control *wbc, get_block_t get_block)
{
	struct backing_dev_info *bdi = mapping->backing_dev_info;
	struct bio *bio = NULL;
	sector_t last_block_in_bio = 0;
	int ret = 0;
	int done = 0;
	int (*writepage)(struct page *page, struct writeback_control *wbc);
	struct pagevec pvec;
	int nr_pages;
	pgoff_t index;
	pgoff_t end;		/* Inclusive */
	int scanned = 0;
	int range_whole = 0;

	if (wbc->nonblocking && bdi_write_congested(bdi)) {
		wbc->encountered_congestion = 1;
		return 0;
	}

	writepage = NULL;
	if (get_block == NULL)
		writepage = mapping->a_ops->writepage;

	pagevec_init(&pvec, 0);
	if (wbc->range_cyclic && !wbc->for_kupdate) {
		index = mapping->writeback_index; /* Start from prev offset */
		end = -1;
	} else {
		index = wbc->range_start >> PAGE_CACHE_SHIFT;
		end = wbc->range_end >> PAGE_CACHE_SHIFT;
		if (wbc->range_start == 0 && wbc->range_end == LLONG_MAX)
			range_whole = 1;
		scanned = 1;
	}
retry:
	while (!done && (index <= end) &&
			(nr_pages = pagevec_lookup_tag(&pvec, mapping, &index,
			PAGECACHE_TAG_DIRTY,
			min(end - index, (pgoff_t)PAGEVEC_SIZE-1) + 1))) {
		unsigned i;

		scanned = 1;
		for (i = 0; i < nr_pages; i++) {
			struct page *page = pvec.pages[i];

			/*
			 * At this point we hold neither mapping->tree_lock nor
			 * lock on the page itself: the page may be truncated or
			 * invalidated (changing page->mapping to NULL), or even
			 * swizzled back from swapper_space to tmpfs file
			 * mapping
			 */

			lock_page(page);

			if (unlikely(page->mapping != mapping)) {
				unlock_page(page);
				continue;
			}

			if (!wbc->range_cyclic && page->index > end) {
				done = 1;
				unlock_page(page);
				continue;
			}

			if (wbc->sync_mode != WB_SYNC_NONE)
				wait_on_page_writeback(page);

			if (PageWriteback(page) ||
					!clear_page_dirty_for_io(page)) {
				unlock_page(page);
				continue;
			}

			if (writepage) {
				ret = (*writepage)(page, wbc);
				if (ret) {
					if (ret == -ENOSPC)
						set_bit(AS_ENOSPC,
							&mapping->flags);
					else
						set_bit(AS_EIO,
							&mapping->flags);
				}
			} else {
				bio = __mpage_writepage(bio, page, get_block,
						&last_block_in_bio, &ret, wbc,
						page->mapping->a_ops->writepage);
			}
			if (unlikely(ret == AOP_WRITEPAGE_ACTIVATE))
				unlock_page(page);
			if (ret || (--(wbc->nr_to_write) <= 0))
				done = 1;
			if (wbc->nonblocking && bdi_write_congested(bdi)) {
				wbc->encountered_congestion = 1;
				done = 1;
			}
		}
		pagevec_release(&pvec);
		cond_resched();
	}
	if (!scanned && !done) {
		/*
		 * We hit the last page and there is more work to be done: wrap
		 * back to the start of the file
		 */
		scanned = 1;
		index = 0;
		goto retry;
	}
	if (wbc->range_cyclic || (range_whole && wbc->nr_to_write > 0))
		mapping->writeback_index = index;
	if (bio)
		mpage_bio_submit(WRITE, bio);
	return ret;
}
EXPORT_SYMBOL(mpage_writepages);
```