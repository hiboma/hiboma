# __bread

CentOS5

```
struct buffer_head * __bread(struct block_device *bdev, sector_t block, int size)
  struct buffer_head *__getblk(struct block_device *bdev, sector_t block, int size)
    struct buffer_head * __find_get_block(struct block_device *bdev, sector_t block, int size)
    static struct buffer_head * __find_get_block_slow(struct block_device *bdev, sector_t block)
  static struct buffer_head *__bread_slow(struct buffer_head *bh)
    int submit_bh(int rw, struct buffer_head * bh)
      void submit_bio(int rw, struct bio *bio)
      void generic_make_request(struct bio *bio)
        static int __make_request(request_queue_t *q, struct bio *bio)
        static inline void add_request(request_queue_t * q, struct request * req)
        void __elv_add_request(request_queue_t *q, struct request *rq, int where, int plug)
        void elv_insert(request_queue_t *q, struct request *rq, int where)
        if (sync)
            void __generic_unplug_device(request_queue_t *q)
```

### __bread

 * ブロックを read して、 buffer_head を返す
 * buffer_head をどうやって獲得するのか

```c
/**
 *  __bread() - reads a specified block and returns the bh
 *  @bdev: the block_device to read from
 *  @block: number of block
 *  @size: size (in bytes) to read
 * 
 *  Reads a specified block, and returns buffer head that contains it.
 *  It returns NULL if the block was unreadable.
 */
struct buffer_head *
__bread(struct block_device *bdev, sector_t block, int size)
{
	struct buffer_head *bh = __getblk(bdev, block, size);

	if (likely(bh) && !buffer_uptodate(bh))
		bh = __bread_slow(bh);
	return bh;
}
EXPORT_SYMBOL(__bread);
```

## __getblk

 * buffer_head を cpu var から探すパス
 * buffer_head を address_space の pagecahce から探すパス

```c
/*
 * __getblk will locate (and, if necessary, create) the buffer_head
 * which corresponds to the passed block_device, block and size. The
 * returned buffer has its reference count incremented.
 *
 * __getblk() cannot fail - it just keeps trying.  If you pass it an
 * illegal block number, __getblk() will happily return a buffer_head
 * which represents the non-existent block.  Very weird.
 *
 * __getblk() will lock up the machine if grow_dev_page's try_to_free_buffers()
 * attempt is failing.  FIXME, perhaps?
 */
struct buffer_head *
__getblk(struct block_device *bdev, sector_t block, int size)
{
   // cpu var から探す
   // 他のコアに干渉しないので高速
	struct buffer_head *bh = __find_get_block(bdev, block, size);

	might_sleep();
	if (bh == NULL)
       // free_more_memory を呼び出しうるので _slow がつく
		bh = __getblk_slow(bdev, block, size);
	return bh;
}
EXPORT_SYMBOL(__getblk);
```

##### _find_get_block

```c
/*
 * Perform a pagecache lookup for the matching buffer.  If it's there, refresh
 * it in the LRU and mark it as accessed.  If it is not present then return
 * NULL
 */
struct buffer_head *
__find_get_block(struct block_device *bdev, sector_t block, int size)
{
	struct buffer_head *bh = lookup_bh_lru(bdev, block, size);

	if (bh == NULL) {
        // inode にマッピングされた page ? から探す
        // 他 CPU とロックで競合する可能性ある
		bh = __find_get_block_slow(bdev, block);
		if (bh)
			bh_lru_install(bh);
	}
	if (bh)
		touch_buffer(bh);
	return bh;
}
EXPORT_SYMBOL(__find_get_block);
```

#### __find_get_block_slow

