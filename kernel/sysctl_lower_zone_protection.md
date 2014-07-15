# sysctl_lower_zone_protection

CentOS6.5 だと zone->lowmem_reserve

## とある OOM Killer

```
Apr 1 11:26:02 foobar kernel: Free pages:       17752kB (1600kB HighMem)
Apr 1 11:26:02 foobar kernel: Active:3607775 inactive:424687 dirty:184 writeback:0 unstable:0 free:4438 slab:49089 mapped:3423565 pagetables:47034
Apr 1 11:26:02 foobar kernel: DMA free:12456kB min:64kB low:128kB high:192kB active:0kB inactive:0kB present:16384kB pages_scanned:0 all_unreclaimable? yes
Apr 1 11:26:02 foobar kernel: protections[]: 0 0 0
Apr 1 11:26:02 foobar kernel: Normal free:3696kB min:3728kB low:7456kB high:11184kB active:305804kB inactive:120012kB present:901120kB pages_scanned:1130529 all_unreclaimable? yes
Apr 1 11:26:02 foobar kernel: protections[]: 0 0 0
Apr 1 11:26:03 foobar kernel: HighMem free:1600kB min:512kB low:1024kB high:1536kB active:14125208kB inactive:1578952kB present:16908288kB pages_scanned:0 all_unreclaimable? no
Apr 1 11:26:03 foobar kernel: protections[]: 0 0 0
Apr 1 11:26:03 foobar kernel: DMA: 2*4kB 2*8kB 3*16kB 3*32kB 4*64kB 2*128kB 2*256kB 0*512kB 1*1024kB 1*2048kB 2*4096kB = 12456kB
Apr 1 11:26:03 foobar kernel: Normal: 6*4kB 17*8kB 15*16kB 1*32kB 1*64kB 1*128kB 0*256kB 0*512kB 1*1024kB 1*2048kB 0*4096kB = 3696kB
Apr 1 11:26:03 foobar kernel: HighMem: 272*4kB 0*8kB 0*16kB 0*32kB 2*64kB 1*128kB 1*256kB 0*512kB 0*1024kB 0*2048kB 0*4096kB = 1600kB
Apr 1 11:26:03 foobar kernel: 736320 pagecache pages
Apr 1 11:26:03 foobar kernel: Swap cache: add 3704763, delete 3347881, find 663746/1132339, race 40+367
Apr 1 11:26:03 foobar kernel: 0 bounce buffer pages
Apr 1 11:26:03 foobar kernel: Free swap:            0kB
Apr 1 11:26:03 foobar kernel: 4456448 pages of RAM
Apr 1 11:26:03 foobar kernel: 3962544 pages of HIGHMEM
Apr 1 11:26:03 foobar kernel: 300937 reserved pages
Apr 1 11:26:03 foobar kernel: 7882373 pages shared
Apr 1 11:26:03 foobar kernel: 357033 pages swap cached
Apr 1 11:26:03 foobar kernel: Out of Memory: Killed process 15527 (httpd).
```

このエントリでは OOM Killer 内の `protections[]` の意味を調べる。対象はまさかの CentSO4 + 32bit。 2.6.9-103.ELsmp

## higherzone_val

**sysctl_lower_zone_protection** が使われているのは下記のコード

```c
static unsigned long higherzone_val(struct zone *z, int max_zone,
					int alloc_type)
{
	int z_idx = zone_idx(z);
	struct zone *higherzone;
	unsigned long pages;

	/* there is no higher zone to get a contribution from */
	if (z_idx == MAX_NR_ZONES-1)
		return 0;

	higherzone = &z->zone_pgdat->node_zones[z_idx+1];

	/* We always start with the higher zone's protection value */
	pages = higherzone->protection[alloc_type];

	/*
	 * We get a lower-zone-protection contribution only if there are
	 * pages in the higher zone and if we're not the highest zone
	 * in the current zonelist.  e.g., never happens for GFP_DMA. Happens
	 * only for ZONE_DMA in a GFP_KERNEL allocation and happens for ZONE_DMA
	 * and ZONE_NORMAL for a GFP_HIGHMEM allocation.
	 */
	if (higherzone->present_pages && z_idx < alloc_type)
		pages += higherzone->pages_low * sysctl_lower_zone_protection;

	return pages;
}
```

肝となる計算式は下記の通り

