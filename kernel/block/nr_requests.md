# struct request_queue nr_requests

CentOS5

## struct request_queue

 * strcut bio をまとめてデバイスドライバに渡す
 * デバイスドライバが ready な request_queue を選択する

```c
struct request_queue
{
	/*
	 * Together with queue_head for cacheline sharing
	 */
	struct list_head	queue_head;
	struct request		*last_merge;
	elevator_t		*elevator;

	/*
	 * the queue request freelist, one for reads and one for writes
	 */
	struct request_list	rq;

//...

	/*
	 * queue kobject
	 */
	struct kobject kobj;

	/*
	 * queue settings
	 */
	unsigned long		nr_requests;	/* Max # of requests */
	unsigned int		nr_congestion_on;
	unsigned int		nr_congestion_off;
	unsigned int		nr_batching;

// ...

};
```

## nr_requests の初期化

blk_queue_make_request で BLKDEV_MAX_RQ (128) で初期化される

```
/**
 * blk_queue_make_request - define an alternate make_request function for a device
 * @q:  the request queue for the device to be affected
 * @mfn: the alternate make_request function
 *
 * Description:
 *    The normal way for &struct bios to be passed to a device
 *    driver is for them to be collected into requests on a request
 *    queue, and then to allow the device driver to select requests
 *    off that queue when it is ready.  This works well for many block
 *    devices. However some block devices (typically virtual devices
 *    such as md or lvm) do not benefit from the processing on the
 *    request queue, and are served best by having the requests passed
 *    directly to them.  This can be achieved by providing a function
 *    to blk_queue_make_request().
 *
 * Caveat:
 *    The driver that does this *must* be able to deal appropriately
 *    with buffers in "highmemory". This can be accomplished by either calling
 *    __bio_kmap_atomic() to get a temporary kernel mapping, or by calling
 *    blk_queue_bounce() to create a buffer in normal memory.
 **/
void blk_queue_make_request(request_queue_t * q, make_request_fn * mfn)
{
	/*
	 * set defaults
	 */
	q->nr_requests = BLKDEV_MAX_RQ;
	blk_queue_max_phys_segments(q, MAX_PHYS_SEGMENTS);
	blk_queue_max_hw_segments(q, MAX_HW_SEGMENTS);
	blk_queue_segment_boundary(q, BLK_SEG_BOUNDARY_MASK);
	blk_queue_max_segment_size(q, MAX_SEGMENT_SIZE);
	q->make_request_fn = mfn;
	q->backing_dev_info.ra_pages = (VM_MAX_READAHEAD * 1024) / PAGE_CACHE_SIZE;
	q->backing_dev_info.state = 0;
	q->backing_dev_info.capabilities = BDI_CAP_MAP_COPY;
	blk_queue_max_sectors(q, SAFE_MAX_SECTORS);
	blk_queue_hardsect_size(q, 512);
	blk_queue_dma_alignment(q, 511);
	blk_queue_congestion_threshold(q);
	q->nr_batching = BLK_BATCH_REQ;

	q->unplug_thresh = 4;		/* hmm */
	q->unplug_delay = (3 * HZ) / 1000;	/* 3 milliseconds */
	if (q->unplug_delay == 0)
		q->unplug_delay = 1;

	INIT_WORK(&q->unplug_work, blk_unplug_work, q);

	q->unplug_timer.function = blk_unplug_timeout;
	q->unplug_timer.data = (unsigned long)q;

	/*
	 * by default assume old behaviour and bounce for any highmem page
	 */
	blk_queue_bounce_limit(q, BLK_BOUNCE_HIGH);

	blk_queue_activity_fn(q, NULL, NULL);
}

EXPORT_SYMBOL(blk_queue_make_request);
```

## /sys/block/dev*/nr_requests

```c
static struct queue_sysfs_entry queue_requests_entry = {
	.attr = {.name = "nr_requests", .mode = S_IRUGO | S_IWUSR },
	.show = queue_requests_show,
	.store = queue_requests_store,
};
```

#### read

```c
static ssize_t queue_requests_show(struct request_queue *q, char *page)
{
	return queue_var_show(q->nr_requests, (page));
}

static ssize_t
queue_var_show(unsigned int var, char *page)
{
	return sprintf(page, "%d\n", var);
}
```

