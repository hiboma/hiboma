# LRU

![2014-06-06 17 24 00](https://cloud.githubusercontent.com/assets/172456/3198095/1d04d80c-ed54-11e3-813a-b1754d92e552.png)

split LRU 以前の図なので注意

 * mark_page_accessed
 * page_referenced
 * shrink_active_list
 * activate_page

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
        // パターンB 
		SetPageReferenced(page);
	}
}

EXPORT_SYMBOL(mark_page_accessed);
``` 