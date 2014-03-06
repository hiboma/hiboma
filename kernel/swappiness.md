## TODO

 * shrink_list
   * shrink_active_list
     * 非 evictable なページは何もしない
     * page_referenced なページは Active リストの先頭に繋ぎ直し (rotate と呼ぶ)
     * その他は PG_Activeフラグを落として Inactive の先頭に繋ぐ
     * active -> inactive の移動では I/O発行 は伴わない
 * shrink_inactive_list
   * shrink_page_list 強い
     * 無名メモリが backing store を持つかどうかで挙動が変わる
     * PageDirty(page) であれば swapやファイルシステムに書き出す必要がある
       * pageout が vm_area_opetaions の .writepage でディスクにページを書き出し
       * swap でなくとも I/O を伴う

```c
# FREE is どこ?

enum lru_list {
	LRU_INACTIVE_ANON = LRU_BASE,
	LRU_ACTIVE_ANON   = LRU_BASE + LRU_ACTIVE,
	LRU_INACTIVE_FILE = LRU_BASE + LRU_FILE,
	LRU_ACTIVE_FILE   = LRU_BASE + LRU_FILE + LRU_ACTIVE,
	LRU_UNEVICTABLE,  // reclaim されない
	NR_LRU_LISTS
};
```

```c
/**
 * page_is_file_cache - should the page be on a file LRU or anon LRU?
 * @page: the page to test
 *
 * Returns 1 if @page is page cache page backed by a regular filesystem,
 * or 0 if @page is anonymous, tmpfs or otherwise ram or swap backed.
 * Used by functions that manipulate the LRU lists, to sort a page
 * onto the right LRU list.
 *
 * We would like to get this info without a page flag, but the state
 * needs to survive until the page is last deleted from the LRU, which
 * could be as far down as __page_cache_release.
 */
static inline int page_is_file_cache(struct page *page)
{
	return !PageSwapBacked(page);
}
```

## a verification script

```
# Inactive(file) +100MB ( PageReferenced = 0 )
$ perl -e 'print 1 x 1024 x 1024 x 100' >100mb.txt

# Inactive(file) -100MB -> Active(file) +100MB ( PageReferenced = 1 )
$ cat 100mb.txt >/dev/null

# Active -100MB
$ unlink 100mb.txt
```

```c
#if 0
#!/bin/bash
o=`basename $0`
o="__${o%.*}"
CFLAGS="-O2 -std=gnu99 -W -Wall -fPIE -D_FORTIFY_SOURCE=2"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <err.h>

/* mmap(p, '\0', mmap_size ); */

int main()
{
	ssize_t mmap_size = sysconf(_SC_PAGESIZE) * 100000;
	char *p = mmap(NULL, mmap_size, PROT_READ|PROT_WRITE,
		       MAP_PRIVATE|MAP_ANONYMOUS, 0,0);
	if (p == MAP_FAILED)
		err(1, "mmap");

	// CommmitedAS ++
	printf("just after mmap\n");
	sleep(5);

	// Active(anon) ++
	printf("first reference\n");
	for (int i = 0; i < mmap_size; i++)
		p[i] = '\0';
	sleep(5);

	// nothing happened ++
	printf("second reference\n");
	for (int i = 0; i < mmap_size; i++)
		p[i] = '\0';

	exit(0);
}
```

## swappiness

定義されているのは kernel/sysctl.c。デフォルトは 60 よ

```
/*
 * From 0 .. 100.  Higher means more swappy.
 */
int vm_swappiness = 60;
```

```c
	{
		.ctl_name	= VM_SWAPPINESS,
		.procname	= "swappiness",
		.data		= &vm_swappiness,
		.maxlen		= sizeof(vm_swappiness),
		.mode		= 0644,
		.proc_handler	= &proc_dointvec_minmax,
		.strategy	= &sysctl_intvec,
		.extra1		= &zero,        // min = 0 
		.extra2		= &one_hundred, // max = 100
	},
```

