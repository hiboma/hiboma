# zone_reclaim

zone の relcaim が起こる条件をまとめておく

watermark と free の状態               | 説明       
------------------|--------------
free > pages_high | ideal
free < pages_low  | reclaim し始める
free < pages_min  | pressure to reclaim page is increased

## pages_high

get_scan_ratio ( shrink_mem_cgroup_zone で呼ばれる ) で使われている

  * file + free ページ < high watermark な際に、 anon だけをスキャンする比率にセットする

```c
 * percent[0] specifies how much pressure to put on ram/swap backed
 * memory, while percent[1] determines pressure on the file LRUs.
 */
static void get_scan_ratio(struct mem_cgroup_zone *mz, struct scan_control *sc,
					unsigned long *percent)
{

//...

		/* If we have very few page cache pages,
		   force-scan anon pages. */
		if (unlikely(file + free <= high_wmark_pages(mz->zone))) {
			percent[0] = 100; // anon
			percent[1] = 0;   // file
			return;
		}
```

#### ちょっと寄り道

swap しない or swap が無い場合は、anon なページをスキャンしない設定になる

```c
static void shrink_mem_cgroup_zone(int priority, struct mem_cgroup_zone *mz,
				   struct scan_control *sc)
{

// ...

	/* If we have no swap space, do not bother scanning anon pages. */
	if (!sc->may_swap || (nr_swap_pages <= 0)) {
		noswap = 1;
		percent[0] = 0;
		percent[1] = 100;
	} else
		get_scan_ratio(mz, sc, percent);
```


## free > pages_low の場合

 * watermark を下回ったかどうかは **zone_watermark_ok** で確認される
 * zone_watermark_ok が false なら zone_reclaim が走る
   * zone_reclaim を呼ぶのは get_page_from_freelist だけ

```c
static struct page *
get_page_from_freelist(gfp_t gfp_mask, nodemask_t *nodemask, unsigned int order,
		struct zonelist *zonelist, int high_zoneidx, int alloc_flags,
		struct zone *preferred_zone, int migratetype)
{
	struct zoneref *z;
	struct page *page = NULL;
	int classzone_idx;
	struct zone *zone;
	nodemask_t *allowednodes = NULL;/* zonelist_cache approximation */
	int zlc_active = 0;		/* set if using zonelist_cache */
	int did_zlc_setup = 0;		/* just call zlc_setup() one time */

	classzone_idx = zone_idx(preferred_zone);
zonelist_scan:
	/*
	 * Scan zonelist, looking for a zone with enough free.
	 * See also cpuset_zone_allowed() comment in kernel/cpuset.c.
	 */
	for_each_zone_zonelist_nodemask(zone, z, zonelist,
						high_zoneidx, nodemask) {
		if (NUMA_BUILD && zlc_active &&
			!zlc_zone_worth_trying(zonelist, z, allowednodes))
				continue;
		if ((alloc_flags & ALLOC_CPUSET) &&
			!cpuset_zone_allowed_softwall(zone, gfp_mask))
				goto try_next_zone;

		BUILD_BUG_ON(ALLOC_NO_WATERMARKS < NR_WMARK);
		if (!(alloc_flags & ALLOC_NO_WATERMARKS)) {
			unsigned long mark;
			int ret;

            /* alloc_flags から比較する watermark を出す */
			mark = zone->watermark[alloc_flags & ALLOC_WMARK_MASK];

            /* watermark 大丈夫なので この zone から空きページを取る */
			if (zone_watermark_ok(zone, order, mark,
				    classzone_idx, alloc_flags))
				goto try_this_zone;

            /* see http://mkosaki.blog46.fc2.com/blog-entry-936.html */
			if (zone_reclaim_mode == 0)
				goto this_zone_full;

            /* zone で reclaim を試みる */
            /* gfp_mask に __GFP_WAIT が立ってないと reclaim しない */
			ret = zone_reclaim(preferred_zone, zone, gfp_mask,
					   order,
					   mark, classzone_idx, alloc_flags);
```

zone_reclaim から各種 compaction, shrink_ プレフィックスな関数呼び出しに繋がる

   * __zone_reclaim
     * zone_reclaim_compact
       * compact_zone_order
         * 外部断片化(external fragmentation) してるページのデフラグする
         * compact_zone, migrate_page でページの中身を copy, ...
           * `sysctl_extfrag_threshold`? で compaction の度合いを決めれる
           * `/proc/sys/vm/compact_memory`?
     * shrink_zones
       * shrink_list
         * shrink_active_list
         * shrink_inactive_list

これらの詳細は別件で。

## free < pages_low の場合

> pressure to reclaim page is increased

これの意味が分からない

ソースを読むと、 min water mark を下回ると **congestion_wait** がされない状態になる

```c
static unsigned long balance_pgdat(pg_data_t *pgdat, int order)
{

//...

				/*
				 * We are still under min water mark. it mean we have
				 * GFP_ATOMIC allocation failure risk. Hurry up!
				 */
				if (!zone_watermark_ok_safe(zone, order,
					    min_wmark_pages(zone), end_zone, 0))
					has_under_min_watermark_zone = 1;

// ...

		/*
		 * OK, kswapd is getting into trouble.  Take a nap, then take
		 * another pass across the zones.
		 */
		if (total_scanned && (priority < DEF_PRIORITY - 2)) {
			if (has_under_min_watermark_zone)
                // これ何に使ってる統計? => /proc/vmstat
                // sum_vm_events, all_vm_events あたりを遡ると分かる
				count_vm_event(KSWAPD_SKIP_CONGESTION_WAIT);
			else
                // min water mark 超えてない = 通常時
				congestion_wait(BLK_RW_ASYNC, HZ/10);
		}
```

congestion_wait の中身は以下の通り

 * io_schedule_timeout に wait (HZ/10秒) を入れる?
 * ブロックデバイスが忙し過ぎる( congestion) のを防ぐため?

```c
/**
 * congestion_wait - wait for a backing_dev to become uncongested
 * @sync: SYNC or ASYNC IO
 * @timeout: timeout in jiffies
 *
 * Waits for up to @timeout jiffies for a backing_dev (any backing_dev) to exit
 * write congestion.  If no backing_devs are congested then just wait for the
 * next write to be completed.
 */
long congestion_wait(int sync, long timeout)
{
	long ret;
	DEFINE_WAIT(wait);
	wait_queue_head_t *wqh = &congestion_wqh[sync];

	prepare_to_wait(wqh, &wait, TASK_UNINTERRUPTIBLE);
	ret = io_schedule_timeout(timeout);
	finish_wait(wqh, &wait);
	return ret;
}
EXPORT_SYMBOL(congestion_wait);
```