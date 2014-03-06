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
    
    // 回収したいページの目標値
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
  