```c
/*
 * Various filesystems appear to want __find_get_block to be non-blocking.
 * But it's the page lock which protects the buffers.  To get around this,
 * we get exclusion from try_to_free_buffers with the blockdev mapping's
 * private_lock.
 *
 * Hack idea: for the blockdev mapping, i_bufferlist_lock contention
 * may be quite high.  This code could TryLock the page, and if that
 * succeeds, there is no need to take private_lock. (But if
 * private_lock is contended then so is mapping->tree_lock).
 */
static struct buffer_head *
__find_get_block_slow(struct block_device *bdev, sector_t block)
{
    // ブロックデバイスの inode を出す
	struct inode *bd_inode = bdev->bd_inode;
	struct address_space *bd_mapping = bd_inode->i_mapping;
	struct buffer_head *ret = NULL;
	pgoff_t index;
	struct buffer_head *bh;
	struct buffer_head *head;
	struct page *page;
	int all_mapped = 1;

    // ブロックデバイスにマッピングされた address_space から対象の page を出す
	index = block >> (PAGE_CACHE_SHIFT - bd_inode->i_blkbits);
	page = find_get_page(bd_mapping, index);
	if (!page)
		goto out;

    // address_space をスピンロック。ブロックデバイスが対象なので粒度大きそう
	spin_lock(&bd_mapping->private_lock);
	if (!page_has_buffers(page))
		goto out_unlock;

    // page から buffer_head を出す
	head = page_buffers(page);
	bh = head;

    // ???
	do {
		if (bh->b_blocknr == block) {
			ret = bh;
			get_bh(bh);
			goto out_unlock;
		}
		if (!buffer_mapped(bh))
			all_mapped = 0;
		bh = bh->b_this_page;
	} while (bh != head);

	/* we might be here because some of the buffers on this page are
	 * not mapped.  This is due to various races between
	 * file io on the block device and getblk.  It gets dealt with
	 * elsewhere, don't buffer_error if we had some unmapped buffers
	 */
	if (all_mapped) {
		printk("__find_get_block_slow() failed. "
			"block=%llu, b_blocknr=%llu\n",
			(unsigned long long)block,
			(unsigned long long)bh->b_blocknr);
		printk("b_state=0x%08lx, b_size=%zu\n",
			bh->b_state, bh->b_size);
		printk("device blocksize: %d\n", 1 << bd_inode->i_blkbits);
	}
out_unlock:
	spin_unlock(&bd_mapping->private_lock);
	page_cache_release(page);
out:
	return ret;
}
```

##### __getblk_slow

 * buffer_head を獲得できなければ、 free_more_memory で空きを確保する

```c
static struct buffer_head *
__getblk_slow(struct block_device *bdev, sector_t block, int size)
{
	/* Size must be multiple of hard sectorsize */
	if (unlikely(size & (bdev_hardsect_size(bdev)-1) ||
			(size < 512 || size > PAGE_SIZE))) {
		printk(KERN_ERR "getblk(): invalid block size %d requested\n",
					size);
		printk(KERN_ERR "hardsect size: %d\n",
					bdev_hardsect_size(bdev));

		dump_stack();
		return NULL;
	}

	for (;;) {
		struct buffer_head * bh;

		bh = __find_get_block(bdev, block, size);
		if (bh)
			return bh;

		if (!grow_buffers(bdev, block, size))
            // try_to_free_pages 呼び出しに繋がる !!
            // wakeup_pdflush で pdflush 呼び出し
			free_more_memory();
	}
}
```

__getblk_slow で free_more_memory に繋がるあたり、面白い

### __bread_slow

 * submit_bh で BIO 層でリクエストを出す
 * wait_on_buffer で TASK_UNINTERRUPTIBLE で待ち

```c
static struct buffer_head *__bread_slow(struct buffer_head *bh)
{
	lock_buffer(bh);
	if (buffer_uptodate(bh)) {
		unlock_buffer(bh);
		return bh;
	} else {
		get_bh(bh);
        // IO終了後のコールバック
		bh->b_end_io = end_buffer_read_sync;
        // bh -> BIO -> request / IOスケジューラ -> デバイスドライバ と下ってデバイスに要求を出す
		submit_bh(READ, bh);
        // TASK_UNINTERRUPTIBLE でのブロック
		wait_on_buffer(bh);
		if (buffer_uptodate(bh))
			return bh;
	}
	brelse(bh);
	return NULL;
}
```

### submit_bh

キャッシュ層 -> 汎用ブロック層

 * buffer_head -> bio への橋渡し層
 * submit_bio で BIO をブロックデバイスレイヤに出す

