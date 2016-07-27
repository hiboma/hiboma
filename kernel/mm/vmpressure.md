# vmpressure

## memory.pressure_level

refs https://lwn.net/Articles/544652/

#### low

```
The "low" level means that the system is reclaiming memory for new
allocations. Monitoring this reclaiming activity might be useful for
maintaining cache level. Upon notification, the program (typically
"Activity Manager") might analyze vmstat and act in advance (i.e.
prematurely shutdown unimportant services).
```

#### medium

```
The "medium" level means that the system is experiencing medium memory
pressure, the system might be making swap, paging out active file caches,
etc. Upon this event applications may decide to further analyze
vmstat/zoneinfo/memcg or internal memory usage statistics and free any
resources that can be easily reconstructed or re-read from a disk.
```

#### critical

```
The "critical" level means that the system is actively thrashing, it is
about to out of memory (OOM) or even the in-kernel OOM killer is on its
way to trigger. Applications should do whatever they can to help the
system. It might be too late to consult with vmstat or any other
statistics, so it's advisable to take an immediate action.
```

## definition - struct vmpressure

```c
struct vmpressure {
	unsigned long scanned;
	unsigned long reclaimed;
	/* The lock is used to keep the scanned/reclaimed above in sync. */
	struct mutex sr_lock;

	/* The list of vmpressure_event structs. */
	struct list_head events;
	/* Have to grab the lock on events traversal or modifications. */
	struct mutex events_lock;

	struct work_struct work;
};
```

## definition - vmpressure()

 * schedule_work(&vmpr->work);
    
```c
/**
 * vmpressure() - Account memory pressure through scanned/reclaimed ratio
 * @gfp:	reclaimer's gfp mask
 * @memcg:	cgroup memory controller handle
 * @scanned:	number of pages scanned
 * @reclaimed:	number of pages reclaimed
 *
 * This function should be called from the vmscan reclaim path to account
 * "instantaneous" memory pressure (scanned/reclaimed ratio). The raw
 * pressure index is then further refined and averaged over time.
 *
 * This function does not return any value.
 */
void vmpressure(gfp_t gfp, struct mem_cgroup *memcg,
		unsigned long scanned, unsigned long reclaimed)
{

    // /* Some nice accessors for the vmpressure. */
    // struct vmpressure *memcg_to_vmpressure(struct mem_cgroup *memcg)
    // {
    // 	if (!memcg)
    // 		memcg = root_mem_cgroup;
    // 	return &memcg->vmpressure;
    // }
	struct vmpressure *vmpr = memcg_to_vmpressure(memcg);

	/*
	 * Here we only want to account pressure that userland is able to
	 * help us with. For example, suppose that DMA zone is under
	 * pressure; if we notify userland about that kind of pressure,
	 * then it will be mostly a waste as it will trigger unnecessary
	 * freeing of memory by userland (since userland is more likely to
	 * have HIGHMEM/MOVABLE pages instead of the DMA fallback). That
	 * is why we include only movable, highmem and FS/IO pages.
	 * Indirect reclaim (kswapd) sets sc->gfp_mask to GFP_KERNEL, so
	 * we account it too.
	 */
	if (!(gfp & (__GFP_HIGHMEM | __GFP_MOVABLE | __GFP_IO | __GFP_FS)))
		return;

	/*
	 * If we got here with no pages scanned, then that is an indicator
	 * that reclaimer was unable to find any shrinkable LRUs at the
	 * current scanning depth. But it does not mean that we should
	 * report the critical pressure, yet. If the scanning priority
	 * (scanning depth) goes too high (deep), we will be notified
	 * through vmpressure_prio(). But so far, keep calm.
	 */
	if (!scanned)
		return;

	mutex_lock(&vmpr->sr_lock);
	vmpr->scanned += scanned;
	vmpr->reclaimed += reclaimed;
	scanned = vmpr->scanned;
	mutex_unlock(&vmpr->sr_lock);

	if (scanned < vmpressure_win || work_pending(&vmpr->work))
		return;
	schedule_work(&vmpr->work);
}
```

## vmpressure_work_fn

```c
/**
 * vmpressure_init() - Initialize vmpressure control structure
 * @vmpr:	Structure to be initialized
 *
 * This function should be called on every allocated vmpressure structure
 * before any usage.
 */
void vmpressure_init(struct vmpressure *vmpr)
{
	mutex_init(&vmpr->sr_lock);
	mutex_init(&vmpr->events_lock);
	INIT_LIST_HEAD(&vmpr->events);
	INIT_WORK(&vmpr->work, vmpressure_work_fn);
}
```

