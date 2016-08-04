# vm.nr_hugepages

## sysctl definition

```
{
		.procname	= "nr_hugepages",
		.data		= NULL,
		.maxlen		= sizeof(unsigned long),
		.mode		= 0644,
		.proc_handler	= hugetlb_sysctl_handler,
	},
```

## sysctl handler

```
int hugetlb_sysctl_handler(struct ctl_table *table, int write,
			  void __user *buffer, size_t *length, loff_t *ppos)
{

	return hugetlb_sysctl_handler_common(false, table, write,
							buffer, length, ppos);
}

static int hugetlb_sysctl_handler_common(bool obey_mempolicy,
			 struct ctl_table *table, int write,
			 void __user *buffer, size_t *length, loff_t *ppos)
{
	struct hstate *h = &default_hstate;
	unsigned long tmp = h->max_huge_pages;
	int ret;

	if (!hugepages_supported())
		return -ENOTSUPP;

	table->data = &tmp;
	table->maxlen = sizeof(unsigned long);
	ret = proc_doulongvec_minmax(table, write, buffer, length, ppos);
	if (ret)
		goto out;

	if (write)
		ret = __nr_hugepages_store_common(obey_mempolicy, h,
						  NUMA_NO_NODE, tmp, *length);
out:
	return ret;
}
```

## allocate hugepages

```c
static ssize_t __nr_hugepages_store_common(bool obey_mempolicy,
					   struct hstate *h, int nid,
					   unsigned long count, size_t len)
{
	int err;
	NODEMASK_ALLOC(nodemask_t, nodes_allowed, GFP_KERNEL | __GFP_NORETRY);

    // MAX_ORDER を超えてる
	if (hstate_is_gigantic(h) && !gigantic_page_supported()) {
		err = -EINVAL;
		goto out;
	}

    // sysctl 経由だと nid == NUMA_NO_NODE   
	if (nid == NUMA_NO_NODE) {
		/*
		 * global hstate attribute
		 */
        // sysctl 経由だと false == obey_mempolicy
		if (!(obey_mempolicy &&
				init_nodemask_of_mempolicy(nodes_allowed))) {
			NODEMASK_FREE(nodes_allowed);
            // node を指定
			nodes_allowed = &node_states[N_MEMORY];
		}
	} else if (nodes_allowed) {
		/*
		 * per node hstate attribute: adjust count to global,
		 * but restrict alloc/free to the specified node.
		 */
		count += h->nr_huge_pages - h->nr_huge_pages_node[nid];
		init_nodemask_of_node(nodes_allowed, nid);
	} else
		nodes_allowed = &node_states[N_MEMORY];

	h->max_huge_pages = set_max_huge_pages(h, count, nodes_allowed);

	if (nodes_allowed != &node_states[N_MEMORY])
		NODEMASK_FREE(nodes_allowed);

	return len;
out:
	NODEMASK_FREE(nodes_allowed);
	return err;
}
```

```c
static unsigned long set_max_huge_pages(struct hstate *h, unsigned long count,
						nodemask_t *nodes_allowed)
{
	unsigned long min_count, ret;

	if (hstate_is_gigantic(h) && !gigantic_page_supported())
		return h->max_huge_pages;

	/*
	 * Increase the pool size
	 * First take pages out of surplus state.  Then make up the
	 * remaining difference by allocating fresh huge pages.
	 *
	 * We might race with alloc_buddy_huge_page() here and be unable
	 * to convert a surplus huge page to a normal huge page. That is
	 * not critical, though, it just means the overall size of the
	 * pool might be one hugepage larger than it needs to be, but
	 * within all the constraints specified by the sysctls.
	 */
	spin_lock(&hugetlb_lock);
    // surplus 余剰
	while (h->surplus_huge_pages && count > persistent_huge_pages(h)) {
		if (!adjust_pool_surplus(h, nodes_allowed, -1))
			break;
	}

	while (count > persistent_huge_pages(h)) {
		/*
		 * If this allocation races such that we no longer need the
		 * page, free_huge_page will handle it by freeing the page
		 * and reducing the surplus.
		 */
		spin_unlock(&hugetlb_lock);

        // hstate_is_gigantic MAX_ORDER 11 以上
        // 2MB 以上の場合
		if (hstate_is_gigantic(h))
			ret = alloc_fresh_gigantic_page(h, nodes_allowed);
		else
			ret = alloc_fresh_huge_page(h, nodes_allowed);
		spin_lock(&hugetlb_lock);
		if (!ret)
			goto out;

		/* Bail for signals. Probably ctrl-c from user */
		if (signal_pending(current))
			goto out;
	}

	/*
	 * Decrease the pool size
	 * First return free pages to the buddy allocator (being careful
	 * to keep enough around to satisfy reservations).  Then place
	 * pages into surplus state as needed so the pool will shrink
	 * to the desired size as pages become free.
	 *
	 * By placing pages into the surplus state independent of the
	 * overcommit value, we are allowing the surplus pool size to
	 * exceed overcommit. There are few sane options here. Since
	 * alloc_buddy_huge_page() is checking the global counter,
	 * though, we'll note that we're not allowed to exceed surplus
	 * and won't grow the pool anywhere else. Not until one of the
	 * sysctls are changed, or the surplus pages go out of use.
	 */
	min_count = h->resv_huge_pages + h->nr_huge_pages - h->free_huge_pages;
	min_count = max(count, min_count);
	try_to_free_low(h, min_count, nodes_allowed);
	while (min_count < persistent_huge_pages(h)) {
		if (!free_pool_huge_page(h, nodes_allowed, 0))
			break;
		cond_resched_lock(&hugetlb_lock);
	}
	while (count < persistent_huge_pages(h)) {
		if (!adjust_pool_surplus(h, nodes_allowed, 1))
			break;
	}
out:
	ret = persistent_huge_pages(h);
	spin_unlock(&hugetlb_lock);
	return ret;
}
```

