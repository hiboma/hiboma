# LRU

![2014-06-06 17 24 00](https://cloud.githubusercontent.com/assets/172456/3198095/1d04d80c-ed54-11e3-813a-b1754d92e552.png)

split LRU 以前の図なので注意

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

### activate_page

Inactive -> Active の LRU 移動

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