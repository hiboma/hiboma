# vm.dirty_bytes, vm.dirty_background_bytes

深遠な理由から調査しているソースは CentOS5.9

## vm.dirty_bytes の定義

```c
	{
		.ctl_name	= VM_DIRTY_BYTES,
		.procname	= "dirty_bytes",
		.data		= &vm_dirty_bytes,
		.maxlen		= sizeof(vm_dirty_bytes),
		.mode		= 0644,
		.proc_handler	= &proc_dointvec,
		.strategy	= &sysctl_intvec,
		.extra1		= &zero,
	},
```

## 参照される場所

`get_dirty_limits` のでしか使用されていない

```c
void
get_dirty_limits(long *pbackground, long *pdirty,
					struct address_space *mapping)

//...

	if (vm_dirty_bytes)
		dirty = DIV_ROUND_UP(vm_dirty_bytes, PAGE_SIZE);
	else {
		dirty_ratio = vm_dirty_ratio;

		/* if vm_dirty_ratio is 100 dont limit to 1/2 unmapped_ratio */
		if ((dirty_ratio > unmapped_ratio / 2) && (dirty_ratio != 100))
			dirty_ratio = unmapped_ratio / 2;

		if (dirty_ratio < 5)
			dirty_ratio = 5;

		dirty = (dirty_ratio * available_memory) / 100;
	}
```

#### ポイント

 * `vm_dirty_bytes > 0` ならば vm.dirty_ratio の代わりになる
 * ページサイズに切り上げ? ている

## vm.dirty_background_bytes の定義

```c
	{
		.ctl_name	= VM_DIRTY_BACKGND_BYTES,
		.procname	= "dirty_background_bytes",
		.data		= &dirty_background_bytes,
		.maxlen		= sizeof(dirty_background_bytes),
		.mode		= 0644,
		.proc_handler	= &proc_dointvec,
		.strategy	= &sysctl_intvec,
		.extra1		= &zero,
	},
```

## 参照される場所

`vm.dirty_bytes` と同様に、 `get_dirty_limits` の一箇所だけ

```c
void
get_dirty_limits(long *pbackground, long *pdirty,
					struct address_space *mapping)

//...

	if (dirty_background_bytes)
		background = DIV_ROUND_UP(dirty_background_bytes, PAGE_SIZE);
	else {
		background_ratio = dirty_background_ratio;
		if (background_ratio >= dirty_ratio)
			background_ratio = dirty_ratio / 2;

		background = (background_ratio * available_memory) / 100;
	}
```

## get_dirty_limits

```c
// clamping ... 締める、固定させる。 foreground での diry 書き出しのことを指している
/*
 * Work out the current dirty-memory clamping and background writeout
 * thresholds.
 *
 * The main aim here is to lower them aggressively if there is a lot of mapped
 * memory around.  To avoid stressing page reclaim with lots of unreclaimable
 * pages.  It is better to clamp down on writers than to start swapping, and
 * performing lots of scanning.
 *
 * We only allow 1/2 of the currently-unmapped memory to be dirtied.
 *
 * We don't permit the clamping level to fall below 5% - that is getting rather
 * excessive.
 *
 * foreground は 5% 以下にはできない
 *
 * We make sure that the background writeout level is below the adjusted
 * clamping level.
 *
 * background < foreground となるよにする
 */
void
get_dirty_limits(long *pbackground, long *pdirty,
					struct address_space *mapping)
{
	int background_ratio;		/* Percentages */
	int dirty_ratio;
	int unmapped_ratio;
	long background;
	long dirty;
	unsigned long available_memory = total_pages;
	struct task_struct *tsk;

    // unmapped = NR_FILE_MAPPED - NR_ANON_PAGES
	unmapped_ratio = 100 - ((global_page_state(NR_FILE_MAPPED) +
				global_page_state(NR_ANON_PAGES)) * 100) /
					total_pages;

    // foreground で回収
	if (vm_dirty_bytes)
		dirty = DIV_ROUND_UP(vm_dirty_bytes, PAGE_SIZE);
	else {
		dirty_ratio = vm_dirty_ratio;

		/* if vm_dirty_ratio is 100 dont limit to 1/2 unmapped_ratio */
		if ((dirty_ratio > unmapped_ratio / 2) && (dirty_ratio != 100))
			dirty_ratio = unmapped_ratio / 2;

        // 5% より小さくならない
		if (dirty_ratio < 5)
			dirty_ratio = 5;

		dirty = (dirty_ratio * available_memory) / 100;
	}

    // background で回収
	if (dirty_background_bytes)
		background = DIV_ROUND_UP(dirty_background_bytes, PAGE_SIZE);
	else {
		background_ratio = dirty_background_ratio;
		if (background_ratio >= dirty_ratio)
			background_ratio = dirty_ratio / 2;

		background = (background_ratio * available_memory) / 100;
	}

    // フラグ経つのは NFS の時だけかな?
    // #define PF_LESS_THROTTLE 0x00100000	/* Throttle me less: I clean memory */
    // リアルタイムタスクの場合は、 1/4 に下げられている
	tsk = current;
	if (tsk->flags & PF_LESS_THROTTLE || rt_task(tsk)) {
		background += background / 4;
		dirty += dirty / 4;
	}
	*pbackground = background;
	*pdirty = dirty;
}
EXPORT_SYMBOL_GPL(get_dirty_limits);
```

