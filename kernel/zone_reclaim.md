# zone_reclaim

zone の relcaim が起こる条件をまとめておく

watermark と free の状態               | 説明       
------------------|--------------
free > pages_high | ideal
free < pages_low  | swapout し始める
free < pages_min  | pressure to reclaim page is increased

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
			ret = zone_reclaim(preferred_zone, zone, gfp_mask,
					   order,
					   mark, classzone_idx, alloc_flags);
```

zone_reclaim から各種 shrink_ プレフィックスな関数呼び出しに繋がる

   * __zone_reclaim
     * zone_reclaim_compact
     * shrink_zones
       * shrink_list
         * shrink_active_list
         * shrink_inactive_list

これらの詳細は別件で。