```c
pages += higherzone->pages_low * sysctl_lower_zone_protection;
```

 * 上位のゾーンの **Low** のページ数 * sysctl_lower_zone_protection
   * NORMAL なら HIGHMEM の low を元に計算
   * DMA なら NORMAL の low を元に計算

することになる   

```
# ZONE_HIGHMEM の pages_low * 100 の例
1024KB * 100 = 10MB
```

計算したページ数 は zone ごとの protection の値になる

 * setup_per_zone_protection
   * sysctl_lower_zone_protection をセットすると protection の値も再度セットされる
   * min_free_kbytes の婆にも呼び出される

```c
/*
 * setup_per_zone_protection - called whenver min_free_kbytes or
 *	sysctl_lower_zone_protection changes.  Ensures that each zone
 *	has a correct pages_protected value, so an adequate number of
 *	pages are left in the zone after a successful __alloc_pages().
 *
 *	This algorithm is way confusing.  I tries to keep the same behavior
 *	as we had with the incremental min iterative algorithm.
 */
static void setup_per_zone_protection(void)
{
	struct pglist_data *pgdat;
	struct zone *zones, *zone;
	int max_zone;
	int i, j;

	for_each_pgdat(pgdat) {
		zones = pgdat->node_zones;

		for (i = 0, max_zone = 0; i < MAX_NR_ZONES; i++)
			if (zones[i].present_pages)
				max_zone = i;

		/*
		 * For each of the different allocation types:
		 * GFP_DMA -> GFP_KERNEL -> GFP_HIGHMEM
		 */
		for (i = 0; i < GFP_ZONETYPES; i++) {
			/*
			 * For each of the zones:
			 * ZONE_HIGHMEM -> ZONE_NORMAL -> ZONE_DMA
			 */
			for (j = MAX_NR_ZONES-1; j >= 0; j--) {
				zone = &zones[j];

				/*
				 * We never protect zones that don't have memory
				 * in them (j>max_zone) or zones that aren't in
				 * the zonelists for a certain type of
				 * allocation (j>=i).  We have to assign these
				 * to zero because the lower zones take
				 * contributions from the higher zones.
				 */
				if (j > max_zone || j >= i) {
					zone->protection[i] = 0;
					continue;
				}
				/*
				 * The contribution of the next higher zone
				 */
				zone->protection[i] = higherzone_val(zone,
								max_zone, i);
			}
		}
	}
}
```

struct zone .protection の定義は下記の通り

```
struct zone {

//…

	/*
	 * protection[] is a pre-calculated number of extra pages that must be
	 * available in a zone in order for __alloc_pages() to allocate memory
	 * from the zone. i.e., for a GFP_KERNEL alloc of "order" there must
	 * be "(1<<order) + protection[ZONE_NORMAL]" free pages in the zone
	 * for us to choose to allocate the page from that zone.
	 *
	 * It uses both min_free_kbytes and sysctl_lower_zone_protection.
	 * The protection values are recalculated if either of these values
	 * change.  The array elements are in zonelist order:
	 *	[0] == GFP_DMA, [1] == GFP_KERNEL, [2] == GFP_HIGHMEM.
	 */
	unsigned long		protection[MAX_NR_ZONES];
```

## zone .protection がどのように使われるか

```c
struct page * fastcall
__alloc_pages(unsigned int gfp_mask, unsigned int order,
		struct zonelist *zonelist)

//…

	/*
	 * Go through the zonelist again. Let __GFP_HIGH and allocations
	 * coming from realtime tasks to go deeper into reserves
	 */
	for (i = 0; (z = zones[i]) != NULL; i++) {
		min = z->pages_min;
		if (gfp_mask & __GFP_HIGH)
			min /= 2;
		if (can_try_harder)
			min -= min / 4;
		min += (1<<order) + z->protection[alloc_type];

		if (z->free_pages < min)
			continue;
```

zone の min に protection の値を加算することで、zone の空きページが min 以下にならんようにするてな感じ?

`echo m /proc/sysrq-trigeger` で printk しているコードは下記の通り

```
       /* mm/page_alloc.c */
       /* ZONE_DMA -> ZONE_NORMAL -> ZONE_HIGHMEM でイテレート */
		printk("protections[]:");
		for (i = 0; i < MAX_NR_ZONES; i++)
			printk(" %lu", zone->protection[i]);
```

