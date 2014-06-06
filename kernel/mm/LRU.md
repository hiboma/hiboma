# LRU

![2014-06-06 17 24 00](https://cloud.githubusercontent.com/assets/172456/3198095/1d04d80c-ed54-11e3-813a-b1754d92e552.png)

split LRU 以前の図なので注意

## 主要な関数群

 * mark_page_accessed
   * activate_page
 * page_referenced
 * shrink_active_list

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

### activate_page

Inactive -> Active の LRU 移動

 * zone を選ぶ
 * file か anon かを選ぶ
 * SetPageActive

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