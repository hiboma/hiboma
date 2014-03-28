
* !page->mapping && page_has_private(page)
  * journaling のページがとりうる。dirty なページ + clean buffer という状態
  * buffer を使っている場合は page->mapping に dev が来る?

## alloc_page を利用する API

 * pgd_alloc
   * __get_free_pages
   * fork(2) で mm_struct の .pgd を初期化される際に呼ばれる ( mm_alloc_pgd )
     * コケたら -ENOMEM
     * mm_struct は kmem_cache_alloc を使っていた ( allocate_mm )
   * preallocate_pmds
     * PMD を事前に __get_free_pages して割り当て
     * PAE = Page Address Extension が有効な場合のみ使う?
   * pgd_t を pgd_list に繋ぐ
 * page_fault
   * do_page_fault
     * __do_page_fault
       * handle_mm_fault
         * pud_alloc_one, pmd_alloc_one, __pte_alloc
            * get_zeroed_page
              * __get_free_pages
                 * alloc_pages ...
         * handle_pte_fault
            * do_linear_fault
              * __do_fault
                * vma->vm_ops->fault
                * vma->vm_ops->page_mkwrite
                * mem_cgroup_newpage_charge
                  * __mem_cgroup_try_charge
                    * チャージを試みる。失敗する可能性もある
                    * mem_cgroup_reclaim
                      * try_to_free_mem_cgroup_pages
                        * do_try_to_free_pages
                        * cgropu 単位で do_try_to_free_pages する
                          * cgroup の limit_in_bytes, を変えた際にも呼び出される
                            * ( mem_cgroup_resize_limit, mem_cgroup_resize_memsw_limit )
                    * mem_cgroup_handle_oom
                      * mem_cgroup_out_of_memory
                        * select_bad_process
                        * oom_kill_process
                  * __mem_cgroup_commit_charge
            * do_anonymous_page
              * mem_cgroup_newpage_charge
                * cgroup で使用量がチャージされる
                * ...
              * alloc_zeroed_user_highpage_movable
                * __alloc_zeroed_user_highpage
                  * alloc_page_vma ...
            * do_nonlinear_fault
              * pte_file PTE が _PAGE_FILE ファイルの場合
              * __do_fault
                * `__do_fault() tries to create a new page mapping.`
              * VM_FAULT_SIGBUS
                * SIGBUS のハンドリング `bad pte`
            * do_swap_page
              * fault を起こしたアドレスが anon でも file でも無い場合に swapin
              * swap されているアドレスで fault
                * lookup_swap_cache
                * swapin_readahead
                  * swapin しても page が見つからない場合は VM_FAULT_OOM で oom killer
                  * read_swap_cache_async
                    * find_get_page
                      * swapper_space からスワップキャッシュを探す
                    * __add_to_swap_cache
                    * alloc_page_vma
                      * swapin するための page を割り当て
                    * swap_readpage
                      * get_swap_bio
                      * count_vm_event(PSWPIN);
                      * submit_bio
                        * ___I/O (read)___
                    * swapcache_free
                * count_vm_event(PGMAJFAULT)
                * mem_cgroup_try_charge_swapin
                  * チャージできなかったら VM_FAULT_OOM
                * inc_mm_counter(mm, anon_rss),
                * dec_mm_counter(mm, swap_usage);
                *  mem_cgroup_commit_charge_swapin(page, ptr);
                  * ここでコミット

----

 * ページフォルトが起きた際に PUD, PMD, PTE のページが無ければ都度割り当てる
   * PGD は fork した際に mm->pgd で確保されていて必ず存在する?
     * fork の際に pgd_alloc が NULL を返したら -ENOMEM なので保証されそう
   * PUD, PMD, PTE のページを割り当てできなければ何もできないので OOM
 * cgroup でチャージされるのはここだけ?

## alloc_page 群

 * alloc_page_buffers
   * バッファ用のページ ( struct buffer_head *) を割り当てる (__getblk)
   * __bread_slow で submit_bh で bio を発行 -> wait_on_buffer(TASK_UNINTERRUPTIBLE) I/O完了を待つ
 * alloc_page_vma
   * vm_area_struct 用のページを割り当てる
   * alloc_page_interleave __alloc_pages_nodemask のいずれかを呼んで page を確保している
 * alloc_pages_current
   * NUMA な構成の場合に current プロセスのメモリポリシーに従ってメモリを配置する
   * alloc_page_interleave もしくは __alloc_pages_nodemask を呼ぶ
 * alloc_page_interleave
   * NUMA で interleave するポリシーになるように page を割り当てる
   * __alloc_pages を呼ぶ

