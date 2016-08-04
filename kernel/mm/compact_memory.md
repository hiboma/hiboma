# /proc/sys/vm/compact_memory

 * allocator - direct compaction
 * kswapd - async compaction
 * /proc/sys/vm/compact_memory, /sys/devices/system/node/nodeN/compact 

## Documentation

https://kernelnewbies.org/Linux_2_6_35#head-9cb0a1275559d40296da42efb7977896ac9edab7

```
1.7. Memory compaction
Recommended LWN article: "Memory compaction"

The memory compaction mechanism tries reduces external memory fragmentation in a memory zone by trying to move used pages to create a new big block of contiguous used pages. When compaction finishes, the memory zone will have a big block of used pages and a big block of free pages. This will make easier to allocate bigger chunks of memory. The mechanism is called "compaction" to distinguish it from other forms of defragmentation.

In this implementation, a full compaction run involves two scanners operating within a zone, a migration scanner and a free scanner. The migration scanner starts at the beginning of a zone and finds all used pages that can be moved. The free scanner begins at the end of the zone and searches for enough free pages to migrate all the used pages found by the previous scanner. A compaction run completes within a zone when the two scanners meet and used pages are migrated to the free blocks scanned. Testing has showed the amount of IO required to satisfy a huge page allocation is reduced significantly.

Memory compaction can be triggered in one of three ways. It may be triggered explicitly by writing any value to /proc/sys/vm/compact_memory and compacting all of memory. It can be triggered on a per-node basis by writing any value to /sys/devices/system/node/nodeN/compact where N is the node ID to be compacted. When a process fails to allocate a high-order page, it may compact memory in an attempt to satisfy the allocation instead of entering direct reclaim. Explicit compaction does not finish until the two scanners meet and direct compaction ends if a suitable page becomes available that would meet watermarks.

Code: (commit 1, 2, 3, 4 ,5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
```

```
compact_memory

Available only when CONFIG_COMPACTION is set. When 1 is written to the file,
all zones are compacted such that free memory is available in contiguous
blocks where possible. This can be important for example in the allocation of
huge pages although processes will also directly compact memory as required.
```

## where is the sysctl-handler fucntion defined ?

```
{
		.procname	= "compact_memory",
		.data		= &sysctl_compact_memory,
		.maxlen		= sizeof(int),
		.mode		= 0200,
		.proc_handler	= sysctl_compaction_handler,
	},
```

## sysctl_compaction_handler

```c
/* The written value is actually unused, all memory is compacted */
int sysctl_compact_memory;

/* This is the entry point for compacting all nodes via /proc/sys/vm */
int sysctl_compaction_handler(struct ctl_table *table, int write,
			void __user *buffer, size_t *length, loff_t *ppos)
{
	if (write)
		compact_nodes();

	return 0;
}
```

# In Memory Node

## compact_nodes

 * comaction runs on each memory nodes.

```c
/* Compact all nodes in the system */
static void compact_nodes(void)
{
	int nid;

	/* Flush pending updates to the LRU lists */
	lru_add_drain_all();

	for_each_online_node(nid)
		compact_node(nid);
}
```

```c
static void compact_node(int nid) // nid = node id
{
	struct compact_control cc = {
		.order = -1,
		.sync = true,
	};

	__compact_pgdat(NODE_DATA(nid), &cc);
}
```

## In Memory Zones

