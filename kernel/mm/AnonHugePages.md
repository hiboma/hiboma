# AnonHugePages

```
$ grep AnonHugePages /proc/meminfo
		"AnonHugePages:  %8lu kB\n"
```

## implementation of /proc/meminfo

```
#ifdef CONFIG_TRANSPARENT_HUGEPAGE
		"AnonHugePages:  %8lu kB\n"
#endif

...

#ifdef CONFIG_TRANSPARENT_HUGEPAGE
		,K(global_page_state(NR_ANON_TRANSPARENT_HUGEPAGES) *
		   HPAGE_PMD_NR)
#endif
```

## What funciton allocates Hugepages?

#### alloc_huge_page

```c
static struct page *alloc_huge_page(struct vm_area_struct *vma,
				    unsigned long addr, int avoid_reserve)
{
	struct hugepage_subpool *spool = subpool_vma(vma);
	struct hstate *h = hstate_vma(vma);
	struct page *page;
	long chg;
	int ret, idx;
	struct hugetlb_cgroup *h_cg;

	idx = hstate_index(h);
	/*
	 * Processes that did not create the mapping will have no
	 * reserves and will not have accounted against subpool
	 * limit. Check that the subpool limit can be made before
	 * satisfying the allocation MAP_NORESERVE mappings may also
	 * need pages and subpool limit allocated allocated if no reserve
	 * mapping overlaps.
	 */
	chg = vma_needs_reservation(h, vma, addr);
	if (chg < 0)
		return ERR_PTR(-ENOMEM);
	if (chg || avoid_reserve)
		if (hugepage_subpool_get_pages(spool, 1))
			return ERR_PTR(-ENOSPC);

    // cgroup の閾値超えていないかどうか
	ret = hugetlb_cgroup_charge_cgroup(idx, pages_per_huge_page(h), &h_cg);
	if (ret) {
		if (chg || avoid_reserve)
			hugepage_subpool_put_pages(spool, 1);
		return ERR_PTR(-ENOSPC);
	}

    // >>> critical section
	spin_lock(&hugetlb_lock);

    // ここで hugepage_freelist から page を持ってくる
	page = dequeue_huge_page_vma(h, vma, addr, avoid_reserve, chg);
	if (!page) {
		spin_unlock(&hugetlb_lock);
        // hugepage_freelist に page ない場合は alloc_pages で割当
        // 連続した領域になるんだっけ???
        // huge_page_order(h) 分の page を返す
		page = alloc_buddy_huge_page(h, NUMA_NO_NODE);
		if (!page) {
            // 割当失敗
            // ENOMEM でなくて ENOSPC なのがポイント?
			hugetlb_cgroup_uncharge_cgroup(idx,
						       pages_per_huge_page(h),
						       h_cg);
			if (chg || avoid_reserve)
				hugepage_subpool_put_pages(spool, 1);
			return ERR_PTR(-ENOSPC);
		}
		spin_lock(&hugetlb_lock);

        // 使用中の page は hugepage_activelist につなげておく
		list_move(&page->lru, &h->hugepage_activelist);
		/* Fall through */
	}
    // 使用量のコミット
	hugetlb_cgroup_commit_charge(idx, pages_per_huge_page(h), h_cg, page);

	spin_unlock(&hugetlb_lock);
    // <<< critical section    

	set_page_private(page, (unsigned long)spool);

	vma_commit_reservation(h, vma, addr);
	return page;
}
```

page are allcoated by alloc_buddy_huge_page (buddy system).

#### alloc_buddy_huge_page