## get_dirty_limits を呼び出す場所

```c
1. static void balance_dirty_pages(struct address_space *mapping)
2. static void background_writeout(unsigned long _min_pages)`
3. void throttle_vm_writeout(void)
```

## background_writeout

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

        // 閾値を取る
		get_dirty_limits(&background_thresh, &dirty_thresh, NULL);

		if (global_page_state(NR_FILE_DIRTY) +
			global_page_state(NR_UNSTABLE_NFS) < background_thresh
				&& min_pages <= 0)
			break;

		wbc.encountered_congestion = 0;
		wbc.nr_to_write = max_writeback_pages;
		wbc.pages_skipped = 0;
		writeback_inodes(&wbc);
		min_pages -= max_writeback_pages - wbc.nr_to_write;
		if (wbc.nr_to_write > 0 || wbc.pages_skipped > 0) {
			/* Wrote less than expected */
			blk_congestion_wait(WRITE, HZ/10);
			if (!wbc.encountered_congestion)
				break;
		}
	}
	trace_mm_pdflush_bgwriteout(_min_pages);
}
```

 * `(global_page_state(NR_FILE_DIRTY) + global_page_state(NR_UNSTABLE_NFS) < background_thresh && min_pages <= 0` の条件
 * NFS はとりあえず無視して読もう
 * **vm.max_writeback_pages** が出てくる
   * http://itline.jp/~svx/diary/?date=200807
   * `vm.max_writeback_pages = 1024` デフォルトは 1024?
   * balance, kupdate, bdflush モード

```c
/*
 * Start writeback of `nr_pages' pages.  If `nr_pages' is zero, write back
 * the whole world.  Returns 0 if a pdflush thread was dispatched.  Returns
 * -1 if all pdflush threads were busy.
 */
int wakeup_pdflush(long nr_pages)
{
	if (nr_pages == 0)
		nr_pages = global_page_state(NR_FILE_DIRTY) +
				global_page_state(NR_UNSTABLE_NFS);
	return pdflush_operation(background_writeout, nr_pages);
}
```

## throttle_vm_writeout

```
# いろんなパスがあるけど、一部だけ
__alloc_pages
 try_to_free_pages
  shrink_zones
   shrink_zone
    throttle_vm_writeout
     blk_congestion_wait
```    

```c
void throttle_vm_writeout(void)
{
	long background_thresh;
	long dirty_thresh;

        for ( ; ; ) {
		get_dirty_limits(&background_thresh, &dirty_thresh, NULL);

                /*
                 * Boost the allowable dirty threshold a bit for page
                 * allocators so they don't get DoS'ed by heavy writers
                 */
                dirty_thresh += dirty_thresh / 10;      /* wheeee... */

                if (global_page_state(NR_UNSTABLE_NFS) +
			global_page_state(NR_WRITEBACK) <= dirty_thresh)
                        	break;
                blk_congestion_wait(WRITE, HZ/10); # ★
        }
}
```

`NR_WRITEBACK + NR_UNSTABLE_NFS < dirty_thresh` として比較しているので、 Dirty ページでは無いな

##### blk_congestion_wait

```c
/**
 * blk_congestion_wait - wait for a queue to become uncongested
 * @rw: READ or WRITE
 * @timeout: timeout in jiffies
 *
 * Waits for up to @timeout jiffies for a queue (any queue) to exit congestion.
 * If no queues are congested then just wait for the next request to be
 * returned.
 */
long blk_congestion_wait(int rw, long timeout)
{
	long ret;
	DEFINE_WAIT(wait);
	wait_queue_head_t *wqh = &congestion_wqh[rw];

	prepare_to_wait(wqh, &wait, TASK_UNINTERRUPTIBLE);
	ret = io_schedule_timeout(timeout);
	finish_wait(wqh, &wait);
	return ret;
}
```