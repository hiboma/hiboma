# totalram_pages の初期化

arch/x86/mm/init_64.c

```c
void __init mem_init(void)
{
	long codesize, reservedpages, datasize, initsize;
	unsigned long absent_pages;

	pci_iommu_alloc();

	/* clear_bss() already clear the empty_zero_page */

	reservedpages = 0;

	/* this will put all low memory onto the freelists */
#ifdef CONFIG_NUMA
	totalram_pages = numa_free_all_bootmem();
#else
	totalram_pages = free_all_bootmem();
#endif
```

NUMA構成の場合はメモリのノードごとに free_all_bootmem_core で総ページ数を計算する。非NUMAの場合は、`NODE_DATA(0)` で出す

```
unsigned long __init numa_free_all_bootmem(void)
{
	unsigned long pages = 0;
	int i;

	for_each_online_node(i)
		pages += free_all_bootmem_node(NODE_DATA(i));

	return pages;
}

/**
 * free_all_bootmem - release free pages to the buddy allocator
 *
 * Returns the number of pages actually released.
 */
unsigned long __init free_all_bootmem(void)
{
	return free_all_bootmem_core(NODE_DATA(0)->bdata);
}
```

#### free_all_bootmem_core で扱う struct bootmem_data

メモリノードの物理ページ

 * ノードの最小/最大の pfn = page frame number を保持しちえる
 * `node_min_pfn (start)` 〜 `node_low_pfn(end)`
 
```c
/*
 * node_bootmem_map is a map pointer - the bits represent all physical 
 * memory pages (including holes) on the node.
 */
typedef struct bootmem_data {
	unsigned long node_min_pfn;
	unsigned long node_low_pfn;
	void *node_bootmem_map;
	unsigned long last_end_off;
	unsigned long hint_idx;
	struct list_head list;
} bootmem_data_t;
```

#### free_all_bootmem_core の実装

```c
static unsigned long __init free_all_bootmem_core(bootmem_data_t *bdata)
{
	int aligned;
	struct page *page;
	unsigned long start, end, pages, count = 0;

	if (!bdata->node_bootmem_map)
		return 0;

	start = bdata->node_min_pfn;
	end = bdata->node_low_pfn;

	/*
	 * If the start is aligned to the machines wordsize, we might
	 * be able to free pages in bulks of that order.
	 */
	aligned = !(start & (BITS_PER_LONG - 1));

	bdebug("nid=%td start=%lx end=%lx aligned=%d\n",
		bdata - bootmem_node_data, start, end, aligned);

	while (start < end) {
		unsigned long *map, idx, vec;

        /* ??? */
		map = bdata->node_bootmem_map;

        /* strat ページのインデックス( min_pfn からのインデックス) を出す */
		idx = start - bdata->node_min_pfn;

        /* ビットマップ? */
		vec = ~map[idx / BITS_PER_LONG];

		if (aligned && vec == ~0UL && start + BITS_PER_LONG < end) {
			int order = ilog2(BITS_PER_LONG);

			__free_pages_bootmem(pfn_to_page(start), order);
			count += BITS_PER_LONG;
		} else {
			unsigned long off = 0;

			while (vec && off < BITS_PER_LONG) {
				if (vec & 1) {
					page = pfn_to_page(start + off);
					__free_pages_bootmem(page, 0);
					count++;
				}
				vec >>= 1;
				off++;
			}
		}
		start += BITS_PER_LONG;
	}

    /* 
	page = virt_to_page(bdata->node_bootmem_map);
	pages = bdata->node_low_pfn - bdata->node_min_pfn;
	pages = bootmem_bootmap_pages(pages);
	count += pages;

    /* pages はページの総数 */
	while (pages--)
        /* page は struct page の 配列 */
		__free_pages_bootmem(page++, 0);

	bdebug("nid=%td released=%lx\n", bdata - bootmem_node_data, count);

	return count;
}
```

ノードの struct page を __free_pages_bootmem で初期化する

```c
/*
 * permit the bootmem allocator to evade page validation on high-order frees
 */
void __meminit __free_pages_bootmem(struct page *page, unsigned int order)
{
	if (order == 0) {
		__ClearPageReserved(page);
		set_page_count(page, 0);
		set_page_refcounted(page);
		__free_page(page);
	} else {
		int loop;

		prefetchw(page);
		for (loop = 0; loop < BITS_PER_LONG; loop++) {
			struct page *p = &page[loop];

			if (loop + 1 < BITS_PER_LONG)
				prefetchw(p + 1);
			__ClearPageReserved(p);
			set_page_count(p, 0);
		}

		set_page_refcounted(page);
		__free_pages(page, order);
	}
}
```

# bootmem_data_t の初期化

