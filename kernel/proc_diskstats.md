# /proc/diskstats

see also https://www.kernel.org/doc/Documentation/block/stat.txt

## CentOS5

```
struct seq_operations diskstats_op = {
	.start	= diskstats_start,
	.next	= diskstats_next,
	.stop	= diskstats_stop,
	.show	= diskstats_show
};
```

### diskstats_start

```c
/*
 * aggregate disk stat collector.  Uses the same stats that the sysfs
 * entries do, above, but makes them available through one seq_file.
 * Watching a few disks may be efficient through sysfs, but watching
 * all of them will be more efficient through this interface.
 *
 * The output looks suspiciously like /proc/partitions with a bunch of
 * extra fields.
 */

/* iterator */
static void *diskstats_start(struct seq_file *part, loff_t *pos)
{
	loff_t k = *pos;
	struct list_head *p;

	mutex_lock(&block_subsys_lock);
	list_for_each(p, &block_subsys.kset.list)
		if (!k--)
			return list_entry(p, struct gendisk, kobj.entry);
	return NULL;
}
```

```c
static void *diskstats_next(struct seq_file *part, void *v, loff_t *pos)
{
	struct list_head *p = ((struct gendisk *)v)->kobj.entry.next;
	++*pos;
	return p==&block_subsys.kset.list ? NULL :
		list_entry(p, struct gendisk, kobj.entry);
}
```

`struct gendisk` が肝そう

### struct gendisk

```
struct gendisk {
	int major;			/* major number of driver */
	int first_minor;
	int minors;                     /* maximum number of minors, =1 for
                                         * disks that can't be partitioned. */
	char disk_name[32];		/* name of major driver */
	struct hd_struct **part;	/* [indexed by minor] */
	int part_uevent_suppress;
	struct block_device_operations *fops;
	struct request_queue *queue;
	void *private_data;
	sector_t capacity;

	int flags;
	struct device *driverfs_dev;
	struct kobject kobj;
	struct kobject *holder_dir;
	struct kobject *slave_dir;

	struct timer_rand_state *random;
	int policy;

	atomic_t sync_io;		/* RAID */
	unsigned long stamp;
	int in_flight;
#ifdef	CONFIG_SMP
	struct disk_stats *dkstats;
#else
	struct disk_stats dkstats;
#endif
};
```

### disk_show

```c
static int diskstats_show(struct seq_file *s, void *v)
{
	struct gendisk *gp = v;
	char buf[BDEVNAME_SIZE];
	int n = 0;

	/*
	if (&sgp->kobj.entry == block_subsys.kset.list.next)
		seq_puts(s,	"major minor name"
				"     rio rmerge rsect ruse wio wmerge "
				"wsect wuse running use aveq"
				"\n\n");
	*/
 
	preempt_disable();
	disk_round_stats(gp);
	preempt_enable();
	seq_printf(s, "%4d %4d %s %lu %lu %llu %u %lu %lu %llu %u %u %u %u\n",
		gp->major, n + gp->first_minor, disk_name(gp, n, buf),
		disk_stat_read(gp, ios[0]), disk_stat_read(gp, merges[0]),
		(unsigned long long)disk_stat_read(gp, sectors[0]),
		jiffies_to_msecs(disk_stat_read(gp, ticks[0])),
		disk_stat_read(gp, ios[1]), disk_stat_read(gp, merges[1]),
		(unsigned long long)disk_stat_read(gp, sectors[1]),
		jiffies_to_msecs(disk_stat_read(gp, ticks[1])),
		gp->in_flight,
		jiffies_to_msecs(disk_stat_read(gp, io_ticks)),
		jiffies_to_msecs(disk_stat_read(gp, time_in_queue)));

    // パーティション別の統計を出す
	/* now show all non-0 size partitions of it */
	for (n = 0; n < gp->minors - 1; n++) {
		struct hd_struct *hd;

		rcu_read_lock();
		hd = rcu_dereference(gp->part[n]);
		if (!hd || !hd->nr_sects) {
			rcu_read_unlock();
			continue;
		}

		preempt_disable();
		part_round_stats(hd);
		preempt_enable();
		seq_printf(s, "%4d %4d %s %lu %lu %llu "
			   "%u %lu %lu %llu %u %u %u %u\n",
			   gp->major, n + gp->first_minor + 1,
			   disk_name(gp, n + 1, buf),
			   part_stat_read(hd, ios[0]),
			   part_stat_read(hd, merges[0]),
			   (unsigned long long)part_stat_read(hd, sectors[0]),
			   jiffies_to_msecs(part_stat_read(hd, ticks[0])),
			   part_stat_read(hd, ios[1]),
			   part_stat_read(hd, merges[1]),
			   (unsigned long long)part_stat_read(hd, sectors[1]),
			   jiffies_to_msecs(part_stat_read(hd, ticks[1])),
			   get_partstats(hd)->in_flight,
			   jiffies_to_msecs(part_stat_read(hd, io_ticks)),
			   jiffies_to_msecs(part_stat_read(hd, time_in_queue))
			);
		rcu_read_unlock();
	}
 
	return 0;
}
```

### disk_round_stats

__disk_stat_add で percpu なデータから数値を取って統計を足す。

 * disk->in_flight
   * ドライバに I/O 発行したけど未完了
 * time_in_queue
   * I/O リクエストのブロックデバイス待ちの秒数。リクエストが複数なら総和
   * キューで待ってるリクエスト数を出すには?
 * io_ticks

```c
/*
 * disk_round_stats()	- Round off the performance stats on a struct
 * disk_stats.
 *
 * The average IO queue length and utilisation statistics are maintained
 * by observing the current state of the queue length and the amount of
 * time it has been in this state for.
 *
 * Normally, that accounting is done on IO completion, but that can result
 * in more than a second's worth of IO being accounted for within any one
 * second, leading to >100% utilisation.  To deal with that, we call this
 * function to do a round-off before returning the results when reading
 * /proc/diskstats.  This accounts immediately for all queue usage up to
 * the current jiffies and restarts the counters again.
 */
void disk_round_stats(struct gendisk *disk)
{
	unsigned long now = jiffies;

	if (now == disk->stamp)
		return;

	if (disk->in_flight) {
		__disk_stat_add(disk, time_in_queue,
				disk->in_flight * (now - disk->stamp));
		__disk_stat_add(disk, io_ticks, (now - disk->stamp));
	}
	disk->stamp = now;
}
```

### disk_stat_read

統計をよみとるマクロ

```
#define disk_stat_read(gendiskp, field)					\
({									\
	typeof(gendiskp->dkstats->field) res = 0;			\
	int i;								\
	for_each_possible_cpu(i)					\
		res += per_cpu_ptr(gendiskp->dkstats, i)->field;	\
	res;								\
})
```

統計はこんな感じで保持されてる

```
struct disk_stats {
	unsigned long sectors[2];	/* READs and WRITEs */
	unsigned long ios[2];
	unsigned long merges[2];
	unsigned long ticks[2];
	unsigned long io_ticks;
	unsigned long time_in_queue;
};
```

#### time_in_queue

disk_round_stats で統計が加算される