```c
static struct page *alloc_fresh_gigantic_page_node(struct hstate *h, int nid)
{
	struct page *page;

	page = alloc_gigantic_page(nid, huge_page_order(h));
	if (page) {
		prep_compound_gigantic_page(page, huge_page_order(h));
		prep_new_huge_page(h, page, nid);
	}

	return page;
}
```

```c
static struct page *alloc_gigantic_page(int nid, unsigned order)
{
	unsigned long nr_pages = 1 << order;
	unsigned long ret, pfn, flags;
	struct zone *z;

	z = NODE_DATA(nid)->node_zones;

    // iterate nodes
	for (; z - NODE_DATA(nid)->node_zones < MAX_NR_ZONES; z++) {
		spin_lock_irqsave(&z->lock, flags);

        // zone の開始ページフレームと、必要なページ数でアラインしたページフレーム番号
		pfn = ALIGN(z->zone_start_pfn, nr_pages);

        // pfn + nr_pages が zone 内に収まっている範囲で
		while (zone_spans_last_pfn(z, pfn, nr_pages)) {

            // 1. ページフレーム番号のバリデーション
            // 2. reserverd ページでないか?
            // 3. shared なページでないか?
            // static bool pfn_range_valid_gigantic(unsigned long start_pfn,
            // 				unsigned long nr_pages)
            // {
            // 	unsigned long i, end_pfn = start_pfn + nr_pages;
            // 	struct page *page;
            // 
            // 	for (i = start_pfn; i < end_pfn; i++) {
            // 		if (!pfn_valid(i))
            // 			return false;
            // 
            // 		page = pfn_to_page(i);
            // 
            // 		if (PageReserved(page))
            // 			return false;
            // 
            // 		if (page_count(page) > 0)
            // 			return false;
            // 
            // 		if (PageHuge(page))
            // 			return false;
            // 	}
            // 
            // 	return true;
            // }
            //
            
			if (pfn_range_valid_gigantic(pfn, nr_pages)) {
				/*
				 * We release the zone lock here because
				 * alloc_contig_range() will also lock the zone
				 * at some point. If there's an allocation
				 * spinning on this lock, it may win the race
				 * and cause alloc_contig_range() to fail...
				 */
                 
                 // alloc_contig_range するのでスピンロック外す
				spin_unlock_irqrestore(&z->lock, flags);
				ret = __alloc_gigantic_page(pfn, nr_pages);
				if (!ret)
                    // ページフレーム番号から struct page* に変換
					return pfn_to_page(pfn);
				spin_lock_irqsave(&z->lock, flags);
			}
			pfn += nr_pages;
		}

		spin_unlock_irqrestore(&z->lock, flags);
	}

	return NULL;
}
```


```
 start_pfn
/
[][][][][][][][][][]
\
 -------------------> nr_pages
```

