## shrink_slab

 * slabキャッシュを破棄する
   * inode_cache, dentry が大半を占める
   * kswapd, 任意のプロセス, 割り込みコンテキスト? の alloc_page 群から呼び出される

## SEE ALSO

 * https://github.com/hiboma/hiboma/blob/master/kernel/SReclaimable.md
 * https://github.com/hiboma/hiboma/blob/master/kernel/dentry_cache.md
 * https://github.com/hiboma/hiboma/blob/master/kernel/swappiness.md
   * shrink_list 周りとごっちゃにしないように

## alloc_page 群

 * alloc_page_buffers
   * バッファ用のページを割り当てる
 * alloc_page_vma
   * vm_area_struct 用のページを割り当てる
 * alloc_pages_current
   * NUMA な構成の場合に current プロセスのメモリポリシーに従ってメモリを配置する
   * alloc_page_interleave もしくは __alloc_pages_nodemask を呼ぶ
 * alloc_page_interleave
   * NUMA で interleave するポリシーになるように page を割り当てる
   * __alloc_pages を呼ぶ
 * __alloc_pages
   * __alloc_pages_nodemask を呼ぶ
 * __alloc_pages_nodemask
   * get_page_from_freelist で freelist からページを確保できなかったら __alloc_pages_slowpath を呼ぶ
     * zone_reclaim
       * __zone_reclaim
         * shrink_slab

   * **__alloc_pages_slowpath**
     * __alloc_pages_direct_compact
     * __alloc_pages_direct_reclaim
       * try_to_free_pages
         * do_try_to_free_pages
           * wakeup_flusher_threads
             * __bdi_start_writeback
               * dirty なページを書き出すスレッドを起床させる
               * bdi_queue_work
     * __alloc_pages_high_priority
     * __alloc_pages_may_oom
     * wake_all_kswapd で kswapd を起床させておく
       * __GFP_NO_KSWAPD が立ってない場合だけ
     * get_page_from_freelist
       * もういっぺん最後に試してみる
       * zone_reclaim
         * __zone_reclaim
           * shrink_slab
     * page 割り当てできなかったら `pr_warning("%s: page allocation failure. order:%d, mode:0x%x\n"`

## try_to 群

 * try_to_free_pages
 * try_to_free_swap
 * try_to_free_buffers

buffer 用のページを割り当てる際にも shrink_slab を呼ぶケースがある

```
alloc_page_buffers
free_more_memory
try_to_release_page
do_try_to_free_pages
 ...
```

## __zone_reclaim

 * NR_SLAB_RECLAIMABLE の数値をスキャンすべきエントリ数に指定して shrink_slab を投げる
```c
static int __zone_reclaim(struct zone *zone, gfp_t gfp_mask, unsigned int order)

//...

	slab_reclaimable = zone_page_state(zone, NR_SLAB_RECLAIMABLE);
	if (slab_reclaimable > zone->min_slab_pages) {
		/*
		 * shrink_slab() does not currently allow us to determine how
		 * many pages were freed in this zone. So we take the current
		 * number of slab pages and shake the slab until it is reduced
		 * by the same nr_pages that we used for reclaiming unmapped
		 * pages.
		 *
		 * Note that shrink_slab will free memory on all zones and may
		 * take a long time.
		 */
		while (shrink_slab(sc.nr_scanned, gfp_mask, order) &&
			zone_page_state(zone, NR_SLAB_RECLAIMABLE) >
				slab_reclaimable - nr_pages)
			;

		/*
		 * Update nr_reclaimed by the number of slab pages we
		 * reclaimed from this zone.
		 */
		sc.nr_reclaimed += slab_reclaimable -
			zone_page_state(zone, NR_SLAB_RECLAIMABLE);
	}
```
## kswapd

__alloc_pages_slowpath -> wake_all_kswapd -> wakeup_kswapd で起床する

 * kswapd
 * balance_pgdat
   * free_pges <= high_wmark_pages(zone).
     * highmem -> normal -> DMA の順番でノード

