# pdflush

pdflush は CentOS5 くらいまでかな

>
>10. Flusher thread
> Linux 2.6 before – bdflush (dirty_background_ratio)
>　　 kupdated (dirty_expire_interval)
>　　　　　　　　(dirty_writeback_interval)
> Linux 2.6    – pdfush : 2 to 8 threads
> Linux 2.6.32 – flusher : one thread for one block device
>
> http://www.slideshare.net/huangachou/ch16-26731925

## pdflush

```c
static int __init pdflush_init(void)
{
	int i;

	for (i = 0; i < MIN_PDFLUSH_THREADS; i++)
		start_one_pdflush_thread();
	return 0;
}
```

カーネルスレッドを生やす

```c
static void start_one_pdflush_thread(void)
{
	kthread_run(pdflush, NULL, "pdflush");
}
```

スレッドのエントリポイント

```c
/*
 * Of course, my_work wants to be just a local in __pdflush().  It is
 * separated out in this manner to hopefully prevent the compiler from
 * performing unfortunate optimisations against the auto variables.  Because
 * these are visible to other tasks and CPUs.  (No problem has actually
 * been observed.  This is just paranoia).
 */
static int pdflush(void *dummy)
{
	struct pdflush_work my_work;
	cpumask_t cpus_allowed;

	/*
	 * pdflush can spend a lot of time doing encryption via dm-crypt.  We
	 * don't want to do that at keventd's priority.
	 */
	set_user_nice(current, 0);

	/*
	 * Some configs put our parent kthread in a limited cpuset,
	 * which kthread() overrides, forcing cpus_allowed == CPU_MASK_ALL.
	 * Our needs are more modest - cut back to our cpusets cpus_allowed.
	 * This is needed as pdflush's are dynamically created and destroyed.
	 * The boottime pdflush's are easily placed w/o these 2 lines.
	 */
	cpus_allowed = cpuset_cpus_allowed(current);
	set_cpus_allowed(current, cpus_allowed);

	return __pdflush(&my_work);
}
```

## __pdflush

メインとなるループ

 * pdflush_operation 経由で my_work->list に関数ポインタがつっこまれる
 * 何をするかは my_work 次第

```c
static int __pdflush(struct pdflush_work *my_work)
{
	current->flags |= PF_FLUSHER | PF_SWAPWRITE;
	my_work->fn = NULL;
	my_work->who = current;
	INIT_LIST_HEAD(&my_work->list);

	spin_lock_irq(&pdflush_lock);
	nr_pdflush_threads++;
	for ( ; ; ) {
		struct pdflush_work *pdf;

		set_current_state(TASK_INTERRUPTIBLE);
		list_move(&my_work->list, &pdflush_list);
		my_work->when_i_went_to_sleep = jiffies;
		spin_unlock_irq(&pdflush_lock);
		schedule();
		try_to_freeze();
		spin_lock_irq(&pdflush_lock);
		if (!list_empty(&my_work->list)) {
			/*
			 * Someone woke us up, but without removing our control
			 * structure from the global list.  swsusp will do this
			 * in try_to_freeze()->refrigerator().  Handle it.
			 */
			my_work->fn = NULL;
			continue;
		}
		if (my_work->fn == NULL) {
			printk("pdflush: bogus wakeup\n");
			continue;
		}
		spin_unlock_irq(&pdflush_lock);
        
        // ここでお仕事 する
		(*my_work->fn)(my_work->arg0);

		/*
		 * Thread creation: For how long have there been zero
		 * available threads?
		 */
        // pdlfush スレッドを増やすかどうか
		if (jiffies - last_empty_jifs > 1 * HZ) {
			/* unlocked list_empty() test is OK here */
			if (list_empty(&pdflush_list)) {
				/* unlocked test is OK here */
				if (nr_pdflush_threads < MAX_PDFLUSH_THREADS)
					start_one_pdflush_thread();
			}
		}

		spin_lock_irq(&pdflush_lock);
		my_work->fn = NULL;

		/*
		 * Thread destruction: For how long has the sleepiest
		 * thread slept?
		 */
		if (list_empty(&pdflush_list))
			continue;
		if (nr_pdflush_threads <= MIN_PDFLUSH_THREADS)
			continue;
		pdf = list_entry(pdflush_list.prev, struct pdflush_work, list);
		if (jiffies - pdf->when_i_went_to_sleep > 1 * HZ) {
			/* Limit exit rate */
			pdf->when_i_went_to_sleep = jiffies;
			break;					/* exeunt */
		}
	}
	nr_pdflush_threads--;
	spin_unlock_irq(&pdflush_lock);
	return 0;
}
```