```C
static int __alloc_gigantic_page(unsigned long start_pfn,
				unsigned long nr_pages)
{
	unsigned long end_pfn = start_pfn + nr_pages;
	return alloc_contig_range(start_pfn, end_pfn, MIGRATE_MOVABLE);
}

ページフレーム番号の start と最後を指定して 連続したページフレームを割り当てる
ゾーンにおさまる ページフレーム番号であること

/**
 * alloc_contig_range() -- tries to allocate given range of pages
 * @start:	start PFN to allocate
 * @end:	one-past-the-last PFN to allocate
 * @migratetype:	migratetype of the underlaying pageblocks (either
 *			#MIGRATE_MOVABLE or #MIGRATE_CMA).  All pageblocks
 *			in range must have the same migratetype and it must
 *			be either of the two.
 *
 * The PFN range does not have to be pageblock or MAX_ORDER_NR_PAGES
 * aligned, however it's the caller's responsibility to guarantee that
 * we are the only thread that changes migrate type of pageblocks the
 * pages fall in.
 *
 * The PFN range must belong to a single zone.
 *
 * Returns zero on success or negative error code.  On success all
 * pages which PFN is in [start, end) are allocated for the caller and
 * need to be freed with free_contig_range().
 */
int alloc_contig_range(unsigned long start, unsigned long end,
		       unsigned migratetype)
{
	unsigned long outer_start, outer_end;
	int ret = 0, order;

	struct compact_control cc = {
		.nr_migratepages = 0,
		.order = -1,
		.zone = page_zone(pfn_to_page(start)),
		.mode = MIGRATE_SYNC,
		.ignore_skip_hint = true,
	};
	INIT_LIST_HEAD(&cc.migratepages);

	/*
	 * What we do here is we mark all pageblocks in range as
	 * MIGRATE_ISOLATE.  Because pageblock and max order pages may
	 * have different sizes, and due to the way page allocator
	 * work, we align the range to biggest of the two pages so
	 * that page allocator won't try to merge buddies from
	 * different pageblocks and change MIGRATE_ISOLATE to some
	 * other migration type.
	 *
	 * Once the pageblocks are marked as MIGRATE_ISOLATE, we
	 * migrate the pages from an unaligned range (ie. pages that
	 * we are interested in).  This will put all the pages in
	 * range back to page allocator as MIGRATE_ISOLATE.
	 *
	 * When this is done, we take the pages in range from page
	 * allocator removing them from the buddy system.  This way
	 * page allocator will never consider using them.
	 *
	 * This lets us mark the pageblocks back as
	 * MIGRATE_CMA/MIGRATE_MOVABLE so that free pages in the
	 * aligned range but not in the unaligned, original range are
	 * put back to page allocator so that buddy can use them.
	 */

	ret = start_isolate_page_range(pfn_max_align_down(start),
				       pfn_max_align_up(end), migratetype,
				       false);
	if (ret)
		return ret;

	ret = __alloc_contig_migrate_range(&cc, start, end);
	if (ret)
		goto done;

	/*
	 * Pages from [start, end) are within a MAX_ORDER_NR_PAGES
	 * aligned blocks that are marked as MIGRATE_ISOLATE.  What's
	 * more, all pages in [start, end) are free in page allocator.
	 * What we are going to do is to allocate all pages from
	 * [start, end) (that is remove them from page allocator).
	 *
	 * The only problem is that pages at the beginning and at the
	 * end of interesting range may be not aligned with pages that
	 * page allocator holds, ie. they can be part of higher order
	 * pages.  Because of this, we reserve the bigger range and
	 * once this is done free the pages we are not interested in.
	 *
	 * We don't have to hold zone->lock here because the pages are
	 * isolated thus they won't get removed from buddy.
	 */

	lru_add_drain_all();
	drain_all_pages(cc.zone);

	order = 0;
	outer_start = start;
	while (!PageBuddy(pfn_to_page(outer_start))) {
		if (++order >= MAX_ORDER) {
			ret = -EBUSY;
			goto done;
		}
		outer_start &= ~0UL << order;
	}

	/* Make sure the range is really isolated. */
	if (test_pages_isolated(outer_start, end, false)) {
		pr_info("%s: [%lx, %lx) PFNs busy\n",
			__func__, outer_start, end);
		ret = -EBUSY;
		goto done;
	}

	/* Grab isolated pages from freelists. */
	outer_end = isolate_freepages_range(&cc, outer_start, end);
	if (!outer_end) {
		ret = -EBUSY;
		goto done;
	}

	/* Free head and tail (if any) */
	if (start != outer_start)
		free_contig_range(outer_start, start - outer_start);
	if (end != outer_end)
		free_contig_range(end, outer_end - end);

done:
	undo_isolate_page_range(pfn_max_align_down(start),
				pfn_max_align_up(end), migratetype);
	return ret;
}
```