[sysctl](https://github.com/hiboma/hiboma/tree/master/kernel_module_scratch/sysctl/)

cgroup ごとに swappiness を持つ

```c
static unsigned int get_swappiness(struct mem_cgroup *memcg)
{
	struct cgroup *cgrp = memcg->css.cgroup;
	unsigned int swappiness;

	/* root ? */
	if (cgrp->parent == NULL)
		return vm_swappiness;

	spin_lock(&memcg->reclaim_param_lock);
	swappiness = memcg->swappiness;
	spin_unlock(&memcg->reclaim_param_lock);

	return swappiness;
}
```

vm_swappiness が参照されているコードを見ていく

## get_scan_ratio

```c
// anon と ファイルの LRU を見ていく積極度?
/*
 * Determine how aggressively the anon and file LRU lists should be
 * scanned.  The relative value of each set of LRU lists is determined
 * by looking at the fraction of the pages scanned we did rotate back
 * onto the active list instead of evict.
 *
 * percent[0] specifies how much pressure to put on ram/swap backed
 * memory, while percent[1] determines pressure on the file LRUs.
 */
static void get_scan_ratio(struct mem_cgroup_zone *mz, struct scan_control *sc,
					unsigned long *percent)
{
	unsigned long anon, file, free;
	unsigned long anon_prio, file_prio;
	unsigned long ap, fp;
	struct zone_reclaim_stat *reclaim_stat = get_reclaim_stat(mz);

    // Active Anon と Inactive Anon のページ数合計
	anon  = zone_nr_lru_pages(mz, LRU_ACTIVE_ANON) +
		zone_nr_lru_pages(mz, LRU_INACTIVE_ANON);

    // Active File と Inactive File のページ数合計
	file  = zone_nr_lru_pages(mz, LRU_ACTIVE_FILE) +
		zone_nr_lru_pages(mz, LRU_INACTIVE_FILE);

    // sc->target_mem_cgroup が NULL かどうか
    // cgroup内か、ホストOS全体の relcaim かどうかを見ているのだろう
	if (global_reclaim(sc)) {

        // 空きページ数
		free  = zone_page_state(mz->zone, NR_FREE_PAGES);
		/* If we have very few page cache pages,
		   force-scan anon pages. */

        // ファイルページ + 空きページ <= high_wmark_pages 以下
		if (unlikely(file + free <= high_wmark_pages(mz->zone))) {
			percent[0] = 100; // ram/swap への pressuer
			percent[1] = 0;   // file LRU への pressuern
			return;
		}
	}

	/*
	 * OK, so we have swap space and a fair amount of page cache
	 * pages.  We use the recently rotated / recently scanned
	 * ratios to determine how valuable each cache is.
	 *
	 * Because workloads change over time (and to avoid overflow)
	 * we keep these statistics as a floating average, which ends
	 * up weighing recent references more than old ones.
	 *
	 * anon in [0], file in [1]
	 */
	if (unlikely(reclaim_stat->recent_scanned[0] > anon / 4)) {
		spin_lock_irq(&mz->zone->lru_lock);
		reclaim_stat->recent_scanned[0] /= 2;
		reclaim_stat->recent_rotated[0] /= 2;
		spin_unlock_irq(&mz->zone->lru_lock);
	}

	if (unlikely(reclaim_stat->recent_scanned[1] > file / 4)) {
		spin_lock_irq(&mz->zone->lru_lock);
		reclaim_stat->recent_scanned[1] /= 2;   
		reclaim_stat->recent_rotated[1] /= 2;
		spin_unlock_irq(&mz->zone->lru_lock);
	}

	/*
	 * With swappiness at 100, anonymous and file have the same priority.
	 * This scanning priority is essentially the inverse of IO cost.
	 */
    // swappiness が小さいほどと anon_prio <<<< file_prio になる
    // swappiness が大きいと     anon_prio >>>> file_prio になる
	anon_prio = sc->swappiness;
	file_prio = 200 - sc->swappiness;

    // anon と ファイるページの pressure の量は
    // references で active でスキャンされたページ割合に反比例する
	/*
	 * The amount of pressure on anon vs file pages is inversely
	 * proportional to the fraction of recently scanned pages on
	 * each list that were recently referenced and in active use.
	 */
	ap = anon_prio * (reclaim_stat->recent_scanned[0] + 1);
	ap /= reclaim_stat->recent_rotated[0] + 1;

	fp = file_prio * (reclaim_stat->recent_scanned[1] + 1);
	fp /= reclaim_stat->recent_rotated[1] + 1;

	/* Normalize to percentages */
	percent[0] = 100 * ap / (ap + fp + 1); // ram/swap への pressure 
	percent[1] = 100 - percent[0];         // 残り
}
```

## get_reclaim_stat

get_scan_ratio が使われている箇所

```c
/*
 * This is a basic per-zone page freer.  Used by both kswapd and direct reclaim.
 */
static void shrink_mem_cgroup_zone(int priority, struct mem_cgroup_zone *mz,
				   struct scan_control *sc)
{
	unsigned long nr[NR_LRU_LISTS];
	unsigned long nr_to_scan;
	unsigned long percent[2];	/* anon @ 0; file @ 1 */
	enum lru_list l;
	unsigned long nr_reclaimed, nr_scanned;
    
    // 
	unsigned long nr_to_reclaim = sc->nr_to_reclaim;
	struct zone_reclaim_stat *reclaim_stat = get_reclaim_stat(mz);
	int noswap = 0;

restart:
    // 回収したページ数
	nr_reclaimed = 0;
    
    // スキャンしたページ数
	nr_scanned = sc->nr_scanned;

	/* If we have no swap space, do not bother scanning anon pages. */
    // swap が無ければ無名ページのスキャンをしない
    // nr_swap_pages スワップできるページ数
	if (!sc->may_swap || (nr_swap_pages <= 0)) {
		noswap = 1;
		percent[0] = 0;
		percent[1] = 100;
	} else
        // percent[0] ... ram/swap pressure  RAMのスワプのしやすさ
        // percent[1] ... file page pressure ページキャッシュの破棄のしやすさ
		get_scan_ratio(mz, sc, percent);

    //
    //  0 LRU_INACTIVE_ANON
    //  1 LRU_ACTIVE_ANON
    //  2 LRU_INACTIVE_FILE
    //  3 LRU_ACTIVE_FILE 
    //
    // を順番にイテレートする
	for_each_evictable_lru(l) {
		int file = is_file_lru(l);
		unsigned long scan;

        // ?
		scan = zone_nr_lru_pages(mz, l);
		if (priority || noswap || !sc->swappiness) {
			scan >>= priority;
			scan = (scan * percent[file]) / 100;
		}
        
        // scan する量を再調整
        // SWAP_CLUSTER_MAX = 32 を超えない値に調整されんのかな
        // anon なページを reclaim しようとすると swap するけど、 
        // 一度にでかい単位で reclaim は大変なので SWAP_CLUSTER_MAX が定められてる?
		nr[l] = nr_scan_try_batch(scan,
					  &reclaim_stat->nr_saved_scan[l]);
	}

	while (nr[LRU_INACTIVE_ANON] || nr[LRU_ACTIVE_FILE] || nr[LRU_INACTIVE_FILE]) {
		for_each_evictable_lru(l) {
			if (nr[l]) {

                // 走査するページ数
				nr_to_scan = min_t(unsigned long, nr[l], SWAP_CLUSTER_MAX);
				nr[l] -= nr_to_scan;

                // ページ回収
                // shrink_active_list, shrink_inactive_list
				nr_reclaimed += shrink_list(l, nr_to_scan, mz, sc, priority);
			}
		}
		/*
		 * On large memory systems, scan >> priority can become
		 * really large. This is fine for the starting priority;
		 * we want to put equal scanning pressure on each zone.
		 * However, if the VM has a harder time of freeing pages,
		 * with multiple processes reclaiming pages, the total
		 * freeing target can get unreasonably large.
		 */
		if (nr_reclaimed >= nr_to_reclaim && priority < DEF_PRIORITY)
			break;
	}

	sc->nr_reclaimed += nr_reclaimed;
	trace_mm_pagereclaim_shrinkzone(nr_reclaimed, priority);

	/*
	 * Even if we did not try to evict anon pages at all, we want to
	 * rebalance the anon lru active/inactive ratio.
	 */
	if (inactive_anon_is_low(mz) && nr_swap_pages > 0)
		shrink_active_list(SWAP_CLUSTER_MAX, mz, sc, priority, 0);

	/* reclaim/compaction might need reclaim to continue */
	if (should_continue_reclaim(mz, nr_reclaimed,
					sc->nr_scanned - nr_scanned,
					priority, sc))
		goto restart;

	throttle_vm_writeout(sc->gfp_mask);
}
```

## shrink_list

 * shrink_active_list
 * shrink_inactive_list

```c
static void shrink_active_list(unsigned long nr_pages,
			       struct mem_cgroup_zone *mz,
			       struct scan_control *sc,
			       int priority, int file)
{
	unsigned long nr_taken;
	unsigned long pgscanned;
	unsigned long vm_flags;
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

        // LRUからページを取り出す
		page = lru_to_page(&l_hold);
		list_del(&page->lru);

        // evictable で無いので元に戻す
		if (unlikely(!page_evictable(page, NULL))) {
			putback_lru_page(page);
			continue;
		}

		if (page_referenced(page, 0, sc->target_mem_cgroup,
				    &vm_flags)) {
            // 直近で参照されてるページ
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
			if ((vm_flags & VM_EXEC) && page_is_file_cache(page)) {
                // active リストの先頭? に戻す = rotated 
				list_add(&page->lru, &l_active);
				continue;
			}
		}

        // Active フラグを落として Inactive の先頭に繋ぐ
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

shrink_inactive_list

```c
/*
 * shrink_inactive_list() is a helper for shrink_zone().  It returns the number
 * of reclaimed pages
 */
static unsigned long shrink_inactive_list(unsigned long max_scan,
			struct mem_cgroup_zone *mz, struct scan_control *sc,
			int priority, int file)
{
	LIST_HEAD(page_list);
	struct pagevec pvec;
	unsigned long nr_scanned = 0;
	unsigned long nr_reclaimed = 0;
        unsigned long nr_dirty = 0;
        unsigned long nr_writeback = 0;
	struct zone_reclaim_stat *reclaim_stat = get_reclaim_stat(mz);
	struct zone *zone = mz->zone;
	int order = 0;

	if (!COMPACTION_BUILD)
		order = sc->order;

	while (unlikely(too_many_isolated(zone, file, sc))) {
		congestion_wait(BLK_RW_ASYNC, HZ/10);

		/* We are about to die and free our memory. Return now. */
        // SIGKILL受けてたらプロセスを止めてメモリを解放するのを優先
		if (fatal_signal_pending(current))
			return SWAP_CLUSTER_MAX;
	}

	pagevec_init(&pvec, 1);

    // ?
	lru_add_drain();
	spin_lock_irq(&zone->lru_lock);
	do {
		struct page *page;
		unsigned long nr_taken;
		unsigned long nr_scan;
		unsigned long nr_freed;
		unsigned long nr_active;
		unsigned int count[NR_LRU_LISTS] = { 0, };
		unsigned long nr_anon;
		unsigned long nr_file;

		nr_taken = isolate_pages(SWAP_CLUSTER_MAX, mz, &page_list,
					 &nr_scan, order,
					 ISOLATE_INACTIVE, 0, file);

		if (global_reclaim(sc)) {
			zone->pages_scanned += nr_scan;
            // 実行スレッドが kswapd スレッドか否か
			if (current_is_kswapd())
				__count_zone_vm_events(PGSCAN_KSWAPD, zone,
						       nr_scan);
			else
				__count_zone_vm_events(PGSCAN_DIRECT, zone,
						       nr_scan);
		}

		if (nr_taken == 0)
			goto done;

		nr_active = clear_active_flags(&page_list, count);

        // ?
		__count_vm_events(PGDEACTIVATE, nr_active);

		__mod_zone_page_state(zone, NR_ACTIVE_FILE,
						-count[LRU_ACTIVE_FILE]);
		__mod_zone_page_state(zone, NR_INACTIVE_FILE,
						-count[LRU_INACTIVE_FILE]);
		__mod_zone_page_state(zone, NR_ACTIVE_ANON,
						-count[LRU_ACTIVE_ANON]);
		__mod_zone_page_state(zone, NR_INACTIVE_ANON,
						-count[LRU_INACTIVE_ANON]);

                       
		nr_anon = count[LRU_ACTIVE_ANON] + count[LRU_INACTIVE_ANON];
		nr_file = count[LRU_ACTIVE_FILE] + count[LRU_INACTIVE_FILE];
		__mod_zone_page_state(zone, NR_ISOLATED_ANON, nr_anon);
		__mod_zone_page_state(zone, NR_ISOLATED_FILE, nr_file);

		reclaim_stat->recent_scanned[0] += count[LRU_INACTIVE_ANON];
		reclaim_stat->recent_scanned[0] += count[LRU_ACTIVE_ANON];
		reclaim_stat->recent_scanned[1] += count[LRU_INACTIVE_FILE];
		reclaim_stat->recent_scanned[1] += count[LRU_ACTIVE_FILE];

		spin_unlock_irq(&zone->lru_lock);

		nr_scanned += nr_scan;

        // shrink_page_list 強い ...
        // dirty なページの書き出しなど
		nr_freed = shrink_page_list(&page_list, sc, mz,
					PAGEOUT_IO_ASYNC, priority,
					&nr_dirty, &nr_writeback);

		nr_reclaimed += nr_freed;

		local_irq_disable();
		if (current_is_kswapd())
			__count_vm_events(KSWAPD_STEAL, nr_freed);
		__count_zone_vm_events(PGSTEAL, zone, nr_freed);

		spin_lock(&zone->lru_lock);
		/*
		 * Put back any unfreeable pages.
		 */
		while (!list_empty(&page_list)) {
			int lru;
			page = lru_to_page(&page_list);
			VM_BUG_ON(PageLRU(page));
			list_del(&page->lru);

            // 非 evictable は元のリストに戻すよ
			if (unlikely(!page_evictable(page, NULL))) {
				spin_unlock_irq(&zone->lru_lock);
				putback_lru_page(page);
				spin_lock_irq(&zone->lru_lock);
				continue;
			}

			SetPageLRU(page);
			lru = page_lru(page);
			add_page_to_lru_list(zone, page, lru);

			if (is_active_lru(lru)) {
				int file = is_file_lru(lru);
				int numpages = hpage_nr_pages(page);
				reclaim_stat->recent_rotated[file] += numpages;
			}

			if (!pagevec_add(&pvec, page)) {
				spin_unlock_irq(&zone->lru_lock);
				__pagevec_release(&pvec);
				spin_lock_irq(&zone->lru_lock);
			}
		}
		__mod_zone_page_state(zone, NR_ISOLATED_ANON, -nr_anon);
		__mod_zone_page_state(zone, NR_ISOLATED_FILE, -nr_file);

		/*
		 * If reclaim is isolating dirty pages under writeback, it implies
		 * that the long-lived page allocation rate is exceeding the page
		 * laundering rate. Either the global limits are not being effective
		 * at throttling processes due to the page distribution throughout
		 * zones or there is heavy usage of a slow backing device. The
		 * only option is to throttle from reclaim context which is not ideal
		 * as there is no guarantee the dirtying process is throttled in the
		 * same way balance_dirty_pages() manages.
		 *
		 * This scales the number of dirty pages that must be under writeback
		 * before throttling depending on priority. It is a simple backoff
		 * function that has the most effect in the range DEF_PRIORITY to
		 * DEF_PRIORITY-2 which is the priority reclaim is considered to be
		 * in trouble and reclaim is considered to be in trouble.
		 *
		 * DEF_PRIORITY   100% isolated pages must be PageWriteback to throttle
		 * DEF_PRIORITY-1  50% must be PageWriteback
		 * DEF_PRIORITY-2  25% must be PageWriteback, kswapd in trouble
		 * ...
		 * DEF_PRIORITY-6 For SWAP_CLUSTER_MAX isolated pages, throttle if any
		 *                     isolated page is PageWriteback
		 */
		if (nr_writeback && nr_writeback >=
			(nr_taken >> (DEF_PRIORITY-priority))) {
			spin_unlock_irq(&zone->lru_lock);
			wait_iff_congested(zone, BLK_RW_ASYNC, HZ/10);
			spin_lock_irq(&zone->lru_lock);
		}
  	} while (nr_scanned < max_scan);

done:
	spin_unlock_irq(&zone->lru_lock);
	pagevec_release(&pvec);
	trace_mm_pagereclaim_shrinkinactive(nr_scanned, file, 
				nr_reclaimed, priority);
	return nr_reclaimed;
```

shrink_list -> shrink_inactive_list -> **shrink_page_list**

```c
/*
 * shrink_page_list() returns the number of reclaimed pages
 */
static unsigned long shrink_page_list(struct list_head *page_list,
					struct scan_control *sc,
					struct mem_cgroup_zone *mz,
					enum pageout_io sync_writeback,
					int priority,
					unsigned long *ret_nr_dirty,
					unsigned long *ret_nr_writeback)
{
	LIST_HEAD(ret_pages);
	struct pagevec freed_pvec;
	int pgactivate = 0;
	unsigned long nr_dirty = 0;
	unsigned long nr_congested = 0;
	unsigned long nr_reclaimed = 0;
	unsigned long nr_writeback = 0;

	cond_resched();

	pagevec_init(&freed_pvec, 1);
	while (!list_empty(page_list)) {
		enum page_references references;
		struct address_space *mapping;
		struct page *page;
		int may_enter_fs;

		cond_resched();

		page = lru_to_page(page_list);
		list_del(&page->lru);

		if (!trylock_page(page))
			goto keep;

		VM_BUG_ON(PageActive(page));
		VM_BUG_ON(page_zone(page) != mz->zone);

		sc->nr_scanned++;

		if (unlikely(!page_evictable(page, NULL)))
			goto cull_mlocked;

		if (!sc->may_unmap && page_mapped(page))
			goto keep_locked;

		/* Double the slab pressure for mapped and swapcache pages */
		if (page_mapped(page) || PageSwapCache(page))
			sc->nr_scanned++;

		may_enter_fs = (sc->gfp_mask & __GFP_FS) ||
			(PageSwapCache(page) && (sc->gfp_mask & __GFP_IO));

         // dirty なページ でディスクに書き出し中
		if (PageWriteback(page)) {
			nr_writeback++;
			/*
			 * Synchronous reclaim cannot queue pages for
			 * writeback due to the possibility of stack overflow
			 * but if it encounters a page under writeback, wait
			 * for the IO to complete.
			 */
            // dirty なページの書き戻し
            // anon, file に限らず dirty ならファイルに書き出しが必要
            // TASK_UNINTERRUPTIBLE ?
			if (sync_writeback == PAGEOUT_IO_SYNC && may_enter_fs)
				wait_on_page_writeback(page);
			else
				goto keep_locked;
		}

		references = page_check_references(page, mz, sc);
		switch (references) {
		case PAGEREF_ACTIVATE:
			goto activate_locked;
		case PAGEREF_KEEP:
			goto keep_locked;
		case PAGEREF_RECLAIM:
		case PAGEREF_RECLAIM_CLEAN:
			; /* try to reclaim the page below */
		}

		/*
		 * Anonymous process memory has backing store?
		 * Try to allocate it some swap space here.
		 */
		if (PageAnon(page) && !PageSwapCache(page)) {
			if (!(sc->gfp_mask & __GFP_IO))
				goto keep_locked;
			if (!add_to_swap(page))
				goto activate_locked;
			may_enter_fs = 1;
		}

		mapping = page_mapping(page);

		/*
		 * The page is mapped into the page tables of one or more
		 * processes. Try to unmap it here.
		 */
        // ページテーブルにマップされている
		if (page_mapped(page) && mapping) {
			switch (try_to_unmap(page, TTU_UNMAP)) {
			case SWAP_FAIL:
				goto activate_locked;
			case SWAP_AGAIN:
				goto keep_locked;
			case SWAP_MLOCK:
				goto cull_mlocked;
			case SWAP_SUCCESS:
				; /* try to free the page below */
			}
		}
        
        // dirty なページ
		if (PageDirty(page)) {
			nr_dirty++;

			/*
			 * Only kswapd can writeback filesystem pages to
			 * avoid risk of stack overflow but do not writeback
			 * unless under significant pressure.
			 */
             // ページキャッシュ (swapbackendで無い=ファイル,tmpfs,ramfsのページ) で
             // kswapでない???
			if (page_is_file_cache(page) &&					(!current_is_kswapd() || priority >= DEF_PRIORITY - 2)) {
				/*
				 * Immediately reclaim when written back.
				 * Similar in principal to deactivate_page()
				 * except we already have the page isolated
				 * and know it's dirty
				 */
                // 
				SetPageReclaim(page);

				goto keep_locked;
			}

			if (references == PAGEREF_RECLAIM_CLEAN)
				goto keep_locked;
			if (!may_enter_fs)
				goto keep_locked;
			if (!sc->may_writepage)
				goto keep_locked;

			/* Page is dirty, try to write it out here */
            // dirty なページの書き出しだー!!!
            // vm_area_operations の .writepage が呼ばれる
			switch (pageout(page, mapping, sync_writeback)) {
			case PAGE_KEEP:
				nr_congested++;
				goto keep_locked;
			case PAGE_ACTIVATE:
				goto activate_locked;
			case PAGE_SUCCESS:
				if (PageWriteback(page) || PageDirty(page))
					goto keep;
				/*
				 * A synchronous write - probably a ramdisk.  Go
				 * ahead and try to reclaim the page.
				 */
				if (!trylock_page(page))
					goto keep;
				if (PageDirty(page) || PageWriteback(page))
					goto keep_locked;
				mapping = page_mapping(page);
			case PAGE_CLEAN:
				; /* try to free the page below */
			}
		}

		/*
		 * If the page has buffers, try to free the buffer mappings
		 * associated with this page. If we succeed we try to free
		 * the page as well.
		 *
		 * We do this even if the page is PageDirty().
		 * try_to_release_page() does not perform I/O, but it is
		 * possible for a page to have PageDirty set, but it is actually
		 * clean (all its buffers are clean).  This happens if the
		 * buffers were written out directly, with submit_bh(). ext3
		 * will do this, as well as the blockdev mapping.
		 * try_to_release_page() will discover that cleanness and will
		 * drop the buffers and mark the page clean - it can be freed.
		 *
		 * Rarely, pages can have buffers and no ->mapping.  These are
		 * the pages which were not successfully invalidated in
		 * truncate_complete_page().  We try to drop those buffers here
		 * and if that worked, and the page is no longer mapped into
		 * process address space (page_count == 1) it can be freed.
		 * Otherwise, leave the page on the LRU so it is swappable.
		 */
         // バッファーの場合
		if (page_has_private(page)) {
			if (!try_to_release_page(page, sc->gfp_mask))
				goto activate_locked;
			if (!mapping && page_count(page) == 1) {
				unlock_page(page);
                // page->_count == 0 にする
				if (put_page_testzero(page))
                    // 回収された
					goto free_it;
				else {
					/*
					 * rare race with speculative reference.
					 * the speculative reference will free
					 * this page shortly, so we may
					 * increment nr_reclaimed here (and
					 * leave it off the LRU).
					 */
                    // 回収された
					nr_reclaimed++;
					continue;
				}
			}
		}

		if (!mapping || !__remove_mapping(mapping, page))
			goto keep_locked;

		/*
		 * At this point, we have no other references and there is
		 * no way to pick any more up (removed from LRU, removed
		 * from pagecache). Can use non-atomic bitops now (and
		 * we obviously don't have to worry about waking up a process
		 * waiting on the page lock, because there are no references.
		 */
		__clear_page_locked(page);
free_it:
		nr_reclaimed++;
		if (!pagevec_add(&freed_pvec, page)) {
			__pagevec_free(&freed_pvec);
			pagevec_reinit(&freed_pvec);
		}
		continue;

cull_mlocked:
		if (PageSwapCache(page))
			try_to_free_swap(page);
		unlock_page(page);
		putback_lru_page(page);
		continue;

activate_locked:
		/* Not a candidate for swapping, so reclaim swap space. */
		if (PageSwapCache(page) && vm_swap_full())
			try_to_free_swap(page);
		VM_BUG_ON(PageActive(page));
		SetPageActive(page);
		pgactivate++;
keep_locked:
		unlock_page(page);
keep:
		list_add(&page->lru, &ret_pages);
		VM_BUG_ON(PageLRU(page) || PageUnevictable(page));
	}

	/*
	 * Tag a zone as congested if all the dirty pages encountered were
	 * backed by a congested BDI. In this case, reclaimers should just
	 * back off and wait for congestion to clear because further reclaim
	 * will encounter the same problem
	 */
	if (nr_dirty && nr_dirty == nr_congested && global_reclaim(sc))
		zone_set_flag(mz->zone, ZONE_CONGESTED);

	list_splice(&ret_pages, page_list);
	if (pagevec_count(&freed_pvec))
		__pagevec_free(&freed_pvec);
	count_vm_events(PGACTIVATE, pgactivate);
	trace_mm_pagereclaim_free(nr_reclaimed);
        *ret_nr_dirty += nr_dirty;
        *ret_nr_writeback += nr_writeback;
	return nr_reclaimed;
}
```