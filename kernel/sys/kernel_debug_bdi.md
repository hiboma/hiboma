## /sys/kernel/debug/bdi/<major>:<minor>/stats

linux-3.10.0-327.el7.centos.x86_64/mm/backing-dev.c

 * **BdiDirtyThresh**, **DirtyThresh** は vm.dirty_ratio, vm.dirty_background_ratio から自動計算
 * 

```
$ cat /sys/kernel/debug/bdi/253:1/stats
BdiWriteback:                0 kB
BdiReclaimable:             32 kB
BdiDirtyThresh:         114108 kB // BDI の 閾値
DirtyThresh:            114108 kB // vm.dirty_ratio            から計算したグローバルな閾値
BackgroundThresh:       102400 kB // vm.dirty_background_ratio から計算したグローバルな閾値
BdiDirtied:            5520704 kB // 過去の統計
BdiWritten:            3120192 kB // 実際に書き込んだデータ量?
BdiWriteBandwidth:       63680 kBps
b_dirty:                     7    // dirty な inode 数
b_io:                        0
b_more_io:                   0
bdi_list:                    1
state:                       8

// state の一覧???
// /*
//  * Bits in backing_dev_info.state
//  */
// enum bdi_state {
// 	BDI_wb_alloc,		/* Default embedded wb allocated */
// 	BDI_async_congested,	/* The async (write) queue is getting full */
// 	BDI_sync_congested,	/* The sync queue is getting full */
// 	BDI_registered,		/* bdi_register() was done */
// 	BDI_writeback_running,	/* Writeback is in progress */
// 	BDI_unused,		/* Available bits start here */
// };

```

## bdi_debug_stats_show

ここを辿ってどんな数値を出しているかを追う

```c
static int bdi_debug_stats_show(struct seq_file *m, void *v)
{
	struct backing_dev_info *bdi = m->private;
	struct bdi_writeback *wb = &bdi->wb;
	unsigned long background_thresh;
	unsigned long dirty_thresh;
	unsigned long bdi_thresh;
	unsigned long nr_dirty, nr_io, nr_more_io;
	struct inode *inode;

	nr_dirty = nr_io = nr_more_io = 0;
	spin_lock(&wb->list_lock);

    // dirty 
	list_for_each_entry(inode, &wb->b_dirty, i_wb_list)
		nr_dirty++;
        
    // parked for writeback
	list_for_each_entry(inode, &wb->b_io, i_wb_list)
		nr_io++;

    // parked for more writeback 
	list_for_each_entry(inode, &wb->b_more_io, i_wb_list)
		nr_more_io++;
	spin_unlock(&wb->list_lock);

    // グローバル扱いされるようになった
	global_dirty_limits(&background_thresh, &dirty_thresh);

    // BDI の dirty threshold
	bdi_thresh = bdi_dirty_limit(bdi, dirty_thresh);

#define K(x) ((x) << (PAGE_SHIFT - 10))
	seq_printf(m,
		   "BdiWriteback:       %10lu kB\n"
		   "BdiReclaimable:     %10lu kB\n"
		   "BdiDirtyThresh:     %10lu kB\n"
		   "DirtyThresh:        %10lu kB\n"
		   "BackgroundThresh:   %10lu kB\n"
		   "BdiDirtied:         %10lu kB\n"   // Dirty のサイズ
		   "BdiWritten:         %10lu kB\n"   // 減らない。純増するだけ
		   "BdiWriteBandwidth:  %10lu kBps\n"
		   "b_dirty:            %10lu\n"
		   "b_io:               %10lu\n"
		   "b_more_io:          %10lu\n"
		   "bdi_list:           %10u\n"
		   "state:              %10lx\n",

           // 量
		   (unsigned long) K(bdi_stat(bdi, BDI_WRITEBACK)),   // percpu_counter
		   (unsigned long) K(bdi_stat(bdi, BDI_RECLAIMABLE)),
		   K(bdi_thresh),
		   K(dirty_thresh),
		   K(background_thresh),
		   (unsigned long) K(bdi_stat(bdi, BDI_DIRTIED)),
		   (unsigned long) K(bdi_stat(bdi, BDI_WRITTEN)),
		   (unsigned long) K(bdi->write_bandwidth),

           // inode数
		   nr_dirty,   
		   nr_io,
		   nr_more_io,
		   !list_empty(&bdi->bdi_list), bdi->state);
#undef K

	return 0;
}
```

あとは debugfs の使い方例みたいなコードが並んでいる。

```c
static void bdi_debug_init(void)
{
	bdi_debug_root = debugfs_create_dir("bdi", NULL);
}

static int bdi_debug_stats_open(struct inode *inode, struct file *file)
{
	return single_open(file, bdi_debug_stats_show, inode->i_private);
}

static const struct file_operations bdi_debug_stats_fops = {
	.open		= bdi_debug_stats_open,
	.read		= seq_read,
	.llseek		= seq_lseek,
	.release	= single_release,
};

static void bdi_debug_register(struct backing_dev_info *bdi, const char *name)
{
	bdi->debug_dir = debugfs_create_dir(name, bdi_debug_root);
	bdi->debug_stats = debugfs_create_file("stats", 0444, bdi->debug_dir,
					       bdi, &bdi_debug_stats_fops);
}

static void bdi_debug_unregister(struct backing_dev_info *bdi)
{
	debugfs_remove(bdi->debug_stats);
	debugfs_remove(bdi->debug_dir);
}
```

## bdi_dirty_limit

```c
/**
 * bdi_dirty_limit - @bdi's share of dirty throttling threshold
 * @bdi: the backing_dev_info to query
 * @dirty: global dirty limit in pages
 *
 * Returns @bdi's dirty limit in pages. The term "dirty" in the context of
 * dirty balancing includes all PG_dirty, PG_writeback and NFS unstable pages.
 *
 * Note that balance_dirty_pages() will only seriously take it as a hard limit
 * when sleeping max_pause per page is not enough to keep the dirty pages under
 * control. For example, when the device is completely stalled due to some error
 * conditions, or when there are 1000 dd tasks writing to a slow 10MB/s USB key.
 * In the other normal situations, it acts more gently by throttling the tasks
 * more (rather than completely block them) when the bdi dirty pages go high.
 *
 * It allocates high/low dirty limits to fast/slow devices, in order to prevent
 * - starving fast devices
 * - piling up dirty pages (that will take long time to sync) on slow devices
 *
 * The bdi's share of dirty limit will be adapting to its throughput and
 * bounded by the bdi->min_ratio and/or bdi->max_ratio parameters, if set.
 */
unsigned long bdi_dirty_limit(struct backing_dev_info *bdi, unsigned long dirty)
{
	u64 bdi_dirty;
	long numerator, denominator;

	/*
	 * Calculate this BDI's share of the dirty ratio.
	 */
	bdi_writeout_fraction(bdi, &numerator, &denominator);

	bdi_dirty = (dirty * (100 - bdi_min_ratio)) / 100;
	bdi_dirty *= numerator;
	do_div(bdi_dirty, denominator);

	bdi_dirty += (dirty * bdi->min_ratio) / 100;
	if (bdi_dirty > (dirty * bdi->max_ratio) / 100)
		bdi_dirty = dirty * bdi->max_ratio / 100;

	return bdi_dirty;
}
```