```c
/* Compact all zones within a node */
static void __compact_pgdat(pg_data_t *pgdat, struct compact_control *cc)
{
	int zoneid;
	struct zone *zone;

    /* ゾーンごとにいてレート */
	for (zoneid = 0; zoneid < MAX_NR_ZONES; zoneid++) {

		zone = &pgdat->node_zones[zoneid];
		if (!populated_zone(zone))
			continue;

        // struct compact_control {
        // 	    struct list_head freepages;	/* List of free pages to migrate to */
        // 	    struct list_head migratepages;	/* List of pages being migrated */
        // 	    unsigned long nr_freepages;	/* Number of isolated free pages */
        // 	    unsigned long nr_migratepages;	/* Number of pages to migrate */
        // 	    unsigned long free_pfn;		/* isolate_freepages search base */
        // 	    unsigned long migrate_pfn;	/* isolate_migratepages search base */
        // 	    bool sync;			/* Synchronous migration */
        // 	    bool ignore_skip_hint;		/* Scan blocks even if marked skip */
        // 	    bool finished_update_free;	/* True when the zone cached pfns are
        // 	    				 * no longer being updated
        // 	    				 */
        // 	    bool finished_update_migrate;
        //      
        // 	    int order;			/* order a direct compactor needs */
        // 	    int migratetype;		/* MOVABLE, RECLAIMABLE etc */
        // 	    struct zone *zone;
        // 	    bool contended;			/* True if a lock was contended */
        // };
        
		cc->nr_freepages = 0;
		cc->nr_migratepages = 0;
		cc->zone = zone;
		INIT_LIST_HEAD(&cc->freepages);
		INIT_LIST_HEAD(&cc->migratepages);

        // `cc->oderver == -1` ... via /proc/sys/vm/compact_memory

        ///* Returns true if compaction should be skipped this time */
        //static inline bool compaction_deferred(struct zone *zone, int order)
        //{
        //	unsigned long defer_limit = 1UL << zone->compact_defer_shift;
        //
        //	if (order < zone->compact_order_failed)
        //		return false;
        //
        //	/* Avoid possible overflow */
        //	if (++zone->compact_considered > defer_limit)
        //		zone->compact_considered = defer_limit;
        //
        //	return zone->compact_considered < defer_limit;
        //}

		if (cc->order == -1 || !compaction_deferred(zone, cc->order))
			compact_zone(zone, cc);

        // via __alloc_pages ?
		if (cc->order > 0) {
			int ok = zone_watermark_ok(zone, cc->order,
						low_wmark_pages(zone), 0, 0);
			if (ok && cc->order >= zone->compact_order_failed)
				zone->compact_order_failed = cc->order + 1;
			/* Currently async compaction is never deferred. */
			else if (!ok && cc->sync)
				defer_compaction(zone, cc->order);
		}

		VM_BUG_ON(!list_empty(&cc->freepages));
		VM_BUG_ON(!list_empty(&cc->migratepages));
	}
}
```

## compact_zone

```c
static int compact_zone(struct zone *zone, struct compact_control *cc)
{
	int ret;

    // pfn = page frame number
	unsigned long start_pfn = zone->zone_start_pfn;
	unsigned long end_pfn = zone_end_pfn(zone);

    // return COMPACT_CONTINUE when via /proc/sys/vm/compact_memory
	ret = compaction_suitable(zone, cc->order);
	switch (ret) {
	case COMPACT_PARTIAL:
	case COMPACT_SKIPPED:
		/* Compaction is likely to fail */
		return ret;
	case COMPACT_CONTINUE:
		/* Fall through to compaction */
		;
	}

	// /* pfns where compaction scanners should start */
    // 	unsigned long		compact_cached_free_pfn;
	//  unsigned long		compact_cached_migrate_pfn;

	/*
	 * Setup to move all movable pages to the end of the zone. Used cached
	 * information on where the scanners should start but check that it
	 * is initialised by ensuring the values are within zone boundaries.
	 */
	cc->migrate_pfn = zone->compact_cached_migrate_pfn;
	cc->free_pfn = zone->compact_cached_free_pfn;
	if (cc->free_pfn < start_pfn || cc->free_pfn > end_pfn) {
		cc->free_pfn = end_pfn & ~(pageblock_nr_pages-1);
		zone->compact_cached_free_pfn = cc->free_pfn;
	}
	if (cc->migrate_pfn < start_pfn || cc->migrate_pfn > end_pfn) {
		cc->migrate_pfn = start_pfn;
		zone->compact_cached_migrate_pfn = cc->migrate_pfn;
	}

	/*
	 * Clear pageblock skip if there were failures recently and compaction
	 * is about to be retried after being deferred. kswapd does not do
	 * this reset as it'll reset the cached information when going to sleep.
	 */
	if (compaction_restarting(zone, cc->order) && !current_is_kswapd())
		__reset_isolation_suitable(zone);

	migrate_prep_local();

    // loop し続けるか否か
	while ((ret = compact_finished(zone, cc)) == COMPACT_CONTINUE) {
		unsigned long nr_migrate, nr_remaining;
		int err;

		switch (isolate_migratepages(zone, cc)) {
		case ISOLATE_ABORT:
			ret = COMPACT_PARTIAL;
			putback_movable_pages(&cc->migratepages);
			cc->nr_migratepages = 0;
			goto out;
		case ISOLATE_NONE:
			continue;
		case ISOLATE_SUCCESS:
			;
		}

		nr_migrate = cc->nr_migratepages;
		err = migrate_pages(&cc->migratepages, compaction_alloc,
				(unsigned long)cc,
				cc->sync ? MIGRATE_SYNC_LIGHT : MIGRATE_ASYNC,
				MR_COMPACTION);
		update_nr_listpages(cc);
		nr_remaining = cc->nr_migratepages;

		trace_mm_compaction_migratepages(nr_migrate - nr_remaining,
						nr_remaining);

		/* Release isolated pages not migrated */
		if (err) {
			putback_movable_pages(&cc->migratepages);
			cc->nr_migratepages = 0;
			if (err == -ENOMEM) {
				ret = COMPACT_PARTIAL;
				goto out;
			}
		}
	}

out:
	/* Release free pages and check accounting */
	cc->nr_freepages -= release_freepages(&cc->freepages);
	VM_BUG_ON(cc->nr_freepages != 0);

	return ret;
}
```

