# zone_reclaim_mode

定義は下記の通り https://www.kernel.org/doc/Documentation/sysctl/vm.txt

```
zone_reclaim_mode:

Zone_reclaim_mode allows someone to set more or less aggressive approaches to
reclaim memory when a zone runs out of memory. If it is set to zero then no
zone reclaim occurs. Allocations will be satisfied from other zones / nodes
in the system.

This is value ORed together of

1	= Zone reclaim on
2	= Zone reclaim writes dirty pages out
4	= Zone reclaim swaps pages

zone_reclaim_mode is disabled by default.  For file servers or workloads
that benefit from having their data cached, zone_reclaim_mode should be
left disabled as the caching effect is likely to be more important than
data locality.

zone_reclaim may be enabled if it's known that the workload is partitioned
such that each partition fits within a NUMA node and that accessing remote
memory would cause a measurable performance reduction.  The page allocator
will then reclaim easily reusable pages (those page cache pages that are
currently not used) before allocating off node pages.

Allowing zone reclaim to write out pages stops processes that are
writing large amounts of data from dirtying pages on other nodes. Zone
reclaim will write out dirty pages if a zone fills up and so effectively
throttle the process. This may decrease the performance of a single process
since it cannot use all of system memory to buffer the outgoing writes
anymore but it preserve the memory on other nodes so that the performance
of other processes running on other nodes will not be affected.

Allowing regular swap effectively restricts allocations to the local
node unless explicitly overridden by memory policies or cpuset
configurations.
```

## mm/vmscan.c

```c
#ifdef CONFIG_NUMA
/*
 * Zone reclaim mode
 *
 * If non-zero call zone_reclaim when the number of free pages falls below
 * the watermarks.
 */
int zone_reclaim_mode __read_mostly;

#define RECLAIM_OFF 0
#define RECLAIM_ZONE (1<<0)	/* Run shrink_inactive_list on the zone */
#define RECLAIM_WRITE (1<<1)	/* Writeout pages during reclaim */
#define RECLAIM_SWAP (1<<2)	/* Swap pages out during reclaim */
```

## zone_reclaim_mode == 0

get_page_from_freelist で `== 0` かどうかの判定に使われている

```c
/*
 * get_page_from_freelist goes through the zonelist trying to allocate
 * a page.
 */
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

			mark = zone->watermark[alloc_flags & ALLOC_WMARK_MASK];
			if (zone_watermark_ok(zone, order, mark,
				    classzone_idx, alloc_flags))
				goto try_this_zone;

            /* 他の zone を見るので goto する */
			if (zone_reclaim_mode == 0)
				goto this_zone_full;

            /* 現在の zone で reclaim を試みる */
			ret = zone_reclaim(preferred_zone, zone, gfp_mask,
					   order,
					   mark, classzone_idx, alloc_flags);
			switch (ret) {
			case ZONE_RECLAIM_NOSCAN:
				/* did not scan */
				goto try_next_zone;
			case ZONE_RECLAIM_FULL:
				/* scanned but unreclaimable */
				continue;
			case ZONE_RECLAIM_SUCCESS:
				/*
				 * If we successfully reclaimed
				 * enough, allow allocations up to the
				 * min watermark (instead of stopping
				 * at "mark"). This provides some more
				 * margin against parallel
				 * allocations. Using the min
				 * watermark doesn't alter when we
				 * wakeup kswapd. It also doesn't
				 * alter the synchronous direct
				 * reclaim behavior of zone_reclaim()
				 * that will still be invoked at the
				 * next pass if we're still below the
				 * low watermark (even if kswapd isn't
				 * woken).
				 */
				mark = min_wmark_pages(zone);
				/* Fall through */
			default:
				/* did we reclaim enough */
				if (zone_watermark_ok(zone, order, mark,
						classzone_idx, alloc_flags))
					goto try_this_zone;

try_this_zone:
		page = buffered_rmqueue(preferred_zone, zone, order,
						gfp_mask, migratetype);
		if (page)
			break;
this_zone_full:
		if (NUMA_BUILD)
			zlc_mark_zone_full(zonelist, z);
try_next_zone:
		if (NUMA_BUILD && !did_zlc_setup && nr_online_nodes > 1) {
			/*
			 * we do zlc_setup after the first zone is tried but only
			 * if there are multiple nodes make it worthwhile
			 */
			allowednodes = zlc_setup(zonelist, alloc_flags);
			zlc_active = 1;
			did_zlc_setup = 1;
		}
	}

	if (unlikely(NUMA_BUILD && page == NULL && zlc_active)) {
		/* Disable zlc cache for second zonelist scan */
		zlc_active = 0;
		goto zonelist_scan;
	}
	return page;
}
```