```c
/* [start, end) must belong to a single zone. */
static int __alloc_contig_migrate_range(struct compact_control *cc,
					unsigned long start, unsigned long end)
{
	/* This function is based on compact_zone() from compaction.c. */
	unsigned long nr_reclaimed;
	unsigned long pfn = start;
	unsigned int tries = 0;
	int ret = 0;

	migrate_prep();

	while (pfn < end || !list_empty(&cc->migratepages)) {
		if (fatal_signal_pending(current)) {
			ret = -EINTR;
			break;
		}

		if (list_empty(&cc->migratepages)) {
			cc->nr_migratepages = 0;
			pfn = isolate_migratepages_range(cc, pfn, end);
			if (!pfn) {
				ret = -EINTR;
				break;
			}
			tries = 0;
		} else if (++tries == 5) {
			ret = ret < 0 ? ret : -EBUSY;
			break;
		}

		nr_reclaimed = reclaim_clean_pages_from_list(cc->zone,
							&cc->migratepages);
		cc->nr_migratepages -= nr_reclaimed;

		ret = migrate_pages(&cc->migratepages, alloc_migrate_target,
				    NULL, 0, cc->mode, MR_CMA);
	}
	if (ret < 0) {
		putback_movable_pages(&cc->migratepages);
		return ret;
	}
	return 0;
}
```

```c
/**
 * isolate_migratepages_range() - isolate migrate-able pages in a PFN range
 * @cc:        Compaction control structure.
 * @start_pfn: The first PFN to start isolating.
 * @end_pfn:   The one-past-last PFN.
 *
 * Returns zero if isolation fails fatally due to e.g. pending signal.
 * Otherwise, function returns one-past-the-last PFN of isolated page
 * (which may be greater than end_pfn if end fell in a middle of a THP page).
 */
unsigned long
isolate_migratepages_range(struct compact_control *cc, unsigned long start_pfn,
							unsigned long end_pfn)
{
	unsigned long pfn, block_end_pfn;

	/* Scan block by block. First and last block may be incomplete */
	pfn = start_pfn;
	block_end_pfn = ALIGN(pfn + 1, pageblock_nr_pages);

	for (; pfn < end_pfn; pfn = block_end_pfn,
				block_end_pfn += pageblock_nr_pages) {

		block_end_pfn = min(block_end_pfn, end_pfn);

		if (!pageblock_pfn_to_page(pfn, block_end_pfn, cc->zone))
			continue;

		pfn = isolate_migratepages_block(cc, pfn, block_end_pfn,
							ISOLATE_UNEVICTABLE);

		/*
		 * In case of fatal failure, release everything that might
		 * have been isolated in the previous iteration, and signal
		 * the failure back to caller.
		 */
		if (!pfn) {
			putback_movable_pages(&cc->migratepages);
			cc->nr_migratepages = 0;
			break;
		}

		if (cc->nr_migratepages == COMPACT_CLUSTER_MAX)
			break;
	}
	acct_isolated(cc->zone, cc);

	return pfn;
}
```

