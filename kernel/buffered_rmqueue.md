# buffered_rmqueue

Linux Kernel Arcitecture P264, P.265,

## 要点

get_page_from_freelist から呼び出される

ページを解放する zone を決めた後

 * ページが連続( contiguous ) しているか
 * order = 0 の場合
   * per-CPU page cahce から free なページを取る
 * order > 0 の場合
   * free_lists から free なページを取る

## ソース   

 ```c
 /*
 * Really, prep_compound_page() should be called from __rmqueue_bulk().  But
 * we cheat by calling it from here, in the order > 0 path.  Saves a branch
 * or two.
 */
static inline
struct page *buffered_rmqueue(struct zone *preferred_zone,
			struct zone *zone, int order, gfp_t gfp_flags,
			int migratetype)
{
	unsigned long flags;
	struct page *page;
	int cold = !!(gfp_flags & __GFP_COLD);
	int cpu;

again:
	cpu  = get_cpu();

    // 欲しいページのオーダーが 0 = 2**0 = 1 個の場合は per_cpu_pages から取る用最適化されている
	if (likely(order == 0)) {
		struct per_cpu_pages *pcp;
		struct list_head *list;

		pcp = &zone_pcp(zone, cpu)->pcp;
		list = &pcp->lists[migratetype];
		local_irq_save(flags);
		if (list_empty(list))
        {
            // per_cpu_pages 足らない!
            // rmqueue_bulk の中は __rmqueue 呼び出し
			pcp->count += rmqueue_bulk(zone, 0,
					pcp->batch, list,
					migratetype, cold);
			if (unlikely(list_empty(list)))
				goto failed;
		}

        // per_cpu_pages のキャッシュ
		if (cold)
			page = list_entry(list->prev, struct page, lru);
		else
			page = list_entry(list->next, struct page, lru);

		list_del(&page->lru);
		pcp->count--;
	} else {
		if (unlikely(gfp_flags & __GFP_NOFAIL)) {
			/*
			 * __GFP_NOFAIL is not to be used in new code.
			 *
			 * All __GFP_NOFAIL callers should be fixed so that they
			 * properly detect and handle allocation failures.
			 *
			 * We most definitely don't want callers attempting to
			 * allocate greater than order-1 page units with
			 * __GFP_NOFAIL.
			 */
			WARN_ON_ONCE(order > 1);
		}
		spin_lock_irqsave(&zone->lock, flags);
        // ->
		page = __rmqueue(zone, order, migratetype);
		spin_unlock(&zone->lock);
		if (!page)
			goto failed;

        // 空きページの数を増やす
		__mod_zone_page_state(zone, NR_FREE_PAGES, -(1 << order));
	}

	__count_zone_vm_events(PGALLOC, zone, 1 << order);
	zone_statistics(preferred_zone, zone, gfp_flags);
	local_irq_restore(flags);
	put_cpu();

	VM_BUG_ON(bad_range(zone, page));
	if (prep_new_page(page, order, gfp_flags))
		goto again;
	return page;

failed:
    // free なページが無い!
	local_irq_restore(flags);
	put_cpu();
	return NULL;
}
```

free なページを取れた場合は prep_new_page で page の初期化? をする

 * prep_zero_page 以下の動作は [ページのゼロ初期化](https://github.com/hiboma/hiboma/blob/master/kernel/%E3%83%98%E3%82%9A%E3%83%BC%E3%82%B7%E3%82%99%E3%81%AE%E3%82%BB%E3%82%99%E3%83%AD%E5%88%9D%E6%9C%9F%E5%8C%96.md) も合わせて読むとよい

```c
static int prep_new_page(struct page *page, int order, gfp_t gfp_flags)
{
	int i;

	for (i = 0; i < (1 << order); i++) {
		struct page *p = page + i;
		if (unlikely(check_new_page(p)))
			return 1;
	}

	set_page_private(page, 0);
	set_page_refcounted(page);

	arch_alloc_page(page, order);
	kernel_map_pages(page, 1 << order, 1);

    // ゼロ初期化
	if (gfp_flags & __GFP_ZERO)
		prep_zero_page(page, order, gfp_flags);

	if (order && (gfp_flags & __GFP_COMP))
		prep_compound_page(page, order);

	return 0;
}
```

__rmqueue

 * __rmqueue_smallest を試す
 * free な page を取れないなら __rmqueue_fallback を試す
 * MIGRATE_RESERVE をつけてもういっぺん __rmqueue_smallest を試す

```c
/*
 * Do the hard work of removing an element from the buddy allocator.
 * Call me with the zone->lock already held.
 */
static struct page *__rmqueue(struct zone *zone, unsigned int order,
						int migratetype)
{
	struct page *page;

retry_reserve:
	page = __rmqueue_smallest(zone, order, migratetype);

	if (unlikely(!page) && migratetype != MIGRATE_RESERVE) {
		page = __rmqueue_fallback(zone, order, migratetype);

		/*
		 * Use MIGRATE_RESERVE rather than fail an allocation. goto
		 * is used because __rmqueue_smallest is an inline function
		 * and we want just one call site
		 */
		if (!page) {
			migratetype = MIGRATE_RESERVE;
			goto retry_reserve;
		}
	}

	trace_mm_page_alloc_zone_locked(page, order, migratetype);
	return page;
}
```