#### write

```c
static ssize_t
queue_requests_store(struct request_queue *q, const char *page, size_t count)
{
	struct request_list *rl = &q->rq;
	unsigned long nr;
	int ret = queue_var_store(&nr, page, count);

    // BLKDEV_MIN_RQ = 4 より小さくならない
	if (nr < BLKDEV_MIN_RQ)
		nr = BLKDEV_MIN_RQ;

	spin_lock_irq(q->queue_lock);
	q->nr_requests = nr;

    // queue がいっぱいかどうか = congestion on か、 congestion off かどうかの閾値?
    // queue_congestion_on_threshold と queue_congestion_off_threshold で使う
	blk_queue_congestion_threshold(q);

   // READ キューが congested かどうか
	if (rl->count[READ] >= queue_congestion_on_threshold(q))
		set_queue_congested(q, READ);
	else if (rl->count[READ] < queue_congestion_off_threshold(q))
		clear_queue_congested(q, READ);

   // WRITE キューが congested かどうか
	if (rl->count[WRITE] >= queue_congestion_on_threshold(q))
		set_queue_congested(q, WRITE);
	else if (rl->count[WRITE] < queue_congestion_off_threshold(q))
		clear_queue_congested(q, WRITE);

    // 
	if (rl->count[READ] >= q->nr_requests) {
		blk_set_queue_full(q, READ);
	} else if (rl->count[READ]+1 <= q->nr_requests) {
		blk_clear_queue_full(q, READ);
		wake_up(&rl->wait[READ]);
	}

	if (rl->count[WRITE] >= q->nr_requests) {
		blk_set_queue_full(q, WRITE);
	} else if (rl->count[WRITE]+1 <= q->nr_requests) {
		blk_clear_queue_full(q, WRITE);
		wake_up(&rl->wait[WRITE]);
	}
	spin_unlock_irq(q->queue_lock);
	return ret;
}
```

nr_requests が多いと? 少ないと?

##### {set|clear}_queue_congested

 * **BDI_write_congested**, **BDI_read_congested** の状態がある
   * bdi_read_congested, bdi_write_congested で判定
     * ex. READ が congested だと、 do_page_cache_readahead で先読みされない
     * ex. WRITE が congested だと、 balance_dirty_pages_ratelimited で blk_congestion_wait が発生する
 * clear_queue_congested で待っているタスクを起床させる

```c
/*
 * A queue has just exitted congestion.  Note this in the global counter of
 * congested queues, and wake up anyone who was waiting for requests to be
 * put back.
 */
static void clear_queue_congested(request_queue_t *q, int rw)
{
	enum bdi_state bit;
	wait_queue_head_t *wqh = &congestion_wqh[rw];

	bit = (rw == WRITE) ? BDI_write_congested : BDI_read_congested;
	clear_bit(bit, &q->backing_dev_info.state);
	smp_mb__after_clear_bit();
	if (waitqueue_active(wqh))
		wake_up(wqh);
}

/*
 * A queue has just entered congestion.  Flag that in the queue's VM-visible
 * state flags and increment the global gounter of congested queues.
 */
static void set_queue_congested(request_queue_t *q, int rw)
{
	enum bdi_state bit;

	bit = (rw == WRITE) ? BDI_write_congested : BDI_read_congested;
	set_bit(bit, &q->backing_dev_info.state);
}
```

##### blk_{set|clear}_queue_full

**QUEUE_FLAG_READFULL**, **QUEUE_FLAG_WRITEFULL** の状態がある

```c
static inline void blk_set_queue_full(struct request_queue *q, int rw)
{
	if (rw == READ)
		set_bit(QUEUE_FLAG_READFULL, &q->queue_flags);
	else
		set_bit(QUEUE_FLAG_WRITEFULL, &q->queue_flags);
}

static inline void blk_clear_queue_full(struct request_queue *q, int rw)
{
	if (rw == READ)
		clear_bit(QUEUE_FLAG_READFULL, &q->queue_flags);
	else
		clear_bit(QUEUE_FLAG_WRITEFULL, &q->queue_flags);
}
```