以下の三つが初期化される

 * node_bootmem_map
 * node_min_pfn (start)
 * node_low_pfn (end)

 ```c
/*
 * Called once to set up the allocator itself.
 */
static unsigned long __init init_bootmem_core(bootmem_data_t *bdata,
	unsigned long mapstart, unsigned long start, unsigned long end)
{
	unsigned long mapsize;

	mminit_validate_memmodel_limits(&start, &end);

    /* 何かの mapping */
	bdata->node_bootmem_map = phys_to_virt(PFN_PHYS(mapstart));
	bdata->node_min_pfn = start;
	bdata->node_low_pfn = end;
	link_bootmem(bdata);

	/*
	 * Initially all pages are reserved - setup_arch() has to
	 * register free RAM areas explicitly.
	 */
	mapsize = bootmap_bytes(end - start);
	memset(bdata->node_bootmem_map, 0xff, mapsize);

	bdebug("nid=%td start=%lx map=%lx end=%lx mapsize=%lx\n",
		bdata - bootmem_node_data, start, mapstart, end, mapsize);

	return mapsize;
}
```

```
 <-------------- mapsize ------------->
 
 +------------------------------------+
 |          node_bootmem_map          |  # 0xff で埋める
 +------------------------------------+
  \                                    \
   \                                    \
 node_min_pfn                      node_low_pfn
```

initmem_init は

 * 32bit  
 * 32bit + CONFIG_NUMA
 * 64bit
 * 64bit + CONFIG_NUMA

の組み合わせがあって、なかなかヤヤコしい。

#### 32bit

 * max_pfn から HIGHMEM のサイズが決定される
 * max_low_pfn から highstart_pfn も決定される
 * highend_pfn

```
void __init initmem_init(unsigned long start_pfn,
				  unsigned long end_pfn)
{
#ifdef CONFIG_HIGHMEM
	highstart_pfn = highend_pfn = max_pfn;
	if (max_pfn > max_low_pfn)
        /* normal ゾーン (低位)終端アドレス = highmemory の開始アドレス */
		highstart_pfn = max_low_pfn;
	e820_register_active_regions(0, 0, highend_pfn);
	sparse_memory_present_with_active_regions(0);
	printk(KERN_NOTICE "%ldMB HIGHMEM available.\n",
		pages_to_mb(highend_pfn - highstart_pfn));
	num_physpages = highend_pfn;
	high_memory = (void *) __va(highstart_pfn * PAGE_SIZE - 1) + 1;
#endif
#ifdef CONFIG_FLATMEM
	max_mapnr = num_physpages;
#endif
	__vmalloc_start_set = true;

	printk(KERN_NOTICE "%ldMB LOWMEM available.\n",
			pages_to_mb(max_low_pfn));

	setup_bootmem_allocator();
}
#endif /* !CONFIG_NEED_MULTIPLE_NODES */
```

#### 64bit

```
#ifndef CONFIG_NUMA
void __init initmem_init(unsigned long start_pfn, unsigned long end_pfn)
{
	unsigned long bootmap_size, bootmap;

	bootmap_size = bootmem_bootmap_pages(end_pfn)<<PAGE_SHIFT;

    /* bios の e820 から memory map サイズ? を読む */
	bootmap = find_e820_area(0, end_pfn<<PAGE_SHIFT, bootmap_size,
				 PAGE_SIZE);
	if (bootmap == -1L)
		panic("Cannot find bootmem map of size %ld\n", bootmap_size);
	/* don't touch min_low_pfn */
	bootmap_size = init_bootmem_node(NODE_DATA(0), bootmap >> PAGE_SHIFT,
					 0, end_pfn);
	e820_register_active_regions(0, start_pfn, end_pfn);
	free_bootmem_with_active_regions(0, end_pfn);
	early_res_to_bootmem(0, end_pfn<<PAGE_SHIFT);
	reserve_bootmem(bootmap, bootmap_size, BOOTMEM_DEFAULT);
}
#endif
```

BIOS の e820 とかいうファシリティ? によって bootmap を知ることができるらしい

 * http://en.wikipedia.org/wiki/E820

```c
/*
 * Find a free area with specified alignment in a specific range.
 */
u64 __init find_e820_area(u64 start, u64 end, u64 size, u64 align)
{
	int i;

	for (i = 0; i < e820.nr_map; i++) {
		struct e820entry *ei = &e820.map[i];
		u64 addr, last;
		u64 ei_last;

		if (ei->type != E820_RAM)
			continue;
		addr = round_up(ei->addr, align);
		ei_last = ei->addr + ei->size;
		if (addr < start)
			addr = round_up(start, align);
		if (addr >= ei_last)
			continue;
		while (bad_addr(&addr, size, align) && addr+size <= ei_last)
			;
		last = addr + size;
		if (last > ei_last)
			continue;
		if (last > end)
			continue;
		return addr;
	}
	return -1ULL;
}
```

