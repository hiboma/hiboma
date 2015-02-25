# Buffers:

> ディスクキャッシュのひとつ。Bufferはディスクのブロック単位のキャッシュを行なう。ブロック Read/WriteはBufferを経由して行なわれる。このため、ディスク上のi-nodeなどのメタデータはBufferにキャッシュされる。
> refs http://wiki.bit-hive.com/linuxkernelmemo/pg/Buffer

ブロック単位てのがミソですなー

## fs/proc/meminfo.c

```c
static int meminfo_proc_show(struct seq_file *m, void *v)
{
	struct sysinfo i;

//...

    seq_printf(m,
		"MemTotal:       %8lu kB\n"
		"MemFree:        %8lu kB\n"
		"Buffers:        %8lu kB\n"

//...
        K(i.bufferram),
```

sysinfo の値をとっているのは si_meminfo

```
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

`nr_blockdev_pages();` が **Buffers:** の正体

## nr_blockdev_pages

 * struct block_device をイテレート
 * bd_inode->imapping->nr_pages を加算
   * これなに?

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