```c
static struct page *alloc_buddy_huge_page(struct hstate *h, int nid)
{
	struct page *page;
	unsigned int r_nid;

	if (hstate_is_gigantic(h))
		return NULL;

	/*
	 * Assume we will successfully allocate the surplus page to
	 * prevent racing processes from causing the surplus to exceed
	 * overcommit
	 *
	 * This however introduces a different race, where a process B
	 * tries to grow the static hugepage pool while alloc_pages() is
	 * called by process A. B will only examine the per-node
	 * counters in determining if surplus huge pages can be
	 * converted to normal huge pages in adjust_pool_surplus(). A
	 * won't be able to increment the per-node counter, until the
	 * lock is dropped by B, but B doesn't drop hugetlb_lock until
	 * no more huge pages can be converted from surplus to normal
	 * state (and doesn't try to convert again). Thus, we have a
	 * case where a surplus huge page exists, the pool is grown, and
	 * the surplus huge page still exists after, even though it
	 * should just have been converted to a normal huge page. This
	 * does not leak memory, though, as the hugepage will be freed
	 * once it is out of use. It also does not allow the counters to
	 * go out of whack in adjust_pool_surplus() as we don't modify
	 * the node values until we've gotten the hugepage and only the
	 * per-node value is checked there.
	 */
	spin_lock(&hugetlb_lock);
	if (h->surplus_huge_pages >= h->nr_overcommit_huge_pages) {
		spin_unlock(&hugetlb_lock);
		return NULL;
	} else {
		h->nr_huge_pages++;
		h->surplus_huge_pages++;
	}
	spin_unlock(&hugetlb_lock);

	if (nid == NUMA_NO_NODE)
		page = alloc_pages(htlb_alloc_mask|__GFP_COMP|
				   __GFP_REPEAT|__GFP_NOWARN,
				   huge_page_order(h));
	else
		page = alloc_pages_exact_node(nid,
			htlb_alloc_mask|__GFP_COMP|__GFP_THISNODE|
			__GFP_REPEAT|__GFP_NOWARN, huge_page_order(h));

	if (page && arch_prepare_hugepage(page)) {
		__free_pages(page, huge_page_order(h));
		page = NULL;
	}

	spin_lock(&hugetlb_lock);
	if (page) {
		INIT_LIST_HEAD(&page->lru);
		r_nid = page_to_nid(page);
		set_compound_page_dtor(page, free_huge_page);
		set_hugetlb_cgroup(page, NULL);
		/*
		 * We incremented the global counters already
		 */
		h->nr_huge_pages_node[r_nid]++;
		h->surplus_huge_pages_node[r_nid]++;
		__count_vm_event(HTLB_BUDDY_PGALLOC);
	} else {
		h->nr_huge_pages--;
		h->surplus_huge_pages--;
		__count_vm_event(HTLB_BUDDY_PGALLOC_FAIL);
	}
	spin_unlock(&hugetlb_lock);

	return page;
}
```

## Where NR_ANON_TRANSPARENT_HUGEPAGES is count up?

#### do_page_add_anon_rmap

 * `PageTransHuge`

```c
/*
 * Special version of the above for do_swap_page, which often runs
 * into pages that are exclusively owned by the current process.
 * Everybody else should continue to use page_add_anon_rmap above.
 */
void do_page_add_anon_rmap(struct page *page,
	struct vm_area_struct *vma, unsigned long address, int exclusive)
{
	int first = atomic_inc_and_test(&page->_mapcount);
	if (first) {
		if (!PageTransHuge(page))
			__inc_zone_page_state(page, NR_ANON_PAGES);
		else
			__inc_zone_page_state(page,
					      NR_ANON_TRANSPARENT_HUGEPAGES);
	}
```

#### page_add_anon_rmap

```c
caller: do_anonymous_page 

/**
 * page_add_new_anon_rmap - add pte mapping to a new anonymous page
 * @page:	the page to add the mapping to
 * @vma:	the vm area in which the mapping is added
 * @address:	the user virtual address mapped
 *
 * Same as page_add_anon_rmap but must only be called on *new* pages.
 * This means the inc-and-test can be bypassed.
 * Page does not have to be locked.
 */
void page_add_new_anon_rmap(struct page *page,
	struct vm_area_struct *vma, unsigned long address)
{
	VM_BUG_ON(address < vma->vm_start || address >= vma->vm_end);
	SetPageSwapBacked(page);
	atomic_set(&page->_mapcount, 0); /* increment count (starts at -1) */
	if (!PageTransHuge(page))
		__inc_zone_page_state(page, NR_ANON_PAGES);
	else
		__inc_zone_page_state(page, NR_ANON_TRANSPARENT_HUGEPAGES);
	__page_set_anon_rmap(page, vma, address, 1);
	if (!mlocked_vma_newpage(vma, page)) {
		SetPageActive(page);
		lru_cache_add(page);
	} else
		add_page_to_unevictable_list(page);
}
```

```
#ifdef CONFIG_TRANSPARENT_HUGEPAGE
/*
 * PageHuge() only returns true for hugetlbfs pages, but not for
 * normal or transparent huge pages.
 *
 * PageTransHuge() returns true for both transparent huge and
 * hugetlbfs pages, but not normal pages. PageTransHuge() can only be
 * called only in the core VM paths where hugetlbfs pages can't exist.
 */
static inline int PageTransHuge(struct page *page)
{
	VM_BUG_ON_PAGE(PageTail(page), page);
	return PageHead(page);
}
```