# Migrate Pages

```c
/*
 * migrate_pages - migrate the pages specified in a list, to the free pages
 *		   supplied as the target for the page migration
 *
 * @from:		The list of pages to be migrated.
 * @get_new_page:	The function used to allocate free pages to be used
 *			as the target of the page migration.
 * @private:		Private data to be passed on to get_new_page()
 * @mode:		The migration mode that specifies the constraints for
 *			page migration, if any.
 * @reason:		The reason for page migration.
 *
 * The function returns after 10 attempts or if no pages are movable any more
 * because the list has become empty or no retryable pages exist any more.
 * The caller should call putback_lru_pages() to return pages to the LRU
 * or free list only if ret != 0.
 *
 * Returns the number of pages that were not migrated, or an error code.
 */
int migrate_pages(struct list_head *from, new_page_t get_new_page,
		unsigned long private, enum migrate_mode mode, int reason)
{
	int retry = 1;
	int nr_failed = 0;
	int nr_succeeded = 0;
	int pass = 0;
	struct page *page;
	struct page *page2;
	int swapwrite = current->flags & PF_SWAPWRITE;
	int rc;

	if (!swapwrite)
		current->flags |= PF_SWAPWRITE;

	for(pass = 0; pass < 10 && retry; pass++) {
		retry = 0;

		list_for_each_entry_safe(page, page2, from, lru) {
			cond_resched();

			if (PageHuge(page))
				rc = unmap_and_move_huge_page(get_new_page,
						private, page, pass > 2, mode);
			else
				rc = unmap_and_move(get_new_page, private,
						page, pass > 2, mode, reason);

			switch(rc) {
			case -ENOMEM:
				goto out;
			case -EAGAIN:
				retry++;
				break;
			case MIGRATEPAGE_SUCCESS:
				nr_succeeded++;
				break;
			default:
				/* Permanent failure */
				nr_failed++;
				break;
			}
		}
	}
	rc = nr_failed + retry;
out:
	if (nr_succeeded)
		count_vm_events(PGMIGRATE_SUCCESS, nr_succeeded);
	if (nr_failed)
		count_vm_events(PGMIGRATE_FAIL, nr_failed);
	trace_mm_migrate_pages(nr_succeeded, nr_failed, mode, reason);

	if (!swapwrite)
		current->flags &= ~PF_SWAPWRITE;

	return rc;
}
```

## Migrate A Page

