## SReclaimable, SUnreclaim

 * Slab Reclaimable
 * Slab Unreclaim

```c
		"SReclaimable:   %8lu kB\n"
		"SUnreclaim:     %8lu kB\n"

// ...

		K(global_page_state(NR_SLAB_RECLAIMABLE) +
				global_page_state(NR_SLAB_UNRECLAIMABLE)),
```

NR_SLAB_RECLAIMABLE は __vm_enough_memory で free ページとして加算されている

 * inode cache, dentry cache はこれらに加算される
```c
		/*
		 * Any slabs which are created with the
		 * SLAB_RECLAIM_ACCOUNT flag claim to have contents
		 * which are reclaimable, under pressure.  The dentry
		 * cache and most inode caches should fall into this
		 */
		free += global_page_state(NR_SLAB_RECLAIMABLE);
```

slab (kmem_cache等) で reclaim できるもの/できないもののサイズを指している

## kmem_cache

SReclaimable/SUnreclaim かどうかは kmem_cache flags の SLAB_RECLAIM_ACCOUNT の有無で分類される

```c
struct kmem_cache {
/* 1) per-cpu data, touched during every alloc/free */
	struct array_cache *array[NR_CPUS];
/* 2) Cache tunables. Protected by cache_chain_mutex */
	unsigned int batchcount;
	unsigned int limit;
	unsigned int shared;

	unsigned int buffer_size;
	u32 reciprocal_buffer_size;
/* 3) touched by every alloc & free from the backend */

	unsigned int flags;		/* constant flags */
	unsigned int num;		/* # of objs per slab */

/* 4) cache_grow/shrink */
	/* order of pgs per slab (2^n) */
	unsigned int gfporder;

	/* force GFP flags, e.g. GFP_DMA */
	gfp_t gfpflags;

	size_t colour;			/* cache colouring range */
	unsigned int colour_off;	/* colour offset */
	struct kmem_cache *slabp_cache;
	unsigned int slab_size;
	unsigned int dflags;		/* dynamic flags */

	/* constructor func */
	void (*ctor)(void *obj);

/* 5) cache creation/removal */
	const char *name;
	struct list_head next;

/* 6) statistics */
#ifdef CONFIG_DEBUG_SLAB
	unsigned long num_active;
	unsigned long num_allocations;
	unsigned long high_mark;
	unsigned long grown;
	unsigned long reaped;
	unsigned long errors;
	unsigned long max_freeable;
	unsigned long node_allocs;
	unsigned long node_frees;
	unsigned long node_overflow;
	atomic_t allochit;
	atomic_t allocmiss;
	atomic_t freehit;
	atomic_t freemiss;

	/*
	 * If debugging is enabled, then the allocator can add additional
	 * fields and/or padding to every object. buffer_size contains the total
	 * object size including these internal fields, the following two
	 * variables contain the offset to the user object and its size.
	 */
	int obj_offset;
	int obj_size;
#endif /* CONFIG_DEBUG_SLAB */

	/*
	 * We put nodelists[] at the end of kmem_cache, because we want to size
	 * this array to nr_node_ids slots instead of MAX_NUMNODES
	 * (see kmem_cache_init())
	 * We still use [MAX_NUMNODES] and not [1] or [0] because cache_cache
	 * is statically defined, so we reserve the max number of nodes.
	 */
	struct kmem_list3 *nodelists[MAX_NUMNODES];
	/*
	 * Do not add fields after nodelists[]
	 */
};
```

## TODO

```
drivers/base/node.c:		       nid, K(node_page_state(nid, NR_SLAB_RECLAIMABLE) +
drivers/base/node.c:		       nid, K(node_page_state(nid, NR_SLAB_RECLAIMABLE)),
fs/proc/meminfo.c:		K(global_page_state(NR_SLAB_RECLAIMABLE) +
fs/proc/meminfo.c:		K(global_page_state(NR_SLAB_RECLAIMABLE)),
include/linux/mmzone.h:	NR_SLAB_RECLAIMABLE,
kernel/power/snapshot.c:	size = global_page_state(NR_SLAB_RECLAIMABLE)
mm/mmap.c:		free += global_page_state(NR_SLAB_RECLAIMABLE);
mm/nommu.c:		free += global_page_state(NR_SLAB_RECLAIMABLE);
mm/page_alloc.c:		global_page_state(NR_SLAB_RECLAIMABLE),
mm/page_alloc.c:			K(zone_page_state(zone, NR_SLAB_RECLAIMABLE)),
mm/slab.c:			NR_SLAB_RECLAIMABLE, nr_pages);
mm/slab.c:				NR_SLAB_RECLAIMABLE, nr_freed);
mm/slub.c:		NR_SLAB_RECLAIMABLE : NR_SLAB_UNRECLAIMABLE,
mm/slub.c:		NR_SLAB_RECLAIMABLE : NR_SLAB_UNRECLAIMABLE,
mm/vmscan.c:	nr_slab = global_page_state(NR_SLAB_RECLAIMABLE);
mm/vmscan.c:	slab_reclaimable = zone_page_state(zone, NR_SLAB_RECLAIMABLE);
mm/vmscan.c:			zone_page_state(zone, NR_SLAB_RECLAIMABLE) >
mm/vmscan.c:			zone_page_state(zone, NR_SLAB_RECLAIMABLE);
mm/vmscan.c:	    zone_page_state(zone, NR_SLAB_RECLAIMABLE) <= zone->min_slab_pages)
```