## pdflush_operation の呼び出し箇所

pdflush は pdlfush_operation を通じて起床する。呼び出し箇所を整理することで、pdflush がどんなパスで起床するか見ていく

```
pdflush_operation  301 fs/buffer.c      	pdflush_operation(do_thaw_all, 0);
pdflush_operation  390 fs/buffer.c      	pdflush_operation(do_sync, 0);
pdflush_operation  598 fs/super.c       	pdflush_operation(do_emergency_remount, 0);
pdflush_operation  122 include/linux/writeback.h int pdflush_operation(void (*fn)(unsigned long), unsigned long arg0);
pdflush_operation  847 mm/memory.c      			pdflush_operation(mmap_flush, vma->vm_file->f_mapping);
pdflush_operation  272 mm/page-writeback.c 		pdflush_operation(background_writeout, 0);
pdflush_operation  399 mm/page-writeback.c 	return pdflush_operation(background_writeout, nr_pages);
pdflush_operation  486 mm/page-writeback.c 	if (pdflush_operation(wb_kupdate, 0) < 0)
pdflush_operation  497 mm/page-writeback.c 	pdflush_operation(laptop_flush, 0);
```

## balance_dirty_pages -> background_writeout

```
/*
 * balance_dirty_pages() must be called by processes which are generating dirty
 * data.  It looks at the number of dirty pages in the machine and will force
 * the caller to perform writeback if the system is over `vm_dirty_ratio'.
 * If we're over `background_thresh' then pdflush is woken to perform some
 * writeout.
 */
static void balance_dirty_pages(struct address_space *mapping)
{
	long nr_reclaimable;
	long nr_writeback;
	long background_thresh;
	long dirty_thresh;
	unsigned long pages_written = 0;
	unsigned long write_chunk = sync_writeback_pages();

	struct backing_dev_info *bdi = mapping->backing_dev_info;

	for (;;) {
		struct writeback_control wbc = {
			.bdi		= bdi,
			.sync_mode	= WB_SYNC_NONE,
			.older_than_this = NULL,
			.nr_to_write	= write_chunk,
			.range_cyclic	= 1,
		};

		get_dirty_limits(&background_thresh, &dirty_thresh, mapping);
		nr_reclaimable = global_page_state(NR_FILE_DIRTY) +
					global_page_state(NR_UNSTABLE_NFS);
		nr_writeback = global_page_state(NR_WRITEBACK);
		if (nr_reclaimable + nr_writeback <= dirty_thresh) {
			if (bdi_cap_throttle_dirty(bdi) &&
                // キューが溢れてる
			    bdi_write_congested(bdi) &&
			    nr_reclaimable + nr_writeback >=
					(background_thresh + dirty_thresh) / 2)
				blk_congestion_wait(WRITE, HZ/10);
			break;
		}

		if (!dirty_exceeded)
			dirty_exceeded = 1;

		/* Note: nr_reclaimable denotes nr_dirty + nr_unstable.
		 * Unstable writes are a feature of certain networked
		 * filesystems (i.e. NFS) in which data may have been
		 * written to the server's write cache, but has not yet
		 * been flushed to permanent storage.
		 */
		if (nr_reclaimable) {
			writeback_inodes(&wbc);
			get_dirty_limits(&background_thresh,
					 	&dirty_thresh, mapping);
			nr_reclaimable = global_page_state(NR_FILE_DIRTY) +
					global_page_state(NR_UNSTABLE_NFS);
			if (nr_reclaimable +
				global_page_state(NR_WRITEBACK)
					<= dirty_thresh)
						break;
			pages_written += write_chunk - wbc.nr_to_write;
			if (pages_written >= write_chunk)
				break;		/* We've done our duty */
		}
		blk_congestion_wait(WRITE, HZ/10);

		if (fatal_signal_pending(current))
			break;
	}

	if (nr_reclaimable + global_page_state(NR_WRITEBACK)
		<= dirty_thresh && dirty_exceeded)
			dirty_exceeded = 0;

	if (writeback_in_progress(bdi))
		return;		/* pdflush is already working this queue */

	/*
	 * In laptop mode, we wait until hitting the higher threshold before
	 * starting background writeout, and then write out all the way down
	 * to the lower threshold.  So slow writers cause minimal disk activity.
	 *
	 * In normal mode, we start background writeout at the lower
	 * background_thresh, to keep the amount of dirty memory low.
	 */
	// ここで pdflush を起床
	if ((laptop_mode && pages_written) ||
	     (!laptop_mode && (nr_reclaimable > background_thresh)))
		pdflush_operation(background_writeout, 0);
}
```

#### background_writeout

 * background_thresh 以下になるまで 後ろでせっせと writeback する
 * writeback の実装は writeback_inodes 

```c
/*
 * writeback at least _min_pages, and keep writing until the amount of dirty
 * memory is less than the background threshold, or until we're all clean.
 */