```c
int submit_bh(int rw, struct buffer_head * bh)
{
	struct bio *bio;
	int ret = 0;

	BUG_ON(!buffer_locked(bh));
	BUG_ON(!buffer_mapped(bh));
	BUG_ON(!bh->b_end_io);

	if (buffer_ordered(bh) && (rw == WRITE))
		rw = WRITE_BARRIER;

	/*
	 * Only clear out a write error when rewriting, should this
	 * include WRITE_SYNC as well?
	 */
	if (test_set_buffer_req(bh) && (rw == WRITE || rw == WRITE_BARRIER))
		clear_buffer_write_io_error(bh);

	/*
	 * from here on down, it's all bio -- do the initial mapping,
	 * submit_bio -> generic_make_request may further map this bio around
	 */
	bio = bio_alloc(GFP_NOIO, 1);

   // セクタ数
	bio->bi_sector = bh->b_blocknr * (bh->b_size >> 9);
    // デバイス
	bio->bi_bdev = bh->b_bdev;
    // buffer_head が mapping された struct page
	bio->bi_io_vec[0].bv_page = bh->b_page;
    // ???
	bio->bi_io_vec[0].bv_len = bh->b_size;
    // ページサイズでのオフセット
	bio->bi_io_vec[0].bv_offset = bh_offset(bh);

   // bio->bi_io_vec の数
	bio->bi_vcnt = 1;
	bio->bi_idx = 0;
	bio->bi_size = bh->b_size;

	bio->bi_end_io = end_bio_bh_io_sync;
	bio->bi_private = bh;

	bio_get(bio);
	submit_bio(rw, bio);

	if (bio_flagged(bio, BIO_EOPNOTSUPP))
		ret = -EOPNOTSUPP;

	bio_put(bio);
	return ret;
}
```

## 汎用ブロック層

### submit_bio

汎用ブロック層 -> IOスケジューラ層

 * PGPGOUT ページアウト, PGPGIN ページアウト がカウントされているのが興味深い
 * IOスケジューラ層に bio を渡す

```c
/**
 * submit_bio: submit a bio to the block device layer for I/O
 * @rw: whether to %READ or %WRITE, or maybe to %READA (read ahead)
 * @bio: The &struct bio which describes the I/O
 *
 * submit_bio() is very similar in purpose to generic_make_request(), and
 * uses that function to do most of the work. Both are fairly rough
 * interfaces, @bio must be presetup and ready for I/O.
 *
 */
void submit_bio(int rw, struct bio *bio)
{
	int count = bio_sectors(bio);

	BIO_BUG_ON(!bio->bi_size);
	BIO_BUG_ON(!bio->bi_io_vec);
	bio->bi_rw |= rw;
	if (rw & WRITE)
		count_vm_events(PGPGOUT, count);
	else
		count_vm_events(PGPGIN, count);

	if (unlikely(block_dump)) {
		char b[BDEVNAME_SIZE];
		printk(KERN_DEBUG "%s(%d): %s block %Lu on %s\n",
			current->comm, current->pid,
			(rw & WRITE) ? "WRITE" : "READ",
			(unsigned long long)bio->bi_sector,
			bdevname(bio->bi_bdev,b));
	}

	generic_make_request(bio);
}

EXPORT_SYMBOL(submit_bio);
```

## IO スケジューラ層

### generic_make_request

```c
/**
 * generic_make_request: hand a buffer to its device driver for I/O
 * @bio:  The bio describing the location in memory and on the device.
 *
 * generic_make_request() is used to make I/O requests of block
 * devices. It is passed a &struct bio, which describes the I/O that needs
 * to be done.
 *
 * generic_make_request() does not return any status.  The
 * success/failure status of the request, along with notification of
 * completion, is delivered asynchronously through the bio->bi_end_io
 * function described (one day) else where.
 *
 * The caller of generic_make_request must make sure that bi_io_vec
 * are set to describe the memory buffer, and that bi_dev and bi_sector are
 * set to describe the device address, and the
 * bi_end_io and optionally bi_private are set to describe how
 * completion notification should be signaled.
 *
 * generic_make_request and the drivers it calls may use bi_next if this
 * bio happens to be merged with someone else, and may change bi_dev and
 * bi_sector for remaps as it sees fit.  So the values of these fields
 * should NOT be depended on after the call to generic_make_request.
 */
void generic_make_request(struct bio *bio)
{
	request_queue_t *q;
	sector_t maxsector;
	int ret, nr_sectors = bio_sectors(bio);
	dev_t old_dev;

	might_sleep();

    // ブロックデバイスの inode サイズから、セクタ数の上限を出す
    // セクタ数の上限をバリデート
	/* Test device or partition size, when known. */
	maxsector = bio->bi_bdev->bd_inode->i_size >> 9;
	if (maxsector) {
		sector_t sector = bio->bi_sector;

		if (maxsector < nr_sectors || maxsector - nr_sectors < sector) {
			/*
			 * This may well happen - the kernel calls bread()
			 * without checking the size of the device, e.g., when
			 * mounting a device.
			 */
			handle_bad_sector(bio);
			goto end_io;
		}
	}

	/*
	 * Resolve the mapping until finished. (drivers are
	 * still free to implement/resolve their own stacking
	 * by explicitly returning 0)
	 *
	 * NOTE: we don't repeat the blk_size check for each new device.
	 * Stacking drivers are expected to know what they are doing.
	 */
	maxsector = -1;
	old_dev = 0;
	do {
		char b[BDEVNAME_SIZE];

       // ブロックデバイスのディスクごとのキューを取り出す
		q = bdev_get_queue(bio->bi_bdev);
		if (!q) {
			printk(KERN_ERR
			       "generic_make_request: Trying to access "
				"nonexistent block-device %s (%Lu)\n",
				bdevname(bio->bi_bdev, b),
				(long long) bio->bi_sector);
end_io:
			bio_endio(bio, bio->bi_size, -EIO);
			break;
		}

		if (unlikely(bio_sectors(bio) > q->max_hw_sectors)) {
			printk("bio too big device %s (%u > %u)\n", 
				bdevname(bio->bi_bdev, b),
				bio_sectors(bio),
				q->max_hw_sectors);
			goto end_io;
		}

		if (unlikely(test_bit(QUEUE_FLAG_DEAD, &q->queue_flags)))
			goto end_io;

        // パーティション remap
		/*
		 * If this device has partitions, remap block n
		 * of partition p to block n+start(p) of the disk.
		 */
		blk_partition_remap(bio);

        // blcktrace かな?
		if (maxsector != -1)
			blk_add_trace_remap(q, bio, old_dev, bio->bi_sector, 
					    maxsector);

		blk_add_trace_bio(q, bio, BLK_TA_QUEUE);

		maxsector = bio->bi_sector;
		old_dev = bio->bi_bdev->bd_dev;

        // IOスケジューラごとの make_request_fn 呼び出し
		ret = q->make_request_fn(q, bio);
	} while (ret);
}

EXPORT_SYMBOL(generic_make_request);
```

