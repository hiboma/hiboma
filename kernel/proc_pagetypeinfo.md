# /proc/pagetypeinfo

https://lkml.org/lkml/2010/2/12/93

```
$ cat /proc/pagetypeinfo
Page block order: 9
Pages per block:  512

Free pages count per migrate type at order       0      1      2      3      4      5      6      7      8      9     10 
Node    0, zone      DMA, type    Unmovable      0      0      1      1      1      0      1      0      2      1      0 
Node    0, zone      DMA, type  Reclaimable      0      0      0      0      0      0      0      0      0      0      0 
Node    0, zone      DMA, type      Movable      0      0      0      0      0      0      0      0      0      1      2 
Node    0, zone      DMA, type      Reserve      0      0      0      0      0      0      0      0      0      0      0 
Node    0, zone      DMA, type          CMA      0      0      0      0      0      0      0      0      0      0      0 
Node    0, zone      DMA, type      Isolate      0      0      0      0      0      0      0      0      0      0      0 
Node    0, zone    DMA32, type    Unmovable   3295   5339     37      0      0      0      0      0      0      0      0 
Node    0, zone    DMA32, type  Reclaimable  21693   3918    108      0      0      0      0      0      0      0      0 
Node    0, zone    DMA32, type      Movable    332     44      0      0      0      0      0      0      0      0      0 
Node    0, zone    DMA32, type      Reserve      0      0      0      0      0      0      0      0      0      0      0 
Node    0, zone    DMA32, type          CMA      0      0      0      0      0      0      0      0      0      0      0 
Node    0, zone    DMA32, type      Isolate      0      0      0      0      0      0      0      0      0      0      0 
Node    0, zone   Normal, type    Unmovable   7308  22441   4281     84      1      0      0      0      0      0      0 
Node    0, zone   Normal, type  Reclaimable  75541  50530   7304    309      5      0      0      0      0      0      0 
Node    0, zone   Normal, type      Movable  16038   8486   1758    275     13      1      0      0      0      0      0 
Node    0, zone   Normal, type      Reserve      0      0      0      0      0      0      0      0      0      0      0 
Node    0, zone   Normal, type          CMA      0      0      0      0      0      0      0      0      0      0      0 
Node    0, zone   Normal, type      Isolate      0      0      0      0      0      0      0      0      0      0      0 

Number of blocks type     Unmovable  Reclaimable      Movable      Reserve          CMA      Isolate 
Node 0, zone      DMA            3            0            5            0            0            0 
Node 0, zone    DMA32          111          463          442            0            0            0 
Node 0, zone   Normal          549         1805         4814            0            0            0 
Page block order: 9
Pages per block:  512

Free pages count per migrate type at order       0      1      2      3      4      5      6      7      8      9     10 
Node    1, zone   Normal, type    Unmovable    431    886    326     83     24      1      0      0      0      0      0 
Node    1, zone   Normal, type  Reclaimable  33365  27814   4087    439     23      1      0      0      0      0      0 
Node    1, zone   Normal, type      Movable  29003   1899    233     36      4      0      0      0      0      0      0 
Node    1, zone   Normal, type      Reserve      0      0      0      0      0      0      0      0      0      0      0 
Node    1, zone   Normal, type          CMA      0      0      0      0      0      0      0      0      0      0      0 
Node    1, zone   Normal, type      Isolate      0      0      0      0      0      0      0      0      0      0      0 

Number of blocks type     Unmovable  Reclaimable      Movable      Reserve          CMA      Isolate 
Node 1, zone   Normal          548         1558         6086            0            0            0 
```

## migration types

```
enum {
	MIGRATE_UNMOVABLE,
	MIGRATE_RECLAIMABLE,
	MIGRATE_MOVABLE,
	MIGRATE_PCPTYPES,	/* the number of types on the pcp lists */
	MIGRATE_RESERVE = MIGRATE_PCPTYPES,
#ifdef CONFIG_CMA
	/*
	 * MIGRATE_CMA migration type is designed to mimic the way
	 * ZONE_MOVABLE works.  Only movable pages can be allocated
	 * from MIGRATE_CMA pageblocks and page allocator never
	 * implicitly change migration type of MIGRATE_CMA pageblock.
	 *
	 * The way to use it is to change migratetype of a range of
	 * pageblocks to MIGRATE_CMA which can be done by
	 * __free_pageblock_cma() function.  What is important though
	 * is that a range of pageblocks must be aligned to
	 * MAX_ORDER_NR_PAGES should biggest page be bigger then
	 * a single pageblock.
	 */
	MIGRATE_CMA,
#endif
#ifdef CONFIG_MEMORY_ISOLATION
	MIGRATE_ISOLATE,	/* can't allocate from here */
#endif
	MIGRATE_TYPES
};
```

```
static char * const migratetype_names[MIGRATE_TYPES] = {
	"Unmovable",
	"Reclaimable",
	"Movable",
	"Reserve",
#ifdef CONFIG_CMA
	"CMA",
#endif
#ifdef CONFIG_MEMORY_ISOLATION
	"Isolate",
#endif
};

static void pagetypeinfo_showfree_print(struct seq_file *m,
					pg_data_t *pgdat, struct zone *zone)
{
	int order, mtype;

	for (mtype = 0; mtype < MIGRATE_TYPES; mtype++) {
		seq_printf(m, "Node %4d, zone %8s, type %12s ",
					pgdat->node_id,
					zone->name,
					migratetype_names[mtype]);
		for (order = 0; order < MAX_ORDER; ++order) {
			unsigned long freecount = 0;
			struct free_area *area;
			struct list_head *curr;

			area = &(zone->free_area[order]);

			list_for_each(curr, &area->free_list[mtype])
				freecount++;
			seq_printf(m, "%6lu ", freecount);
		}
		seq_putc(m, '\n');
	}
}
```