static void background_writeout(unsigned long _min_pages)
{
	long min_pages = _min_pages;
	struct writeback_control wbc = {
		.bdi		= NULL,
		.sync_mode	= WB_SYNC_NONE,
		.older_than_this = NULL,
		.nr_to_write	= 0,
		.nonblocking	= 1,
		.range_cyclic	= 1,
	};

	for ( ; ; ) {
		long background_thresh;
		long dirty_thresh;

		get_dirty_limits(&background_thresh, &dirty_thresh, NULL);

        // background_thresh を下回ったら終わる
		if (global_page_state(NR_FILE_DIRTY) +
			global_page_state(NR_UNSTABLE_NFS) < background_thresh
				&& min_pages <= 0)
			break;

		wbc.encountered_congestion = 0;
		wbc.nr_to_write = max_writeback_pages;
		wbcqq.pages_skipped = 0;
		writeback_inodes(&wbc);
		min_pages -= max_writeback_pages - wbc.nr_to_write;

		if (wbc.nr_to_write > 0 || wbc.pages_skipped > 0) {
			/* Wrote less than expected */
            // IOキューが掃けるのを待つ。 STATE D
			blk_congestion_wait(WRITE, HZ/10);

            // ここで break して終わるのは何故?
			if (!wbc.encountered_congestion)
				break;
		}
	}
	trace_mm_pdflush_bgwriteout(_min_pages);
}
```

## 2. wb_timer_fn -> wb_kupdate

wb_kupdate は固定のタイマーとして定義されていて呼び出しされる

```
static DEFINE_TIMER(wb_timer, wb_timer_fn, 0, 0);