## IO スケジューラ make_request_fn

 * __make_request
 * aoeblk_make_request
 * loop_make_request
   * loopback ブロックデバイス?
 * pkt_make_request
 * rd_make_request
 * mm_make_request
 * dm_request
 * md_fail_request
   * bio_io_error 呼んでるだけ
 * ...

## IO スケジューラ request ->->-> request_queue_t

 * noop
 * deadline
 * CFQ
 * anticipatory

### __make_request_fn

 * blk_queue_bounce ???
 * ポイント: elv_merge, elv_merged_request
   * ELEVATOR_BACK_MERGE, ELEVATOR_FRONT_MERGE 既存の request にマージする?
   * ELV_NO_MERGE マージしない
 * /proc/diskstats の マージセクタ数の統計

```c
static int __make_request(request_queue_t *q, struct bio *bio)
{
	struct request *req;
	int el_ret, rw, nr_sectors, cur_nr_sectors, barrier, err, sync;
	unsigned short prio;
	sector_t sector;

	sector = bio->bi_sector;
	nr_sectors = bio_sectors(bio);
	cur_nr_sectors = bio_cur_sectors(bio);
	prio = bio_prio(bio);

	rw = bio_data_dir(bio);
	sync = bio_sync(bio);

	/*
	 * low level driver can indicate that it wants pages above a
	 * certain limit bounced to low memory (ie for highmem, or even
	 * ISA dma in theory)
	 */
	blk_queue_bounce(q, &bio);

	spin_lock_prefetch(q->queue_lock);

	barrier = bio_barrier(bio);
	if (unlikely(barrier) && (q->next_ordered == QUEUE_ORDERED_NONE)) {
		err = -EOPNOTSUPP;
		goto end_io;
	}

	spin_lock_irq(q->queue_lock);

	if (unlikely(barrier) || elv_queue_empty(q))
		goto get_rq;

	el_ret = elv_merge(q, &req, bio);
	switch (el_ret) {
		case ELEVATOR_BACK_MERGE:
			BUG_ON(!rq_mergeable(req));

			if (!q->back_merge_fn(q, req, bio))
				break;

			blk_add_trace_bio(q, bio, BLK_TA_BACKMERGE);

			req->biotail->bi_next = bio;
			req->biotail = bio;
			req->nr_sectors = req->hard_nr_sectors += nr_sectors;
			req->ioprio = ioprio_best(req->ioprio, prio);
			drive_stat_acct(req, nr_sectors, 0);
			if (!attempt_back_merge(q, req))
				elv_merged_request(q, req);
			goto out;

		case ELEVATOR_FRONT_MERGE:
			BUG_ON(!rq_mergeable(req));

			if (!q->front_merge_fn(q, req, bio))
				break;

			blk_add_trace_bio(q, bio, BLK_TA_FRONTMERGE);

			bio->bi_next = req->bio;
			req->bio = bio;

			/*
			 * may not be valid. if the low level driver said
			 * it didn't need a bounce buffer then it better
			 * not touch req->buffer either...
			 */
			req->buffer = bio_data(bio);
			req->current_nr_sectors = cur_nr_sectors;
			req->hard_cur_sectors = cur_nr_sectors;
			req->sector = req->hard_sector = sector;
			req->nr_sectors = req->hard_nr_sectors += nr_sectors;
			req->ioprio = ioprio_best(req->ioprio, prio);
			drive_stat_acct(req, nr_sectors, 0);
			if (!attempt_front_merge(q, req))
				elv_merged_request(q, req);
			goto out;

		/* ELV_NO_MERGE: elevator says don't/can't merge. */
		default:
			;
	}

get_rq:
	/*
	 * Grab a free request. This is might sleep but can not fail.
	 * Returns with the queue unlocked.
	 */
	req = get_request_wait(q, rw, bio);

	/*
	 * After dropping the lock and possibly sleeping here, our request
	 * may now be mergeable after it had proven unmergeable (above).
	 * We don't worry about that case for efficiency. It won't happen
	 * often, and the elevators are able to handle it.
	 */
	init_request_from_bio(req, bio);

	spin_lock_irq(q->queue_lock);
    
	if (elv_queue_empty(q))
        // キューが空ならデバイスドライバの呼び出しに「蓋」する (request を溜め込む)
		blk_plug_device(q);
	add_request(q, req);
out:
    // 同期?
	if (sync)
        // デバイスドライバを呼び出し
		__generic_unplug_device(q);

	spin_unlock_irq(q->queue_lock);
	return 0;

end_io:
	bio_endio(bio, nr_sectors << 9, err);
	return 0;
}
```