```c
static void vmpressure_work_fn(struct work_struct *work)
{
	struct vmpressure *vmpr = work_to_vmpressure(work);
	unsigned long scanned;
	unsigned long reclaimed;

	/*
	 * Several contexts might be calling vmpressure(), so it is
	 * possible that the work was rescheduled again before the old
	 * work context cleared the counters. In that case we will run
	 * just after the old work returns, but then scanned might be zero
	 * here. No need for any locks here since we don't care if
	 * vmpr->reclaimed is in sync.
	 */
	if (!vmpr->scanned)
		return;

	mutex_lock(&vmpr->sr_lock);
	scanned = vmpr->scanned;
	reclaimed = vmpr->reclaimed;
	vmpr->scanned = 0;
	vmpr->reclaimed = 0;
	mutex_unlock(&vmpr->sr_lock);

	do {
		if (vmpressure_event(vmpr, scanned, reclaimed))
			break;
		/*
		 * If not handled, propagate the event upward into the
		 * hierarchy.
		 */
	} while ((vmpr = vmpressure_parent(vmpr)));
}
```

```c
static bool vmpressure_event(struct vmpressure *vmpr,
			     unsigned long scanned, unsigned long reclaimed)
{
	struct vmpressure_event *ev;
	enum vmpressure_levels level;
	bool signalled = false;

	level = vmpressure_calc_level(scanned, reclaimed);

	mutex_lock(&vmpr->events_lock);

    // notify to userland by eventfd
    
    // enum vmpressure_levels {
    // 	VMPRESSURE_LOW = 0,
    // 	VMPRESSURE_MEDIUM,
    // 	VMPRESSURE_CRITICAL,
    // 	VMPRESSURE_NUM_LEVELS,
    // };
    // 
    // static const char * const vmpressure_str_levels[] = {
    // 	[VMPRESSURE_LOW] = "low",
    // 	[VMPRESSURE_MEDIUM] = "medium",
    // 	[VMPRESSURE_CRITICAL] = "critical",
    // };
    //     
    list_for_each_entry(ev, &vmpr->events, node) {
		if (level >= ev->level) {
			eventfd_signal(ev->efd, 1);
			signalled = true;
		}
	}

	mutex_unlock(&vmpr->events_lock);

	return signalled;
}
```

```c
static enum vmpressure_levels vmpressure_calc_level(unsigned long scanned,
						    unsigned long reclaimed)
{
	unsigned long scale = scanned + reclaimed;
	unsigned long pressure;

	/*
	 * We calculate the ratio (in percents) of how many pages were
	 * scanned vs. reclaimed in a given time frame (window). Note that
	 * time is in VM reclaimer's "ticks", i.e. number of pages
	 * scanned. This makes it possible to set desired reaction time
	 * and serves as a ratelimit.
	 */
	pressure = scale - (reclaimed * scale / scanned);
	pressure = pressure * 100 / scale;

	pr_debug("%s: %3lu  (s: %lu  r: %lu)\n", __func__, pressure,
		 scanned, reclaimed);

	return vmpressure_level(pressure);
}
```

## Where is vmpressure_win called?

```c
static void shrink_zone(struct zone *zone, struct scan_control *sc)
{
	unsigned long nr_reclaimed, nr_scanned;

	do {
		struct mem_cgroup *root = sc->target_mem_cgroup;
		struct mem_cgroup_reclaim_cookie reclaim = {
			.zone = zone,
			.priority = sc->priority,
		};
		struct mem_cgroup *memcg;

		nr_reclaimed = sc->nr_reclaimed;
		nr_scanned = sc->nr_scanned;

		memcg = mem_cgroup_iter(root, NULL, &reclaim);
		do {
			struct lruvec *lruvec;

			lruvec = mem_cgroup_zone_lruvec(zone, memcg);

            // do reclaim
			shrink_lruvec(lruvec, sc);

			/*
			 * Direct reclaim and kswapd have to scan all memory
			 * cgroups to fulfill the overall scan target for the
			 * zone.
			 *
			 * Limit reclaim, on the other hand, only cares about
			 * nr_to_reclaim pages to be reclaimed and it will
			 * retry with decreasing priority if one round over the
			 * whole hierarchy is not sufficient.
			 */
			if (!global_reclaim(sc) &&
					sc->nr_reclaimed >= sc->nr_to_reclaim) {
				mem_cgroup_iter_break(root, memcg);
				break;
			}
			memcg = mem_cgroup_iter(root, memcg, &reclaim);
		} while (memcg);

        // vmpressure_work_fn
        // eventfd
		vmpressure(sc->gfp_mask, sc->target_mem_cgroup,
			   sc->nr_scanned - nr_scanned,
			   sc->nr_reclaimed - nr_reclaimed);

	} while (should_continue_reclaim(zone, sc->nr_reclaimed - nr_reclaimed,
					 sc->nr_scanned - nr_scanned, sc));
}
```
