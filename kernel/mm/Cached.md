# /proc/meminfo の Cached

```
$ cat /proc/meminfo 
MemTotal:       32828144 kB
MemFree:         7946436 kB
Buffers:         4520132 kB
Cached:         14997108 kB # ★
SwapCached:        55932 kB
Active:         12755820 kB
```

/proc/meminfo の **Cached** は、 free コマンドの **cached** の数値としても使われている

```n
$ free             
             total       used       free     shared    buffers     cached
Mem:      32828144   31563012    1265132          0    4732700   15230408
-/+ buffers/cache:   11599904   21228240
Swap:      2097148      98652    1998496
```

で、この数値は、いったい何? となる。

## 実態

```c
global_page_state(NR_FILE_PAGES) - total_swapcache_pages - i.bufferram;
```

これが Cached の実態。ソースを読んでください

さらに ↓ の実装を読めば明らかになるが、 **Cacehd** では slabキャッシュ が換算されていない。
slab キャッシュを浪費する環境では free コマンドで正確に「利用可能なメモリ」を出すことはできない [refs MemAvailable](./MemAvailable.md)

## 実装

/proc/meminfo の **Cached** は fs/proc/meminfo.c で下記のように計算されている

```c
	cached = global_page_state(NR_FILE_PAGES) -
			total_swapcache_pages - i.bufferram;
	if (cached < 0)
		cached = 0;

	/*
	 * Tagged format, for easy grepping and expansion.
	 */
	seq_printf(m,
		"MemTotal:       %8lu kB\n"
		"MemFree:        %8lu kB\n"
		"Buffers:        %8lu kB\n"
		"Cached:         %8lu kB\n"

//...

		K(i.totalram),
		K(i.freeram),
		K(i.bufferram),
		K(cached),
```

計算式は、下記の通りであーる

```c
global_page_state(NR_FILE_PAGES) - total_swapcache_pages - i.bufferram;
```

### global_page_state(NR_FILE_PAGES) とは?

> The size of the pagecache is the number of file backed
> pages in a zone which is available through NR_FILE_PAGES.
>
> http://lwn.net/Articles/218890/

 * file bached な ページキャッシュの数
 * tmpfs, ramfs は含まない

### total_swapcache_pages とは?

```c
/*
 * __add_to_swap_cache resembles add_to_page_cache_locked on swapper_space,
 * but sets SwapCache flag and private instead of mapping and index.
 */
static int __add_to_swap_cache(struct page *page, swp_entry_t entry)
{
	int error;

	VM_BUG_ON(!PageLocked(page));
	VM_BUG_ON(PageSwapCache(page));
	VM_BUG_ON(!PageSwapBacked(page));

	page_cache_get(page);
	SetPageSwapCache(page);
	set_page_private(page, entry.val);

	spin_lock_irq(&swapper_space.tree_lock);
	error = radix_tree_insert(&swapper_space.page_tree, entry.val, page);
	if (likely(!error)) {
		total_swapcache_pages++; // ★
		__inc_zone_page_state(page, NR_FILE_PAGES);
		INC_CACHE_INFO(add_total);
	}
```

```c
/*
 * This must be called only on pages that have
 * been verified to be in the swap cache.
 */
void __delete_from_swap_cache(struct page *page)
{
	VM_BUG_ON(!PageLocked(page));
	VM_BUG_ON(!PageSwapCache(page));
	VM_BUG_ON(PageWriteback(page));

	radix_tree_delete(&swapper_space.page_tree, page_private(page));
	set_page_private(page, 0);
	ClearPageSwapCache(page);
	total_swapcache_pages--; // ★
	__dec_zone_page_state(page, NR_FILE_PAGES);
	INC_CACHE_INFO(del_total);
}
```

### i.bufferram とは?

バッファ

```c
void si_meminfo(struct sysinfo *val)
{
	val->totalram = totalram_pages;
	val->sharedram = 0;
	val->freeram = global_page_state(NR_FREE_PAGES);
	val->bufferram = nr_blockdev_pages(); // ★
	val->totalhigh = totalhigh_pages;
	val->freehigh = nr_free_highpages();
	val->mem_unit = PAGE_SIZE;
}
```