static void wb_timer_fn(unsigned long unused)
{
	if (pdflush_operation(wb_kupdate, 0) < 0)
		mod_timer(&wb_timer, jiffies + HZ); /* delay 1 second */
}
```

#### wb_kupdate

kupdate 古い Dirty ページを定期的に writeback する

 * vm.dirty_expire_interval         
 * vm.dirty_writeback_interval

が関係してくる

```c

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
		.older_than_this = &oldest_jif, // これより古い Dirty が writeback される
                                        // vm.dirty_expire_centisecs
		.nr_to_write	= 0,
		.nonblocking	= 1,
		.for_kupdate	= 1,
		.range_cyclic	= 1,
		.range_start	= 0,
		.range_end 	= LLONG_MAX,
	};

	sync_supers();

    // vm.dirty_writeback_centisecs と vm.dirty_expire_centisecs
	oldest_jif = jiffies - msecs_to_jiffies(dirty_expire_interval * 10);
	start_jif = jiffies;
	next_jif = start_jif + msecs_to_jiffies(dirty_writeback_interval * 10);

    // NFS を無視したら、Dirty ページ
    // inode ???
	nr_to_write = global_page_state(NR_FILE_DIRTY) +
			global_page_state(NR_UNSTABLE_NFS) +
			(inodes_stat.nr_inodes - inodes_stat.nr_unused);
	trace_mm_pdflush_kupdate(nr_to_write);
    
	while (nr_to_write > 0) {
		wbc.encountered_congestion = 0;
		wbc.nr_to_write = max_writeback_pages;

        // ここで writeback 祭りに入る
		writeback_inodes(&wbc);

		if (wbc.nr_to_write > 0) {
            // キューがはけるのを待つ
			if (wbc.encountered_congestion)
				blk_congestion_wait(WRITE, HZ/10);
			else
				break;	/* All the old data is written */
		}
		nr_to_write -= max_writeback_pages - wbc.nr_to_write;
	}
	if (time_before(next_jif, jiffies + HZ))
		next_jif = jiffies + HZ;

    // 次の起床タイミングをタイマーにぶっこむ
	if (dirty_writeback_interval)
		mod_timer(&wb_timer, next_jif);
}
```

#### writeback_inodes

writeback の肝となる関数

```c
/*
 * Start writeback of dirty pagecache data against all unlocked inodes.
 *
 * Note:
 * We don't need to grab a reference to superblock here. If it has non-empty
 * ->s_dirty it's hadn't been killed yet and kill_super() won't proceed
 * past sync_inodes_sb() until both the ->s_dirty and ->s_io lists are
 * empty. Since __sync_single_inode() regains inode_lock before it finally moves
 * inode from superblock lists we are OK.
 *
 * If `older_than_this' is non-zero then only flush inodes which have a
 * flushtime older than *older_than_this.
 *
 * If `bdi' is non-zero then we will scan the first inode against each
 * superblock until we find the matching ones.  One group will be the dirty
 * inodes against a filesystem.  Then when we hit the dummy blockdev superblock,
 * sync_sb_inodes will seekout the blockdev which matches `bdi'.  Maybe not
 * super-efficient but we're about to do a ton of I/O...
 */
void
writeback_inodes(struct writeback_control *wbc)
{
	struct super_block *sb;

	might_sleep();
	spin_lock(&sb_lock);
restart:
	sb = sb_entry(super_blocks.prev);
    // superblock を全部いてレートする
	for (; sb != sb_entry(&super_blocks); sb = sb_entry(sb->s_list.prev)) {

        // s_dirty ... Dirty な inode
        // s_io    ... Writeback 中な inode

		if (!list_empty(&sb->s_dirty) || !list_empty(&sb->s_io)) {
			/* we're making our own get_super here */
			sb->s_count++;
			spin_unlock(&sb_lock);
			/*
			 * If we can't get the readlock, there's no sense in
			 * waiting around, most of the time the FS is going to
			 * be unmounted by the time it is released.
			 */
			if (down_read_trylock(&sb->s_umount)) {
				if (sb->s_root) {
					spin_lock(&inode_lock);
					sync_sb_inodes(sb, wbc);
                    					spin_unlock(&inode_lock);
				}
				up_read(&sb->s_umount);
			}
			spin_lock(&sb_lock);
			if (__put_super_and_need_restart(sb))
				goto restart;
		}
		if (wbc->nr_to_write <= 0)
			break;
	}
	spin_unlock(&sb_lock);
}
```

#### sync_sb_inodes

 * superblock の dirty inode を writeback する

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

        // Dirty な inode を書き出す必要のないデバイス (擬似デバイス???)
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

        // congested ならスキップ?
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
        // 他の pdflush がキューを掴んでる?
		if (current_is_pdflush() && !writeback_acquire(bdi))
			break;

        // dirty で古いページかかえてる inode を writeback
		BUG_ON(inode->i_state & I_FREEING);
		__iget(inode);
		pages_skipped = wbc->pages_skipped;

        // ->
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

#### __writeback_single_inode

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
     // inode が I_LOCK なら TASK_UNINTERRUPTIBLE で待つ
     // writeback が直列化される
	if (inode->i_state & I_LOCK) {
		DEFINE_WAIT_BIT(wq, &inode->i_state, __I_LOCK);

		wqh = bit_waitqueue(&inode->i_state, __I_LOCK);

        //  STATE D で待ちうるよ
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

#### __sync_single_inode

 * inode の Dirty ページをディスクに書き出す。writeback, 同期
 * wait = 1 なら待つ

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
    // IO完了を待つかどうかは、↓ の filemap_fdatawait の呼び出しに依る
    // ->
	ret = do_writepages(mapping, wbc);

	/* Don't write the inode if only I_DIRTY_PAGES was set */
    // inode の同期待ち?
    // ->
	if (dirty & (I_DIRTY_SYNC | I_DIRTY_DATASYNC)) {
		int err = write_inode(inode, wait);
		if (ret == 0)
			ret = err;
	}

   // データの同期待ち?
   // ->
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

#### write_inode

ファイルシステムの実装によって内容が違うようだ

```
static int write_inode(struct inode *inode, int sync)
{
	if (inode->i_sb->s_op->write_inode && !is_bad_inode(inode))
		return inode->i_sb->s_op->write_inode(inode, sync);
	return 0;
}
```

#### do_writepages

 * writepages メソッドで page の書き出し
 * ファイルシステムによって実装違うので、個別に見ていくのがよい

```
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
```

#### filemap_fdatawait

データの同期。アドレス空間を舐めて Dirty なページを writeback すんのかな?

```
/**
 * filemap_fdatawait - wait for all under-writeback pages to complete
 * @mapping: address space structure to wait for
 *
 * Walk the list of under-writeback pages of the given address space
 * and wait for all of them.
 */