## NR_SLAB_RECLAIMABLE, NR_SLAB_UNRECLAIMABLE の減算される場所

kmem_cache_shrink -> discard_slab -> free_slab -> **__free_slab**

```c
static void __free_slab(struct kmem_cache *s, struct page *page)
{
	int order = compound_order(page);
	int pages = 1 << order;

	if (unlikely(SLABDEBUG && PageSlubDebug(page))) {
		void *p;

		slab_pad_check(s, page);
		for_each_object(p, s, page_address(page),
						page->objects)
			check_object(s, page, p, 0);
		__ClearPageSlubDebug(page);
	}

	kmemcheck_free_shadow(page, compound_order(page));

    // ここで加算されるぞう
	mod_zone_page_state(page_zone(page),
		(s->flags & SLAB_RECLAIM_ACCOUNT) ?
		NR_SLAB_RECLAIMABLE : NR_SLAB_UNRECLAIMABLE,
		-pages);

	__ClearPageSlab(page);
	reset_page_mapcount(page);
	if (current->reclaim_state)
		current->reclaim_state->reclaimed_slab += pages;
	__free_pages(page, order);
}
```

## NR_SLAB_RECLAIMABLE, NR_SLAB_UNRECLAIMABLE の加算される場所

kmem_cache_alloc -> slab_alloc __slab_alloc -> new_slab -> **allocate_slab**

```c
static struct page *allocate_slab(struct kmem_cache *s, gfp_t flags, int node)
{
	struct page *page;
	struct kmem_cache_order_objects oo = s->oo;
	gfp_t alloc_gfp;

	flags |= s->allocflags;

	/*
	 * Let the initial higher-order allocation fail under memory pressure
	 * so we fall-back to the minimum order allocation.
	 */
	alloc_gfp = (flags | __GFP_NOWARN | __GFP_NORETRY) & ~__GFP_NOFAIL;

	page = alloc_slab_page(alloc_gfp, node, oo);
	if (unlikely(!page)) {
		oo = s->min;
		/*
		 * Allocation may have failed due to fragmentation.
		 * Try a lower order alloc if possible
		 */
		page = alloc_slab_page(flags, node, oo);
		if (!page)
			return NULL;

		stat(get_cpu_slab(s, raw_smp_processor_id()), ORDER_FALLBACK);
	}

	if (kmemcheck_enabled
		&& !(s->flags & (SLAB_NOTRACK | DEBUG_DEFAULT_FLAGS))) {
		int pages = 1 << oo_order(oo);

		kmemcheck_alloc_shadow(page, oo_order(oo), flags, node);

		/*
		 * Objects from caches that have a constructor don't get
		 * cleared when they're allocated, so we need to do it here.
		 */
		if (s->ctor)
			kmemcheck_mark_uninitialized_pages(page, pages);
		else
			kmemcheck_mark_unallocated_pages(page, pages);
	}

	page->objects = oo_objects(oo);
	mod_zone_page_state(page_zone(page),
		(s->flags & SLAB_RECLAIM_ACCOUNT) ?
		NR_SLAB_RECLAIMABLE : NR_SLAB_UNRECLAIMABLE,
		1 << oo_order(oo));

	return page;
}
```

## inode cache と SLAB_RECLAIM_ACCOUNT

### ext4_inode_cachep

```c
static int init_inodecache(void)
{
	ext4_inode_cachep = kmem_cache_create("ext4_inode_cache",
					     sizeof(struct ext4_inode_info),
					     0, (SLAB_RECLAIM_ACCOUNT|
						SLAB_MEM_SPREAD),
					     init_once);
	if (ext4_inode_cachep == NULL)
		return -ENOMEM;
	return 0;
}
```

### inode_cache

```
void __init inode_init(void)
{
	int loop;

	/* inode slab cache */
	inode_cachep = kmem_cache_create("inode_cache",
					 sizeof(struct inode),
					 0,
					 (SLAB_RECLAIM_ACCOUNT|SLAB_PANIC|
					 SLAB_MEM_SPREAD),
					 init_once);
	register_shrinker(&icache_shrinker);
```

icache_shrinker を kmem_cache_shrink のコールバックとする