#### get_request_wait

 * __generic_unplug_device
   * http://wiki.bit-hive.com/north/pg/%A5%D6%A5%ED%A5
 %C3%A5%AF%A5%C7%A5%D0%A5%A4%A5%B9%A4%CE%A5%D7%A5%E9%A5%B0%2F%A5%A2%A5%F3%A5%D7%A5%E9%A5%B0  * unplug = デバイスドライバの呼び出し

```c
/*
 * No available requests for this queue, unplug the device and wait for some
 * requests to become available.
 *
 * Called with q->queue_lock held, and returns with it unlocked.
 */
static struct request *get_request_wait(request_queue_t *q, int rw,
					struct bio *bio)
{
	struct request *rq;

    // デバイスのキューから request を取り出す
	rq = get_request(q, rw, bio, GFP_NOIO);

    // queue が starved なので request 出せない
	while (!rq) {
		DEFINE_WAIT(wait);
		struct request_list *rl = &q->rq;

		prepare_to_wait_exclusive(&rl->wait[rw], &wait,
				TASK_UNINTERRUPTIBLE);

        //もういっぺんトライする
		rq = get_request(q, rw, bio, GFP_NOIO);

        // request が取れないので、デバイスドライバの呼び出しして、割り込み待ちに入る?
		if (!rq) {
			struct io_context *ioc;

            // request_queue_t が一杯で request を発行できずスリープしたことを示す
            // ここを追えば、 request queue の長さが足りているかどうか ( starved かどうか) 分かる?
			blk_add_trace_generic(q, bio, rw, BLK_TA_SLEEPRQ);

            // デバイスドライバを呼び出してキューが掃けるのを待つ
			__generic_unplug_device(q);
			spin_unlock_irq(q->queue_lock);
			io_schedule();

			/*
			 * After sleeping, we become a "batching" process and
			 * will be able to allocate at least one request, and
			 * up to a big batch of them for a small period time.
			 * See ioc_batching, ioc_set_batching
			 */
			ioc = current_io_context(GFP_NOIO);
			ioc_set_batching(q, ioc);

			spin_lock_irq(q->queue_lock);
		}
		finish_wait(&rl->wait[rw], &wait);
	}

	return rq;
}
```

### add_request

 * request ->->-> request_queue_t

```c
/*
 * add-request adds a request to the linked list.
 * queue lock is held and interrupts disabled, as we muck with the
 * request queue list.
 */
static inline void add_request(request_queue_t * q, struct request * req)
{
	drive_stat_acct(req, req->nr_sectors, 1);

	if (q->activity_fn)
		q->activity_fn(q->activity_data, rq_data_dir(req));

	/*
	 * elevator indicated where it wants this request to be
	 * inserted at elevator_merge time
	 */
	__elv_add_request(q, req, ELEVATOR_INSERT_SORT, 0);
}
```