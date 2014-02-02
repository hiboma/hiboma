# free の buffers の数値

free で表示されるバッファは /proc/meminfo の Buffers の数値と一緒

```
open("/proc/meminfo", O_RDONLY)         = 3
```

Buffers の数値は fs/proc/meminfo.c の [si_meminfo](http://lxr.free-electrons.com/ident?v=2.6.32&i=si_meminfo) で {val->bufferram = nr_blockdev_pages();` で代入される

```c
void si_meminfo(struct sysinfo *val)
{
	val->totalram = totalram_pages;
	val->sharedram = 0;
	val->freeram = global_page_state(NR_FREE_PAGES);
	val->bufferram = nr_blockdev_pages();
	val->totalhigh = totalhigh_pages;
	val->freehigh = nr_free_highpages();
	val->mem_unit = PAGE_SIZE;
}
```

nr_blockdev_pages とは???

## nr_blockdev_pages

 * block_device 型ファイルのアドレス空間にマッピングされたページ数を加算 = Buffers = バッファのサイズ


```c
long nr_blockdev_pages(void)
{
	struct block_device *bdev;
	long ret = 0;
	spin_lock(&bdev_lock);
	list_for_each_entry(bdev, &all_bdevs, bd_list) {
		ret += bdev->bd_inode->i_mapping->nrpages;
	}
	spin_unlock(&bdev_lock);
	return ret;
}
```

## struct block_device

```c
struct block_device {
        dev_t                   bd_dev;  /* not a kdev_t - it's a search key */
        struct inode *          bd_inode;       /* will die */
        struct super_block *    bd_super;
        int                     bd_openers;
        struct mutex            bd_mutex;       /* open/close mutex */
        struct list_head        bd_inodes;
        void *                  bd_holder;
        int                     bd_holders;
#ifdef CONFIG_SYSFS
        struct list_head        bd_holder_list;
#endif
        struct block_device *   bd_contains;
        unsigned                bd_block_size;
        struct hd_struct *      bd_part;
        /* number of times partitions within this device have been opened. */
        unsigned                bd_part_count;
        int                     bd_invalidated;
        struct gendisk *        bd_disk;
        struct list_head        bd_list;
        /*
         * Private data.  You must have bd_claim'ed the block_device
         * to use this.  NOTE:  bd_claim allows an owner to claim
         * the same device multiple times, the owner must take special
         * care to not mess up bd_private for that case.
         */
        unsigned long           bd_private;

        /* The counter of freeze processes */
        int                     bd_fsfreeze_count;
        /* Mutex for freeze */
        struct mutex            bd_fsfreeze_mutex;
};
```

block_device の inode 管理とアドレス空間の扱われ方を調べないとだ