dmesg に e820 の出力が出ている

```
# 512MB の場合
[vagrant@*** ~]$ dmesg | grep -i e820
 BIOS-e820: 0000000000000000 - 000000000009fc00 (usable)
 BIOS-e820: 000000000009fc00 - 00000000000a0000 (reserved)
 BIOS-e820: 00000000000f0000 - 0000000000100000 (reserved)
 BIOS-e820: 0000000000100000 - 000000001fff0000 (usable)    # 510MB
 BIOS-e820: 000000001fff0000 - 0000000020000000 (ACPI data)
 BIOS-e820: 00000000fffc0000 - 0000000100000000 (reserved)
e820 update range: 0000000000000000 - 0000000000001000 (usable) ==> (reserved)
e820 remove range: 00000000000a0000 - 0000000000100000 (usable)
```

Vagrant + CentOS6.5 + 16GB載せた場合。 usable が増えている

```
[vagrant@*** ~]$ dmesg | grep e820
 BIOS-e820: 0000000000000000 - 000000000009fc00 (usable)    # DOS用(リアルモード?)
 BIOS-e820: 000000000009fc00 - 00000000000a0000 (reserved)  # 1MB?
 BIOS-e820: 00000000000f0000 - 0000000000100000 (reserved)  
 BIOS-e820: 0000000000100000 - 00000000dfff0000 (usable)    # 3582MB
 BIOS-e820: 00000000dfff0000 - 00000000e0000000 (ACPI data) # ハードウェアデバイスの情報?
 BIOS-e820: 00000000fffc0000 - 0000000100000000 (reserved) 
 BIOS-e820: 0000000100000000 - 0000000408000000 (usable)    # 12416MB
e820 update range: 0000000000000000 - 0000000000001000 (usable) ==> (reserved)
e820 remove range: 00000000000a0000 - 0000000000100000 (usable)
```

 * ページフレーム0
   * BIOS が POST で使用する

# max_pfn, max_low_pfn

 * max_pfn = 利用出来るページフレームで終端のページフレーム番号
 * max_low_pfn = ストレートマッピング(低位)しているの終端のページフレーム番号
   * ZONE_NORMAL の終端?

max_pfn の値を BIOS の e820 から取れる

```c
unsigned long __init e820_end_of_ram_pfn(void)
{
	return e820_end_pfn(MAX_ARCH_PFN, E820_RAM);
}
```

max_pfn, max_low_pfn の初期化コード

```
/*
 * Determine if we were loaded by an EFI loader.  If so, then we have also been
 * passed the efi memmap, systab, etc., so we should use these data structures
 * for initialization.  Note, the efi init code path is determined by the
 * global efi_enabled. This allows the same kernel image to be used on existing
 * systems (with a traditional BIOS) as well as on EFI systems.
 */
/*
 * setup_arch - architecture-specific boot-time initializations
 *
 * Note: On x86_64, fixmaps are ready for use even before this is called.
 */

void __init setup_arch(char **cmdline_p)
{

//...

	/*
	 * partially used pages are not usable - thus
	 * we are rounding upwards:
	 */
    // ページフレーム番号の最大値
	max_pfn = e820_end_of_ram_pfn();

	/* preallocate 4k for mptable mpc */
	early_reserve_e820_mpc_new();
	/* update e820 for memory not covered by WB MTRRs */
    // MTRR = http://www.itmedia.co.jp/help/tips/linux/l0173.html
    // X Windows 用の何かの機能
	mtrr_bp_init();
	if (mtrr_trim_uncached_memory(max_pfn))
		max_pfn = e820_end_of_ram_pfn();

    /* ページフレーム番号の最大値 = ページフレーム数 */
	num_physpages = max_pfn;

	check_x2apic();

	/* How many end-of-memory variables you have, grandma! */
	/* need this before calling reserve_initrd */
    // 4GBでは e820 から max_low_pfn を読み取る?
	if (max_pfn > (1UL<<(32 - PAGE_SHIFT)))
		max_low_pfn = e820_end_of_low_ram_pfn();
	else
		max_low_pfn = max_pfn;

    // __va 物理アドレス => 仮想アドレス ( phys_to_virtの逆 )
	high_memory = (void *)__va(max_pfn * PAGE_SIZE - 1) + 1;
	max_pfn_mapped = KERNEL_IMAGE_SIZE >> PAGE_SHIFT;

//...    

    // ここでメモリノードの初期化に入る
	initmem_init(0, max_pfn);    
```