int filemap_fdatawait(struct address_space *mapping)
{
	loff_t i_size = i_size_read(mapping->host);

    // サイズ0 なら待たない〜
	if (i_size == 0)
		return 0;

    // ->
	return wait_on_page_writeback_range(mapping, 0,
				(i_size - 1) >> PAGE_CACHE_SHIFT);
}
EXPORT_SYMBOL(filemap_fdatawait);
```

#### wait_on_page_writeback_range

```c
/**
 * wait_on_page_writeback_range - wait for writeback to complete
 * @mapping:	target address_space
 * @start:	beginning page index
 * @end:	ending page index
 *
 * Wait for writeback to complete against pages indexed by start->end
 * inclusive
 */
int wait_on_page_writeback_range(struct address_space *mapping,
				pgoff_t start, pgoff_t end)
{
	struct pagevec pvec;
	int nr_pages;
	int ret = 0;
	pgoff_t index;

	if (end < start)
		return 0;

	pagevec_init(&pvec, 0);
	index = start;
	while ((index <= end) &&
			(nr_pages = pagevec_lookup_tag(&pvec, mapping, &index,
			PAGECACHE_TAG_WRITEBACK,
			min(end - index, (pgoff_t)PAGEVEC_SIZE-1) + 1)) != 0) {
		unsigned i;

		for (i = 0; i < nr_pages; i++) {
			struct page *page = pvec.pages[i];

			/* until radix tree lookup accepts end_index */
			if (page->index > end)
				continue;

            // ここで ~~Dirty~~ Writeback ページの writeback 待ち
			wait_on_page_writeback(page);
            // なんかデバイスがエラッたら EIO
			if (TestClearPageError(page))
				ret = -EIO;
		}
		pagevec_release(&pvec);
		cond_resched();
	}

	/* Check for outstanding write errors */
	if (test_and_clear_bit(AS_ENOSPC, &mapping->flags))
		ret = -ENOSPC;
	if (test_and_clear_bit(AS_EIO, &mapping->flags))
		ret = -EIO;

	return ret;
}
```

#### wait_on_page_writeback

 * **Writeback** なページの書き出し待ち
   * Writeback でなければ、全部書き出し済み?
 * wait_on_page_bit は TASK_UNINTERRUPTIBLE
 * I/Oリクエストはどこで出してるんだっけ? -> do_writepages

```
/* 
 * Wait for a page to complete writeback
 */
static inline void wait_on_page_writeback(struct page *page)
{
	if (PageWriteback(page))
		wait_on_page_bit(page, PG_writeback);
}
```