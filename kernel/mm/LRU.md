# LRU, inactive_list, active_list

![2014-06-06 17 24 00](https://cloud.githubusercontent.com/assets/172456/3198095/1d04d80c-ed54-11e3-813a-b1754d92e552.png)

[Professional Linux Kernel Architecture](http://www.amazon.com/dp/0470343435)

----

 * 一応 split LRU 以前の図なので注意
 * 1 node の 1 zone を指してる図

## アルゴリズム 

 * LRU
 * second chance 

## 主要な関数群

 * mark_page_accessed
 * page_referenced
   * shrink_page_list -> page_check_references -> ... で呼び出しされる
   * 名前と裏腹に副作用があるのだな
 * shrink_active_list
   * shrink_inactive_list も大事
 * activate_page
 * SetPageActive
 * ClearPageActive

### mark_page_accessed

```c 
/*
 * Mark a page as having seen activity.
 *
 * inactive,unreferenced	->	inactive,referenced   // B
 * inactive,referenced		->	active,unreferenced   // A
 * active,unreferenced		->	active,referenced     // B
 */
void mark_page_accessed(struct page *page)
{
	if (!PageActive(page) && !PageUnevictable(page) &&
			PageReferenced(page) && PageLRU(page)) {
        // パターンA active リストに繋いで referenced を落とす
		activate_page(page);
		ClearPageReferenced(page);
	} else if (!PageReferenced(page)) {
        // パターンB referenced をつけるだけ
		SetPageReferenced(page);
	}
}

EXPORT_SYMBOL(mark_page_accessed);
```

### page_referenced

 * KSM, anon, file によって分岐する
 * 名前からは分からないけど referenced ビットを落とす副作用持っているので注意
   * test_and_clear_referenced でビットを落とす

```c
/**
 * page_referenced - test if the page was referenced
 * @page: the page to test
 * @is_locked: caller holds lock on the page
 * @mem_cont: target memory controller
 * @vm_flags: collect encountered vma->vm_flags who actually referenced the page
 *
 * Quick test_and_clear_referenced for all mappings to a page,
 * returns the number of ptes which referenced the page.
 */
int page_referenced(struct page *page,
		    int is_locked,
		    struct mem_cgroup *mem_cont,
		    unsigned long *vm_flags)
{
	int referenced = 0;
	int we_locked = 0;

	*vm_flags = 0;
	if (page_mapped(page) &&  // アドレス空間にマップされているかどうか
       page_rmapping(page)) { // ?
       
		if (!is_locked && (!PageAnon(page) || PageKsm(page))) {
           // PG_locked をたてようとするt
			we_locked = trylock_page(page);
			if (!we_locked) {
				referenced++;
				goto out;
			}
		}
		if (unlikely(PageKsm(page)))
			referenced += page_referenced_ksm(page, mem_cont,
								vm_flags);
		else if (PageAnon(page))
			referenced += page_referenced_anon(page, mem_cont,
								vm_flags);
		else if (page->mapping)
			referenced += page_referenced_file(page, mem_cont,
								vm_flags);
		if (we_locked)
			unlock_page(page);

		if (page_test_and_clear_young(page))
			referenced++;
	}
out:

	return referenced;
}
```

page_referenced_* 属は下記の用に潜っていく

```
page_referenced_ksm    page_referenced_anon    page_referenced_file
               \                 |                   /
                 \               |                 /
                  +--------------+----------------+
                                 |
                                 |
                        page_referenced_one
                                 |
                                 |
                     ptep_clear_flush_young_notify
                                 |
                                 |
                        ptep_clear_flush_young
                                 |
                                 |
                      ptep_test_and_clear_young 
                                 |
                                 |   
     test_and_clear_bit(_PAGE_BIT_ACCESSED, (unsigned long *) &ptep->pte);
```

#### page_referenced_one

共通で呼び出される page_referenced_one の実装 

```c
/*
 * Subfunctions of page_referenced: page_referenced_one called
 * repeatedly from either page_referenced_anon or page_referenced_file.
 */
int page_referenced_one(struct page *page, struct vm_area_struct *vma,
			unsigned long address, unsigned int *mapcount,
			unsigned long *vm_flags)
{
	struct mm_struct *mm = vma->vm_mm;
	int referenced = 0;

    /* HugePage の場合 */
	if (unlikely(PageTransHuge(page))) {
		pmd_t *pmd;

		spin_lock(&mm->page_table_lock);
		/*
		 * rmap might return false positives; we must filter
		 * these out using page_check_address_pmd().
		 */
         /* pmd_t PMD があるかどうか */
		pmd = page_check_address_pmd(page, mm, address,
					     PAGE_CHECK_ADDRESS_PMD_FLAG);
		if (!pmd) {
			spin_unlock(&mm->page_table_lock);
			goto out;
		}

        /* mlock(2) されてるページは対象外? */
		if (vma->vm_flags & VM_LOCKED) {
			spin_unlock(&mm->page_table_lock);
			*mapcount = 0;	/* break early from loop */
			*vm_flags |= VM_LOCKED;
			goto out;
		}

		/* go ahead even if the pmd is pmd_trans_splitting() */
		if (pmdp_clear_flush_young_notify(vma, address, pmd))
			referenced++;
		spin_unlock(&mm->page_table_lock);
	} else {
        // 普通の呼び出しパスはこっちだろう

		pte_t *pte;      // typedef struct { pteval_t pte; } pte_t;
		spinlock_t *ptl;

		/*
		 * rmap might return false positives; we must filter
		 * these out using page_check_address().
		 */
         // mm->pgd から PGD -> PUD -> PMD と辿って PTE を取る
		pte = page_check_address(page, mm, address, &ptl, 0);
		if (!pte)
			goto out;

		if (vma->vm_flags & VM_LOCKED) {
			pte_unmap_unlock(pte, ptl);
			*mapcount = 0;	/* break early from loop */
			*vm_flags |= VM_LOCKED;
			goto out;
		}

        // PTE の Referenced ビットを落とす
        // https://www.cs.uaf.edu/2007/fall/cs301/lecture/11_30_cache.png
		if (ptep_clear_flush_young_notify(vma, address, pte)) {
			/*
			 * Don't treat a reference through a sequentially read
			 * mapping as such.  If the page has been used in
			 * another mapping, we will catch it; if this other
			 * mapping is already gone, the unmap path will have
			 * set PG_referenced or activated the page.
			 */
			if (likely(!VM_SequentialReadHint(vma)))
				referenced++;
		}
		pte_unmap_unlock(pte, ptl);
	}

	/* Pretend the page is referenced if the task has the
	   swap token and is in the middle of a page fault. */
	if (mm != current->mm && has_swap_token(mm) &&
			rwsem_is_locked(&mm->mmap_sem))
		referenced++;

	(*mapcount)--;

	if (referenced)
		*vm_flags |= vma->vm_flags;
out:
	return referenced;
}
```

pte_young は pte_flags(pte) & _PAGE_ACCESSED の意らしい

### activate_page

Inactive -> Active の LRU 移動

 * 対象の page から zone を選ぶ
 * page が file か anon かを選ぶ
 * SetPageActive する

```c
/*
 * FIXME: speed this up?
 */
void activate_page(struct page *page)
{
	struct zone *zone = page_zone(page);

    // LRU は zone ごとにあるので zone->lru_lock を取る
	spin_lock_irq(&zone->lru_lock);
	if (PageLRU(page)    && // なんだっけ?
       !PageActive(page) && // 既に Active なら何もしない
       !PageUnevictable(page)) {

       // file LRU に入れるべきかどうかを選択
       // return !PageSwapBacked(page);
		int file = page_is_file_cache(page);

        // LRU_INACTIVE_FILE か LRU_INACTIVE_ANON かを選択
		int lru = page_lru_base_type(page);

        // LRU からページを消す
		del_page_from_lru_list(zone, page, lru);

        // Active
		SetPageActive(page);
		lru += LRU_ACTIVE;
		add_page_to_lru_list(zone, page, lru);
		__count_vm_event(PGACTIVATE);

		update_page_reclaim_stat(zone, page, file, 1);
	}
	spin_unlock_irq(&zone->lru_lock);
}
```

### shrink_active_list

shrink_mem_cgroup_zone の過程で呼び出される

 * l_hold に deactivate 候補のページを isolate_pages で集める
 * l_active にやっぱり active に戻すページを集める
 * l_inactive に deactivate 対象のページを集める

```c
static void shrink_active_list(unsigned long nr_pages,
			       struct mem_cgroup_zone *mz,
			       struct scan_control *sc,
			       int priority, int file)
{
	unsigned long nr_taken;
	unsigned long pgscanned;
	unsigned long vm_flags;

    /* 関数無いでページを一時的に保持しておくようのリスト */
	LIST_HEAD(l_hold);	/* The pages which were snipped off */
	LIST_HEAD(l_active);
	LIST_HEAD(l_inactive);
	struct page *page;
	struct zone_reclaim_stat *reclaim_stat = get_reclaim_stat(mz);
	unsigned long nr_rotated = 0;
	int order = 0;
	struct zone *zone = mz->zone;

	if (!COMPACTION_BUILD)
		order = sc->order;

    // pagevecs ( per_cpu のリストの page 群) をLRU に移動させる?
	lru_add_drain();
	spin_lock_irq(&zone->lru_lock);

	nr_taken = isolate_pages(nr_pages, mz, &l_hold,
				 &pgscanned, order,
				 ISOLATE_ACTIVE, 1, file);

	if (global_reclaim(sc))
		zone->pages_scanned += pgscanned;

	reclaim_stat->recent_scanned[file] += nr_taken;

	__count_zone_vm_events(PGREFILL, zone, pgscanned);
	if (file)
		__mod_zone_page_state(zone, NR_ACTIVE_FILE, -nr_taken);
	else
		__mod_zone_page_state(zone, NR_ACTIVE_ANON, -nr_taken);
	__mod_zone_page_state(zone, NR_ISOLATED_ANON + file, nr_taken);
	spin_unlock_irq(&zone->lru_lock);

	while (!list_empty(&l_hold)) {
		cond_resched();
		page = lru_to_page(&l_hold);
		list_del(&page->lru);

		if (unlikely(!page_evictable(page, NULL))) {
			putback_lru_page(page);
			continue;
		}

        /* Referenced ビットが立っているかどうかを見る */
		if (page_referenced(page, 0, sc->target_mem_cgroup, &vm_flags)) {
			nr_rotated += hpage_nr_pages(page);
			/*
			 * Identify referenced, file-backed active pages and
			 * give them one more trip around the active list. So
			 * that executable code get better chances to stay in
			 * memory under moderate memory pressure.  Anon pages
			 * are not likely to be evicted by use-once streaming
			 * IO, plus JVM can create lots of anon VM_EXEC pages,
			 * so we ignore them here.
			 */
             // ファイル backed な active ページを active list に戻す
             // 実行コードがオンメモリに残りやすい
             // anon ページは対象外
             / JVM は VM_EXEC なページを大量に生成する。無視
			if ((vm_flags & VM_EXEC) && page_is_file_cache(page)) {
				list_add(&page->lru, &l_active);
				continue;
			}
		}

        /* Active => Inactive へ移す候補に入れる */
		ClearPageActive(page);	/* we are de-activating */
		list_add(&page->lru, &l_inactive);
	}

	/*
	 * Move pages back to the lru list.
	 */
	spin_lock_irq(&zone->lru_lock);
	/*
	 * Count referenced pages from currently used mappings as rotated,
	 * even though only some of them are actually re-activated.  This
	 * helps balance scan pressure between file and anonymous pages in
	 * get_scan_ratio.
	 */
	reclaim_stat->recent_rotated[file] += nr_rotated;

	move_active_pages_to_lru(zone, &l_active,
						LRU_ACTIVE + file * LRU_FILE);
	move_active_pages_to_lru(zone, &l_inactive,
						LRU_BASE   + file * LRU_FILE);
	__mod_zone_page_state(zone, NR_ISOLATED_ANON + file, -nr_taken);
	spin_unlock_irq(&zone->lru_lock);
	trace_mm_pagereclaim_shrinkactive(pgscanned, file, priority);  
}
```