```c
/**
 * isolate_migratepages_block() - isolate all migrate-able pages within
 *				  a single pageblock
 * @cc:		Compaction control structure.
 * @low_pfn:	The first PFN to isolate
 * @end_pfn:	The one-past-the-last PFN to isolate, within same pageblock
 * @isolate_mode: Isolation mode to be used.
 *
 * Isolate all pages that can be migrated from the range specified by
 * [low_pfn, end_pfn). The range is expected to be within same pageblock.
 * Returns zero if there is a fatal signal pending, otherwise PFN of the
 * first page that was not scanned (which may be both less, equal to or more
 * than end_pfn).
 *
 * The pages are isolated on cc->migratepages list (not required to be empty),
 * and cc->nr_migratepages is updated accordingly. The cc->migrate_pfn field
 * is neither read nor updated.
 */
static unsigned long
isolate_migratepages_block(struct compact_control *cc, unsigned long low_pfn,
			unsigned long end_pfn, isolate_mode_t isolate_mode)
{
	struct zone *zone = cc->zone;
	unsigned long nr_scanned = 0, nr_isolated = 0;
	struct list_head *migratelist = &cc->migratepages;
	struct lruvec *lruvec;
	unsigned long flags = 0;
	bool locked = false;
	struct page *page = NULL, *valid_page = NULL;
	unsigned long start_pfn = low_pfn;

	/*
	 * Ensure that there are not too many pages isolated from the LRU
	 * list by either parallel reclaimers or compaction. If there are,
	 * delay for some time until fewer pages are isolated
	 */
	while (unlikely(too_many_isolated(zone))) {
		/* async migration should just abort */
		if (cc->mode == MIGRATE_ASYNC)
			return 0;

		congestion_wait(BLK_RW_ASYNC, HZ/10);

		if (fatal_signal_pending(current))
			return 0;
	}

	if (compact_should_abort(cc))
		return 0;

	/* Time to isolate some pages for migration */
	for (; low_pfn < end_pfn; low_pfn++) {
		bool is_lru;

		/*
		 * Periodically drop the lock (if held) regardless of its
		 * contention, to give chance to IRQs. Abort async compaction
		 * if contended.
		 */
		if (!(low_pfn % SWAP_CLUSTER_MAX)
		    && compact_unlock_should_abort(&zone->lru_lock, flags,
								&locked, cc))
			break;

		if (!pfn_valid_within(low_pfn))
			continue;
		nr_scanned++;

       // struct page にする
		page = pfn_to_page(low_pfn);

		if (!valid_page)
			valid_page = page;

		/*
		 * Skip if free. We read page order here without zone lock
		 * which is generally unsafe, but the race window is small and
		 * the worst thing that can happen is that we skip some
		 * potential isolation targets.
		 */
		if (PageBuddy(page)) {
			unsigned long freepage_order = page_order_unsafe(page);

			/*
			 * Without lock, we cannot be sure that what we got is
			 * a valid page order. Consider only values in the
			 * valid order range to prevent low_pfn overflow.
			 */
			if (freepage_order > 0 && freepage_order < MAX_ORDER)
				low_pfn += (1UL << freepage_order) - 1;
			continue;
		}

		/*
		 * Check may be lockless but that's ok as we recheck later.
		 * It's possible to migrate LRU pages and balloon pages
		 * Skip any other type of page
		 */
		is_lru = PageLRU(page);
		if (!is_lru) {
			if (unlikely(balloon_page_movable(page))) {
				if (balloon_page_isolate(page)) {
					/* Successfully isolated */
					goto isolate_success;
				}
			}
		}

		/*
		 * Regardless of being on LRU, compound pages such as THP and
		 * hugetlbfs are not to be compacted. We can potentially save
		 * a lot of iterations if we skip them at once. The check is
		 * racy, but we can consider only valid values and the only
		 * danger is skipping too much.
		 */
		if (PageCompound(page)) {
			unsigned int comp_order = compound_order(page);

			if (likely(comp_order < MAX_ORDER))
				low_pfn += (1UL << comp_order) - 1;

			continue;
		}

		if (!is_lru)
			continue;

		/*
		 * Migration will fail if an anonymous page is pinned in memory,
		 * so avoid taking lru_lock and isolating it unnecessarily in an
		 * admittedly racy check.
		 */
		if (!page_mapping(page) &&
		    page_count(page) > page_mapcount(page))
			continue;

		/* If we already hold the lock, we can skip some rechecking */
		if (!locked) {
			locked = compact_trylock_irqsave(&zone->lru_lock,
								&flags, cc);
			if (!locked)
				break;

			/* Recheck PageLRU and PageCompound under lock */
			if (!PageLRU(page))
				continue;

			/*
			 * Page become compound since the non-locked check,
			 * and it's on LRU. It can only be a THP so the order
			 * is safe to read and it's 0 for tail pages.
			 */
			if (unlikely(PageCompound(page))) {
				low_pfn += (1UL << compound_order(page)) - 1;
				continue;
			}
		}

		lruvec = mem_cgroup_page_lruvec(page, zone);

		/* Try isolate the page */
		if (__isolate_lru_page(page, isolate_mode) != 0)
			continue;

		VM_BUG_ON_PAGE(PageCompound(page), page);

		/* Successfully isolated */
        // struct page を LRU から外す = isolate ?
		del_page_from_lru_list(page, lruvec, page_lru(page));

isolate_success:
		list_add(&page->lru, migratelist);
		cc->nr_migratepages++;
		nr_isolated++;

		/* Avoid isolating too much */
		if (cc->nr_migratepages == COMPACT_CLUSTER_MAX) {
			++low_pfn;
			break;
		}
	}

	/*
	 * The PageBuddy() check could have potentially brought us outside
	 * the range to be scanned.
	 */
	if (unlikely(low_pfn > end_pfn))
		low_pfn = end_pfn;

	if (locked)
		spin_unlock_irqrestore(&zone->lru_lock, flags);

	/*
	 * Update the pageblock-skip information and cached scanner pfn,
	 * if the whole pageblock was scanned without isolating any page.
	 */
	if (low_pfn == end_pfn)
		update_pageblock_skip(cc, valid_page, nr_isolated, true);

	trace_mm_compaction_isolate_migratepages(start_pfn, low_pfn,
						nr_scanned, nr_isolated);

	count_compact_events(COMPACTMIGRATE_SCANNED, nr_scanned);
	if (nr_isolated)
		count_compact_events(COMPACTISOLATED, nr_isolated);

	return low_pfn;
}
```