```c
static int __unmap_and_move(struct page *page, struct page *newpage,
				int force, enum migrate_mode mode)
{
	int rc = -EAGAIN;
	int remap_swapcache = 1;
	struct mem_cgroup *mem;
	struct anon_vma *anon_vma = NULL;

	if (!trylock_page(page)) {
		if (!force || mode == MIGRATE_ASYNC)
			goto out;

		/*
		 * It's not safe for direct compaction to call lock_page.
		 * For example, during page readahead pages are added locked
		 * to the LRU. Later, when the IO completes the pages are
		 * marked uptodate and unlocked. However, the queueing
		 * could be merging multiple pages for one bio (e.g.
		 * mpage_readpages). If an allocation happens for the
		 * second or third page, the process can end up locking
		 * the same page twice and deadlocking. Rather than
		 * trying to be clever about what pages can be locked,
		 * avoid the use of lock_page for direct compaction
		 * altogether.
		 */
		if (current->flags & PF_MEMALLOC)
			goto out;

		lock_page(page);
	}

	/* charge against new page */
	mem_cgroup_prepare_migration(page, newpage, &mem);

	if (PageWriteback(page)) {
		/*
		 * Only in the case of a full synchronous migration is it
		 * necessary to wait for PageWriteback. In the async case,
		 * the retry loop is too short and in the sync-light case,
		 * the overhead of stalling is too much
		 */
		if (mode != MIGRATE_SYNC) {
			rc = -EBUSY;
			goto uncharge;
		}
		if (!force)
			goto uncharge;
		wait_on_page_writeback(page);
	}
	/*
	 * By try_to_unmap(), page->mapcount goes down to 0 here. In this case,
	 * we cannot notice that anon_vma is freed while we migrates a page.
	 * This get_anon_vma() delays freeing anon_vma pointer until the end
	 * of migration. File cache pages are no problem because of page_lock()
	 * File Caches may use write_page() or lock_page() in migration, then,
	 * just care Anon page here.
	 */
	if (PageAnon(page) && !PageKsm(page)) {
		/*
		 * Only page_lock_anon_vma_read() understands the subtleties of
		 * getting a hold on an anon_vma from outside one of its mms.
		 */
		anon_vma = page_get_anon_vma(page);
		if (anon_vma) {
			/*
			 * Anon page
			 */
		} else if (PageSwapCache(page)) {
			/*
			 * We cannot be sure that the anon_vma of an unmapped
			 * swapcache page is safe to use because we don't
			 * know in advance if the VMA that this page belonged
			 * to still exists. If the VMA and others sharing the
			 * data have been freed, then the anon_vma could
			 * already be invalid.
			 *
			 * To avoid this possibility, swapcache pages get
			 * migrated but are not remapped when migration
			 * completes
			 */
			remap_swapcache = 0;
		} else {
			goto uncharge;
		}
	}

	if (unlikely(balloon_page_movable(page))) {
		/*
		 * A ballooned page does not need any special attention from
		 * physical to virtual reverse mapping procedures.
		 * Skip any attempt to unmap PTEs or to remap swap cache,
		 * in order to avoid burning cycles at rmap level, and perform
		 * the page migration right away (proteced by page lock).
		 */
		rc = balloon_page_migrate(newpage, page, mode);
		goto uncharge;
	}

	/*
	 * Corner case handling:
	 * 1. When a new swap-cache page is read into, it is added to the LRU
	 * and treated as swapcache but it has no rmap yet.
	 * Calling try_to_unmap() against a page->mapping==NULL page will
	 * trigger a BUG.  So handle it here.
	 * 2. An orphaned page (see truncate_complete_page) might have
	 * fs-private metadata. The page can be picked up due to memory
	 * offlining.  Everywhere else except page reclaim, the page is
	 * invisible to the vm, so the page can not be migrated.  So try to
	 * free the metadata, so the page can be freed.
	 */
	if (!page->mapping) {
		VM_BUG_ON_PAGE(PageAnon(page), page);
		if (page_has_private(page)) {
			try_to_free_buffers(page);
			goto uncharge;
		}
		goto skip_unmap;
	}

	/* Establish migration ptes or remove ptes */
	try_to_unmap(page, TTU_MIGRATION|TTU_IGNORE_MLOCK|TTU_IGNORE_ACCESS);

skip_unmap:
	if (!page_mapped(page))
		rc = move_to_new_page(newpage, page, remap_swapcache, mode);

	if (rc && remap_swapcache)
		remove_migration_ptes(page, page);

	/* Drop an anon_vma reference if we took one */
	if (anon_vma)
		put_anon_vma(anon_vma);

uncharge:
	mem_cgroup_end_migration(mem, page, newpage,
				 (rc == MIGRATEPAGE_SUCCESS ||
				  rc == MIGRATEPAGE_BALLOON_SUCCESS));
	unlock_page(page);
out:
	return rc;
}
```