## __alloc_pages 群

 * __alloc_pages
   * nodemask_t を NULL 指定で __alloc_pages_nodemask を呼ぶだけのラッパー
 * __alloc_pages_nodemask
   * get_page_from_freelist
     * struct zone の free_area から空き page を探す
     * buffered_rmqueue
       * order == 0 の場合
         * per_cpu_pages から空きページを取る
           * rmqueue_bulk
       * order > 1 の場合 __rmqueue で buddy アロケータから ?? する
         * __rmqueue_smallest
           * order ごとに zone->free_area リストを走査して空き struct page を探す
           * rmv_page_order
         * __rmqueue_fallback
           * 一つ上の order で空きページを探す?
     * freelist からページを確保できなかったら __alloc_pages_slowpath を呼ぶ
     * zone_reclaim で zone ごとに reclaim できるページを探す
       * __zone_reclaim
         * **vm_swappiness**
         * **shrink_zone**
           * shrink_mem_cgroup_zone
             * shrink_list
               * shrink_active_list
                 * inactive への移動
               * shrink_inactive_list
                 * shrink_page_list
                 * reclaim したページを返す
                   * pageout
                     * Dirty なページの書き出しを試みる
                     * try_to_free_buffers
                       * drop_buffers
                         * free_buffer_head
                           * kmem_cache_free
                     * mapping->a_ops->writepage
                       * shmem_writepage
                         * ページを swap に writeback
                       * ディスクベースのファイルシステムならただの writeback
                   * add_to_swap
         * **shrink_slab**
   * **__alloc_pages_slowpath**
     * wake_all_kswapd で kswapd を起床させておく
       * __GFP_NO_KSWAPD が立ってない場合だけ
     * __alloc_pages_direct_compact
       * compact_zone_order
         * compact_zone
           * migrate_pages
             * unmap_and_move
                * __unmap_and_move
                  * PageWriteback な場合 wait_on_page_writeback で I/O
                  * ...
     * **__alloc_pages_direct_reclaim**
       * try_to_free_pages
         * do_try_to_free_pages
           * wakeup_flusher_threads
             * __bdi_start_writeback
               * dirty なページを書き出すスレッドを起床させる
               * bdi_queue_work
       * get_page_from_freelist
         * ...
     * **__alloc_pages_high_priority**
       * get_page_from_freelist
         * ...
       * wait_iff_congested
         * io_schedule_timeout
     * **__alloc_pages_may_oom**
       * get_page_from_freelist ...
       * __GFP_NOFAIL が立っていたら out_of_memory で プロセスのページを reclaim
     * get_page_from_freelist もういっぺん最後に試してページを確保できないか試す
     * page 割り当てできなかったら `pr_warning("%s: page allocation failure. order:%d, mode:0x%x\n"`
       * __GFP_NOWARN が立ってない場合にだけ pr_warning 出る

## try_to 群

 * try_to_free_pages
 * try_to_free_swap
 * try_to_free_buffers
 * try_to_low
 * try_to_free_mem_cgroup_pages

----

最終的に reclaim されるページを整理

 * shrink_slab で SReclaimable なページを破棄して reclaim する
   * (ほぼ) inode_cache, dentry の slab が reclaim される
 * shrink_page_list で reclaim する
   * PageWriteback な ページを writeback して reclaim
   * PageDirty なページを pageout でディスクに書き出して reclaim
     * swapcahe, file mapped page? が reclaim される
   * unevictable なページは reclaim されない
 * out_of_memory -> oom_kill_process プロセスから reclaim
   * anon, stack, mapped file

## shrink_slab

 * slabキャッシュを破棄する
   * inode_cache, dentry が大半を占める
   * kswapd, 任意のプロセス, 割り込みコンテキスト? の alloc_page 群から呼び出される
 * node と zone

## tmpfs と swap

 * shmem_swapin

## swap API

shmem_writepage での実装から抜粋

 * get_swap_page
   * スワップキャシュを確保
   * swap_list に swap デバイスが連なっているので走査 (swap は複数登録できるので)
     * swap_list には swapon(2) で追加する
     * 空きが見つかったら nr_swap_pages++
   * scan_swap_map
   * get_swap_page で見つけたページを解放できるように面倒みるのはファイルシステムの役割?
     * tmpfs ではそうだけど、 anon な場合は?
 * add_to_swap_cache
   * page を swap cache として利用する
   * __add_to_swap_cache
     * set_page_private
       * page が swp_entry_t に使われていることを .private
     * radix_tree_insert(&swapper_space.page_tree, entry.val, page);
     * total_swapcache_pages++
     * __inc_zone_page_state(page, NR_FILE_PAGES);
 * swap_writepage
   * get_swap_bio
     * bio_alloc
       * bio_alloc_bioset
         * mempool_alloc
   * count_vm_event(PSWPOUT);
     * sar で swapout として出る統計
   * set_page_writeback して submit_bio で I/O する
 * swapcache_free
   * swap_entry_free
     * SWP_BLKDEV
     * struct gendisk disk->fops->swap_slot_free_notify
   * mem_cgroup_uncharge_swapcache

スワップキャッシュの属する struct address_space はグローバルな swapper_space

----

 * add_to_swap
   * get_swap_page
   * swapcache_free
   * add_to_swap_cache

## SEE ALSO

 * https://github.com/hiboma/hiboma/blob/master/kernel/SReclaimable.md
 * https://github.com/hiboma/hiboma/blob/master/kernel/dentry_cache.md
 * https://github.com/hiboma/hiboma/blob/master/kernel/swappiness.md
   * shrink_list 周りとごっちゃにしないように

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

