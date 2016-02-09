# pdflush

>
>10. Flusher thread
> Linux 2.6 before – bdflush (dirty_background_ratio)
>　　 kupdated (dirty_expire_interval)
>　　　　　　　　(dirty_writeback_interval)
> Linux 2.6    – pdfush : 2 to 8 threads
> Linux 2.6.32 – flusher : one thread for one block device
>
> http://www.slideshare.net/huangachou/ch16-26731925

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

メインとなるループ

 * pdflush_operation 経由で my_work->list に関数ポインタがつっこまれる?

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
        
        // ここでお仕事
		(*my_work->fn)(my_work->arg0);

		/*
		 * Thread creation: For how long have there been zero
		 * available threads?
		 */
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

## pdflush_operation の呼び出し

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

## wb_kupdate

kupdate 古い Dirty ページを定期的に writeback する

 * vm.dirty_expire_interval         
 * vm.dirty_writeback_interval

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
		.older_than_this = &oldest_jif,
		.nr_to_write	= 0,
		.nonblocking	= 1,
		.for_kupdate	= 1,
		.range_cyclic	= 1,
		.range_start	= 0,
		.range_end 	= LLONG_MAX,
	};

	sync_supers();

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

#### writeback_inodes

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
	for (; sb != sb_entry(&super_blocks); sb = sb_entry(sb->s_list.prev)) {
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