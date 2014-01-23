* [本] Linux Kernel Architecture

* 1. Introduction and Overview

* Virtual and Physical Address Spaces

 * 単語の使い分け
   * page frames ... 物理メモリのページ
   * page        ... 仮想アドレス空間のページを指す
   * userland    ... BSDコミュニティでよく使われる言い回しらしい
   * user space, kernel space ... アプリケーションに加えて仮想アドレス空間なども一緒に指す用語
   * user mode,  kernel mode  ... 特権レベル
   
* Page Tables
 
  * 32bit ... 2レベル
  * 64bit ... 4レベル
    * Page Global Table
    * Page Middle Table
    * Page Table  Entry
    * offset
    
* 2. Process Management and Scheduling

* 2.5.2 Data Structures

 * `Generic Schedluer`
   * テンプレートメソッド的な役割で Scheduling Class に委譲する

 * `Scheduling Classes`
  * CFS, real-time scheduling, scheduling of the idle task

 * `schedulable entities`
   * プロセス単位でのスケジューリングより大きい単位でスケジューリング 
   * "struct sched_entity" のインスタンス
   * group scheduling の単位
     * タイムスライスがプロセスではなく、エンティティ(プロセスのグループ) に対して充てられる
     * cgroup cpu

* 3. Memory Management

* 3.1 Overview

 * アドレス空間は kernel : user = 1 : 3 = 0x000000 ~ 0xbfffffff : 0xc000000 0xffffff で分割される
 * カーネルアドレス空間は物理メモリに直接マッピングされる

 * Linux の物理メモリの区分 (ZONEと呼ばれる
 *  0    - 16MB  DMA
 * 16MB  - 896MB NORMAL  ... 物理メモリに直マップできる。PTEを経由せずアクセスできる。カーネルが使用
   * 128MB 分は memory map や page tables 用に予約されている。そのため 896MB という数値がでてくる
   * refs http://kerneltrap.org/node/2450
 * 896MB - ....  HIGHMEM ... PTEを経由しないとアクセスできない (MMUでの変換コストが発生)
   * HIGMMEM page はカーネルアドレス空間だけの問題。
   * ユーザアドレス空間は必ずページテーブルエントリを経由して間接的にアクセスされる

PTEを経由してアクセスする物理メモリ領域を一般的に `High Memory` と呼ぶ様子
refs http://en.wikipedia.org/wiki/High_memory

----

 * UMA Uniform memory access
  * contigunous
 * NUMA Non unicorm memory access
   * nodes
   * CONFIG_NUMA
   * NUMA_EMU というオプションが AMD64にまる。NUMAのエミュレーション

 * FLATMEM
   * メモリ空間が全て連続しているモデル。馴染みの深いモデル
 * DISCONTIGMEM
   * NUMAを模擬るための設定?
   * 非連続物理メモリ http://www.mars.dti.ne.jp/~otk/bak/200106-linuxkernel24.pdf
 * SPARSEMEM
   * NUMAなアーキテクチャでメモリホットプラグ(稼働中にメモリ取っ替え) を実現する際のモデル
     * `Sparse memory is only useful on x86 if you want memory hotplug, AFAIK.`
       * http://lc.linux.or.jp/lc2002/papers/suganuma0919p.pdf
       * http://osdn.jp/event/kernel2004/pdf/C06.pdf
     * メモリ空間を意図的に穴だらけにして、独立して外したり追加できたりする仕組みなのかな

* 3. NUMAな環境でMySQLやらMongoDBがswap起こす件

http://osdn.jp/event/kernel2004/pdf/C06.pdf を参照した

 * 1. CPUごとにゾーンが定義されている

   /_/howm/images/Linux_Kernel_Architecture.txt-20130218225253.png

 * 2. スワップの処理がゾーンごとに独立している

   /_/howm/images/Linux_Kernel_Architecture.txt-20130218225207.png

 * 3. どれか特定のノードのゾーンでswapの閾値を超える
   * 他ノードでもメモリが余っているにも関わらず swap が発生という仕組み
   
* 3. dev002.tokyo.pb の numactl でノード数と kswapd スレッドの数を確かめる

 * numactl で見ると 2ノード

    [hiroya@dev002]~% numactl --hardware
    available: 2 nodes (0-1)
    node 0 cpus: 0 1 2 3 4 5 12 13 14 15 16 17
    node 0 size: 36854 MB
    node 0 free: 2851 MB
    node 1 cpus: 6 7 8 9 10 11 18 19 20 21 22 23
    node 1 size: 36864 MB
    node 1 free: 4004 MB
    node distances:
    node   0   1 
      0:  10  15 
      1:  15  10 

 * 2ノード分のkswapd カーネルスレッドが生えている

    ps auxf | grep kswapd
    root       258  0.0  0.0      0     0 ?        S    Feb07   0:03  \_ [kswapd0]
    root       259  0.0  0.0      0     0 ?        S    Feb07   0:03  \_ [kswapd1]
    hiroya   22740  0.0  0.0 107456   920 pts/94   S+   16:24   0:00              \_ grep kswapd
    
node = pg_data_t ごとに kswapd スレッドがいる、ということの印

 * numactl は /sys/devices/system/node/, /sys/devices/system/cpu 以下をさらっている

* 3.2 Organization in the (N)UMA Model

 * NUMAのノードが一つになったモデルを UMA と考えてよい
 * RAM は `nodes = pg_data_t` に分割される
 * `node` は `zones` に分割される
   * ZONE_DMA, ZONE_DMA32
   * ZONE_NORMAL
   * ZONE_HIGHMEM
   * ZONE_MOVABLE
     * 各 zone は `page frames = struct page` と結びついている
     
* kswapd スレッド生成のコードから swap の実装を追う (3.0.4)

 * kthread_run で起動して、ポインタを pg_data_t->kswapd に入れておく

    /*
     * This kswapd start function will be called by init and node-hot-add.
     * On node-hot-add, kswapd will moved to proper cpus if cpus are hot-added.
     */
    int kswapd_run(int nid)
    {
    	pg_data_t *pgdat = NODE_DATA(nid);
    	int ret = 0;

    	if (pgdat->kswapd)
    		return 0;
    
    	pgdat->kswapd = kthread_run(kswapd, pgdat, "kswapd%d", nid);
    	if (IS_ERR(pgdat->kswapd)) {
    		/* failure at boot is fatal */
    		BUG_ON(system_state == SYSTEM_BOOTING);
    		printk("Failed to start kswapd on node %d\n",nid);
    		ret = -1;
    	}
    	return ret;
    }

#### /proc/sys/vm/min_free_kbytes について

 * [linux] swapper: page allocation failureを解決するにはvm.min_free_kbytesを設定
   * http://za.toypark.in/html/2010/06-17.html
   * ネットワークカードからの割り込みコンテキストでページ割当ができなくて死ぬ => min_free_kbytes を大きく取る事で空きページを取る事で余裕を持たせる、という?
 
* 3.2.2 Data Structures - pg_data_t

  * ノードのオブジェクト
  　* メモリ使用量の統計, ページ置換はゾーンごとに管理される
    * kswapd 

    /*
     * The pg_data_t structure is used in machines with CONFIG_DISCONTIGMEM
     * (mostly NUMA machines?) to denote a higher-level memory zone than the
     * zone denotes.
     *
     * On NUMA machines, each NUMA node would have a pg_data_t to describe
     * it's memory layout.
     *
     * Memory statistics and page replacement data structures are maintained on a
     * per-zone basis.
     */
    struct bootmem_data;
    typedef struct pglist_data {
    	struct zone node_zones[MAX_NR_ZONES];
    	struct zonelist node_zonelists[MAX_ZONELISTS];
    	int nr_zones;
    #ifdef CONFIG_FLAT_NODE_MEM_MAP	/* means !SPARSEMEM */
    	struct page *node_mem_map;
    #ifdef CONFIG_CGROUP_MEM_RES_CTLR
    	struct page_cgroup *node_page_cgroup;
    #endif
    #endif
    #ifndef CONFIG_NO_BOOTMEM
    	struct bootmem_data *bdata;
    #endif
    // メモリホットプラグ
    #ifdef CONFIG_MEMORY_HOTPLUG
    	/*
    	 * Must be held any time you expect node_start_pfn, node_present_pages
    	 * or node_spanned_pages stay constant.  Holding this will also
    	 * guarantee that any pfn_valid() stays that way.
    	 *
    	 * Nests above zone->lock and zone->size_seqlock.
    	 */
    	spinlock_t node_size_lock;
    #endif
        // node の 一番最初に当てられた論理的なページフレームの番号
    	unsigned long node_start_pfn;
    	unsigned long node_present_pages; /* total number of physical pages */
    	unsigned long node_spanned_pages; /* total size of physical page
    					     range, including holes */
    	int node_id;
        // kswapd の キュー
    	wait_queue_head_t kswapd_wait;
    	struct task_struct *kswapd;	/* Protected by lock_memory_hotplug() */
    	int kswapd_max_order;
    	enum zone_type classzone_idx;
    } pg_data_t;
    
* 3.2.2 Data Structures - zone

 * ゾーン

   * ZONE_PADDING でパディング => lock, lru_lock が CPUキャッシュに載せるための工夫
   * ゾーンごとにメモリ使用量の `watermakrs` が定められている。enum
     * pages_high ----- 安定
     * pages_min  ----- swap out 始まる
     * pages_low  ----- ページ再利用の pressure 強める???

    enum zone_watermarks {
    	WMARK_MIN,
    	WMARK_LOW,
    	WMARK_HIGH,
    	NR_WMARK
    };

   * ゾーンごとに LRUリストが管理されている
    * 2.6.24 とメンバ名が違うね (
    * SMPの場合 並行して ゾーンの再利用が走る
    * wait_* で ページ利用可能待ちになるプロセスをキューイングする

    enum lru_list {
    	LRU_INACTIVE_ANON = LRU_BASE,
    	LRU_ACTIVE_ANON   = LRU_BASE + LRU_ACTIVE, アクティブな無名ページ 
    	LRU_INACTIVE_FILE = LRU_BASE + LRU_FILE,
    	LRU_ACTIVE_FILE   = LRU_BASE + LRU_FILE + LRU_ACTIVE,
    	LRU_UNEVICTABLE,
    	NR_LRU_LISTS
    };

    struct zone {
    	/* Fields commonly accessed by the page allocator */

    	/* zone watermarks, access with *_wmark_pages(zone) macros */
    	unsigned long watermark[NR_WMARK];
    
    	/*
    	 * When free pages are below this point, additional steps are taken
    	 * when reading the number of free pages to avoid per-cpu counter
    	 * drift allowing watermarks to be breached
    	 */
    	unsigned long percpu_drift_mark;
    
    	/*
    	 * We don't know if the memory that we're going to allocate will be freeable
    	 * or/and it will be released eventually, so to avoid totally wasting several
    	 * GB of ram we must reserve some of the lower zone memory (otherwise we risk
    	 * to run OOM on the lower zones despite there's tons of freeable ram
    	 * on the higher zones). This array is recalculated at runtime if the
    	 * sysctl_lowmem_reserve_ratio sysctl changes.
    	 */
        // 緊急用に確保しておくページ
    	unsigned long		lowmem_reserve[MAX_NR_ZONES];

    #ifdef CONFIG_NUMA
    	int node;
    	/*
    	 * zone reclaim becomes active if more unmapped pages exist.
    	 */
    	unsigned long		min_unmapped_pages;
    	unsigned long		min_slab_pages;
    	struct per_cpu_pageset	*pageset[NR_CPUS];
    #else
        // CPUキャッシュに載るページセット = host-n-cold pages
    	struct per_cpu_pageset	pageset[NR_CPUS]; // NR_CPUS はカーネルがサポートするCPU数で、実際の和人は一致しない
    #endif
    	/*
    	 * free areas of different sizes
    	 */
    	spinlock_t		lock;
    #ifdef CONFIG_MEMORY_HOTPLUG
    	/* see spanned/present_pages for more description */
    	seqlock_t		span_seqlock;
    #endif
    	struct free_area	free_area[MAX_ORDER];
    
    #ifndef CONFIG_SPARSEMEM
    	/*
    	 * Flags for a pageblock_nr_pages block. See pageblock-flags.h.
    	 * In SPARSEMEM, this map is stored in struct mem_section
    	 */
    	unsigned long		*pageblock_flags;
    #endif /* CONFIG_SPARSEMEM */
    
    	ZONE_PADDING(_pad1_)

       // いろんなCPUからアクセスされるので スピンロック
    	/* Fields commonly accessed by the page reclaim scanner */
    	spinlock_t		lru_lock;	

    	struct zone_lru {
    		struct list_head list;
    	} lru[NR_LRU_LISTS];
    
    	struct zone_reclaim_stat reclaim_stat;
    
    	unsigned long		pages_scanned;	   /* since last reclaim */
    	unsigned long		flags;		   /* zone flags, see below */
    
    	/* Zone statistics */
    	atomic_long_t		vm_stat[NR_VM_ZONE_STAT_ITEMS];
    
    	/*
    	 * prev_priority holds the scanning priority for this zone.  It is
    	 * defined as the scanning priority at which we achieved our reclaim
    	 * target at the previous try_to_free_pages() or balance_pgdat()
    	 * invokation.
    	 *
    	 * We use prev_priority as a measure of how much stress page reclaim is
    	 * under - it drives the swappiness decision: whether to unmap mapped
    	 * pages.
    	 *
    	 * Access to both this field is quite racy even on uniprocessor.  But
    	 * it is expected to average out OK.
    	 */
    	int prev_priority;
    
    	/*
    	 * The target ratio of ACTIVE_ANON to INACTIVE_ANON pages on
    	 * this zone's LRU.  Maintained by the pageout code.
    	 */
    	unsigned int inactive_ratio;
    
    
    	ZONE_PADDING(_pad2_)
    	/* Rarely used or read-mostly fields */
    
    	/*
    	 * wait_table		-- the array holding the hash table
    	 * wait_table_hash_nr_entries	-- the size of the hash table array
    	 * wait_table_bits	-- wait_table_size == (1 << wait_table_bits)
    	 *
    	 * The purpose of all these is to keep track of the people
    	 * waiting for a page to become available and make them
    	 * runnable again when possible. The trouble is that this
    	 * consumes a lot of space, especially when so few things
    	 * wait on pages at a given time. So instead of using
    	 * per-page waitqueues, we use a waitqueue hash table.
    	 *
    	 * The bucket discipline is to sleep on the same queue when
    	 * colliding and wake all in that wait queue when removing.
    	 * When something wakes, it must check to be sure its page is
    	 * truly available, a la thundering herd. The cost of a
    	 * collision is great, but given the expected load of the
    	 * table, they should be so rare as to be outweighed by the
    	 * benefits from the saved space.
    	 *
    	 * __wait_on_page_locked() and unlock_page() in mm/filemap.c, are the
    	 * primary users of these fields, and in mm/page_alloc.c
    	 * free_area_init_core() performs the initialization of them.
    	 */
        // ページ解放待ちのプロセスを繋げとく
    	wait_queue_head_t	* wait_table;
    	unsigned long		wait_table_hash_nr_entries;
    	unsigned long		wait_table_bits;
    
    	/*
    	 * Discontig memory support fields.
    	 */
    	struct pglist_data	*zone_pgdat;
    	/* zone_start_pfn == zone_start_paddr >> PAGE_SHIFT */
    	unsigned long		zone_start_pfn;
    
    	/*
    	 * zone_start_pfn, spanned_pages and present_pages are all
    	 * protected by span_seqlock.  It is a seqlock because it has
    	 * to be read outside of zone->lock, and it is done in the main
    	 * allocator path.  But, it is written quite infrequently.
    	 *
    	 * The lock is declared along with zone->lock because it is
    	 * frequently read in proximity to zone->lock.  It's good to
    	 * give them a chance of being in the same cacheline.
    	 */
    	unsigned long		spanned_pages;	/* total size, including holes */
    	unsigned long		present_pages;	/* amount of memory (excluding holes) */
    
    	/*
    	 * rarely used fields:
    	 */
    	const char		*name;
    } ____cacheline_internodealigned_in_smp;

* 3.2.2 Data Structures - Hot-N-Cold Pages

 * CPU キャッシュに載る様に調整された `Hot Pages` を扱う
   * struct zone -> pageset

    struct zone {
        ...
        // CPUキャッシュに載るページセット = host-n-cold pages
        // NR_CPUS はカーネルがサポートするCPU数で、実際の和人は一致しない
    	struct per_cpu_pageset	pageset[NR_CPUS]; 
        ...
    }

   * struct per_cpu_pageset
 
    struct per_cpu_pageset {
    	struct per_cpu_pages pcp;
    #ifdef CONFIG_NUMA
    	s8 expire;
    #endif
    #ifdef CONFIG_SMP
    	s8 stat_threshold;
    	s8 vm_stat_diff[NR_VM_ZONE_STAT_ITEMS];
    #endif
    } ____cacheline_aligned_in_smp;

   * struct per_cpu_pages

    struct per_cpu_pages {
    	int count;		/* number of pages in the list */
    	int high;		/* high watermark, emptying needed */
    	int batch;		/* chunk size for buddy add/remove */

    	/* Lists of pages, one per migrate type stored on the pcp-lists */
    	struct list_head lists[MIGRATE_PCPTYPES];
    };

lists にページフレームが連結して繋がってる、のかな

* Page frames

    /*
     * Each physical page in the system has a struct page associated with
     * it to keep track of whatever it is we are using the page for at the
     * moment. Note that we have no way to track which tasks are using
     * a page, though if it is a pagecache page, rmap structures can tell us
     * who is mapping it.
     */
    struct page {
        // プラットフォームに依存しない
        // PG_locked とか PG_dirty などのフラグ
    	unsigned long flags;		/* Atomic flags, some possibly updated asynchronously */
    	atomic_t _count;		    /* Usage count, see below. */
    	union {
    		atomic_t _mapcount;	/* Count of ptes mapped in mms,
    					 * to show when page is mapped
    					 * & limit reverse map searches.
    					 */
    		struct {		/* SLUB */
    			u16 inuse;
    			u16 objects;
    		};
    	};
    	union {
    	    struct {
            // bufferヘッドにつかったり
    		unsigned long private;
                            /* Mapping-private opaque data:
    					 	 * usually used for buffer_heads
    						 * if PagePrivate set; used for
    						 * swp_entry_t if PageSwapCache;
    						 * indicates order in the buddy
    						 * system if PG_buddy is set.
            // inode の address_space もしくは 無名アドレス空間オブジェクト指したり
    		struct address_space *mapping;
                            /* If low bit clear, points to
    						 * inode address_space, or NULL.
    						 * If page mapped as anonymous
    						 * memory, low bit is set, and
    						 * it points to anon_vma object:
    						 * see PAGE_MAPPING_ANON below.
    						 */
    	    };
    #if USE_SPLIT_PTLOCKS
    	    spinlock_t ptl;
    #endif
    	    struct kmem_cache *slab;	/* SLUB: Pointer to slab */
    	    struct page *first_page;	/* Compound tail pages */
    	};
    	union {
    		pgoff_t index;		/* Our offset within mapping. */
    		void *freelist;		/* SLUB: freelist req. slab lock */
    	};
    	struct list_head lru;		/* Pageout list, eg. active_list
    					 * protected by zone->lru_lock !
    					 */
    	/*
    	 * On machines where all RAM is mapped into kernel address space,
    	 * we can simply calculate the virtual address. On machines with
    	 * highmem some memory is mapped into kernel virtual memory
    	 * dynamically, so we need a place to store that address.
    	 * Note that this field could be 16 bits on x86 ... ;)
    	 *
    	 * Architectures with slow multiplication can define
    	 * WANT_PAGE_VIRTUAL in asm/page.h
    	 */
    #if defined(WANT_PAGE_VIRTUAL)
    	void *virtual;			/* Kernel virtual address (NULL if
    					   not kmapped, ie. highmem) */
    #endif /* WANT_PAGE_VIRTUAL */
    #ifdef CONFIG_WANT_PAGE_DEBUG_FLAGS
    	unsigned long debug_flags;	/* Use atomic bitops on this */
    #endif
    
    #ifdef CONFIG_KMEMCHECK
    	/*
    	 * kmemcheck wants to track the status of each byte in a page; this
    	 * is a pointer to such a status block. NULL if not tracked.
    	 */
    	void *shadow;
    #endif
    };

* page frames の操作関数

 * wait_on_page_locked(struct page), wait_on_page_writeback(struc page)
   * 共に指定したページが利用可能になるまで TASK_UNINTERRUPTIBLE で待つ操作
     * これらの関数の内部がどのように実装されているかを追う
     * wait_queue_head_t の待ち行列の扱い方
     * TASK_UNINTERRUPTIBLE , TASK_RUNNING の状態遷移
     * 事象待ちに入る際の schedule() の呼び出し方

>>> プロセスコンテキスト     

 * wait_on_page_locked の実装
   * ページがロックされていたら (struct page の status が PG_locked) 待ちにはいる
   * ページ操作の一貫性

    /* 
     * Wait for a page to be unlocked.
     *
     * This must be called with the caller "holding" the page,
     * ie with increased "page->count" so that the page won't
     * go away during the wait..
     */
    static inline void wait_on_page_locked(struct page *page)
    {
    	if (PageLocked(page))
    		wait_on_page_bit(page, PG_locked);
    }

 * wait_on_page_bit の実装
   * TASK_UNINTERRUPTIBLE を指定して待ちに入っている
   * page_waitqueue ... ページ を キュー ( wait_queue_head_t ) にいれて、利用可能になるまでまつ
   * sync_page ... コールバック
     * sync_page を呼び出すと io_schedule を呼び出してコンテキストスイッチする
       * 割り込みコンテンキストでページ操作をするので TASK_UNINTERRUPTIBLE をセットで渡しておく、という使い方か?
     * コールバックに対して TASK_UNINTERRUPTIBLE, TASK_INTERRUPTIBLE どちらを選ぶかは 呼び出し側の責任になる
    
    void wait_on_page_bit(struct page *page, int bit_nr)
    {
    	DEFINE_WAIT_BIT(wait, &page->flags, bit_nr);
    
    	if (test_bit(bit_nr, &page->flags))
    		__wait_on_bit(page_waitqueue(page), &wait, sync_page,
    							TASK_UNINTERRUPTIBLE);
    }

 * page_waitqueue の実装
   * キュー は ゾーンごとに用意されているので、ゾーンを逆引きする
   * キュー はリスト管理 + 効率あげるためにハッシュテーブルでの管理
   * 全部のページ待ちを管理している
   * 起床させる際には適宜選ぶ => "thundering herd" のコストを抑える
    
    /*
     * In order to wait for pages to become available there must be
     * waitqueues associated with pages. By using a hash table of
     * waitqueues where the bucket discipline is to maintain all
     * waiters on the same queue and wake all when any of the pages
     * become available, and for the woken contexts to check to be
     * sure the appropriate page became available, this saves space
     * at a cost of "thundering herd" phenomena during rare hash
     * collisions.
     */
    static wait_queue_head_t *page_waitqueue(struct page *page)
    {
    	const struct zone *zone = page_zone(page);
    
    	return &zone->wait_table[hash_ptr(page, zone->wait_table_bits)];
    }
    
  * __wait_on_bit の実装
    * 指定のビットが立つ + コールバック呼び出しが成功までループする?
    * コールバックの中で sleep に入る

    /*
     * To allow interruptible waiting and asynchronous (i.e. nonblocking)
     * waiting, the actions of __wait_on_bit() and __wait_on_bit_lock() are
     * permitted return codes. Nonzero return codes halt waiting and return.
     */
    int __sched
    __wait_on_bit(wait_queue_head_t *wq, struct wait_bit_queue *q,
    			int (*action)(void *), unsigned mode)
    {
    	int ret = 0;
    
    	do {
            // 内部でスピンロックしてキューに繋ぐだけ
    		prepare_to_wait(wq, &q->wait, mode);
    		if (test_bit(q->key.bit_nr, q->key.flags))
                // コールバックの中で schedule() を呼び出してコンテキストスイッチ
                // sync_page の中で io_schedule => schedule という呼び出しになっている
    			ret = (*action)(q->key.flags);
    	} while (test_bit(q->key.bit_nr, q->key.flags) && !ret);
    	finish_wait(wq, &q->wait); // ページを確保できたら finish_wait を呼び出して TASK_RUNNING になる
    	return ret;
    }

wait_on_page_bit はコールバックとして sync_page を扱う。これがどのように呼び出されるかを追う
 
  * sync_page の実装
    * address_space が肝

    static int sync_page(void *word)
    {
    	struct address_space *mapping;
    	struct page *page;
    
    	page = container_of((unsigned long *)word, struct page, flags);
    
    	/*
    	 * page_mapping() is being called without PG_locked held.
    	 * Some knowledge of the state and use of the page is used to
    	 * reduce the requirements down to a memory barrier.
    	 * The danger here is of a stale page_mapping() return value
    	 * indicating a struct address_space different from the one it's
    	 * associated with when it is associated with one.
    	 * After smp_mb(), it's either the correct page_mapping() for
    	 * the page, or an old page_mapping() and the page's own
    	 * page_mapping() has gone NULL.
    	 * The ->sync_page() address_space operation must tolerate
    	 * page_mapping() going NULL. By an amazing coincidence,
    	 * this comes about because none of the users of the page
    	 * in the ->sync_page() methods make essential use of the
    	 * page_mapping(), merely passing the page down to the backing
    	 * device's unplug functions when it's non-NULL, which in turn
    	 * ignore it for all cases but swap, where only page_private(page) is
    	 * of interest. When page_mapping() does go NULL, the entire
    	 * call stack gracefully ignores the page and returns.
    	 * -- wli
    	 */
    	smp_mb();
        // ページから address_space を逆引きする
    	mapping = page_mapping(page);

        // ページがマッピングされているアドレス空間オブジェクトのメソッドで sync_page する
    	if (mapping && mapping->a_ops && mapping->a_ops->sync_page)
    		mapping->a_ops->sync_page(page);
    	io_schedule();
    	return 0;
    }

 * io_schedule の実装
   * スケジューラを呼び出す。とても重要
   * I/O accounting もちゃっかり実行する
    
    /*
     * This task is about to go to sleep on IO. Increment rq->nr_iowait so
     * that process accounting knows that this is a task in IO wait state.
     */
    void __sched io_schedule(void)
    {
    	struct rq *rq = raw_rq();
    
    	delayacct_blkio_start();   // CONFIG_TASK_DELAY_ACCT I/O aaccounting
                                   // リソース確保待ちで遅延した時間の statics らしい
    	atomic_inc(&rq->nr_iowait);
    	current->in_iowait = 1;
    	schedule();                // コンテキストスイッチ。
    	current->in_iowait = 0;
    	atomic_dec(&rq->nr_iowait);
    	delayacct_blkio_end();
    }
    EXPORT_SYMBOL(io_schedule);

schedule を呼び出しているので、ページが利用可能になるまで TASK_UNINTERRUPTIBLEで待つ

  * finish_wait の実装
    * 待っていたイベントが完了して起床したプロセスを TASK_RUNNING にして waitキューから取り除く

    /*
     * finish_wait - clean up after waiting in a queue
     * @q: waitqueue waited on
     * @wait: wait descriptor
     *
     * Sets current thread back to running state and removes
     * the wait descriptor from the given waitqueue if still
     * queued.
     */
    void finish_wait(wait_queue_head_t *q, wait_queue_t *wait)
    {
    	unsigned long flags;
    
    	__set_current_state(TASK_RUNNING);
    	/*
    	 * We can check for list emptiness outside the lock
    	 * IFF:
    	 *  - we use the "careful" check that verifies both
    	 *    the next and prev pointers, so that there cannot
    	 *    be any half-pending updates in progress on other
    	 *    CPU's that we haven't seen yet (and that might
    	 *    still change the stack area.
    	 * and
    	 *  - all other users take the lock (ie we can only
    	 *    have _one_ other CPU that looks at or modifies
    	 *    the list).
    	 */
    	if (!list_empty_careful(&wait->task_list)) {
    		spin_lock_irqsave(&q->lock, flags);
    		list_del_init(&wait->task_list);
    		spin_unlock_irqrestore(&q->lock, flags);
    	}
    }

  * struct zone
    * ゾーンごとに wait_table を用意している
    * ページ利用の キューを管理する
    
    	/*
    	 * wait_table		-- the array holding the hash table
    	 * wait_table_hash_nr_entries	-- the size of the hash table array
    	 * wait_table_bits	-- wait_table_size == (1 << wait_table_bits)
    	 *
    	 * The purpose of all these is to keep track of the people
    	 * waiting for a page to become available and make them
    	 * runnable again when possible. The trouble is that this
    	 * consumes a lot of space, especially when so few things
    	 * wait on pages at a given time. So instead of using
    	 * per-page waitqueues, we use a waitqueue hash table.

         > リスト管理だけだとコストがかさむので ハッシュテーブルの waitqueue を用意する
    	 
    	 * The bucket discipline is to sleep on the same queue when
    	 * colliding and wake all in that wait queue when removing.

         > キューから取り除き起床する際に衝突する

    	 * When something wakes, it must check to be sure its page is
    	 * truly available, a la thundering herd.

         > 起床する際にはページが本当に利用可能かどうかを確認しないといけない => thundering herd
         
         * The cost of a
    	 * collision is great, but given the expected load of the
    	 * table, they should be so rare as to be outweighed by the
    	 * benefits from the saved space.
         
         > 衝突のコストは高いけど、そうそう起こらないので抑えようとする効果を上回る

    	 *
    	 * __wait_on_page_locked() and unlock_page() in mm/filemap.c, are the
    	 * primary users of these fields, and in mm/page_alloc.c
    	 * free_area_init_core() performs the initialization of them.
    	 */
    	wait_queue_head_t	* wait_table;

上記は ページ利用可能になるまで TASK_UNINTERRUPTIBLE で待つパスである

待ちプロセスを起床させる際には wake_up_*** から始まるパスになる

>>> 多分割り込みコンテキスト

 * wake_up の実装
   * 指定したキューで待っている"全ての"プロセスを起床させる

    #define wake_up(x)			__wake_up(x, TASK_NORMAL, 1, NULL)

 * __wake_up の実装

    /**
     * __wake_up - wake up threads blocked on a waitqueue.
     * @q: the waitqueue
     * @mode: which threads
     * @nr_exclusive: how many wake-one or wake-many threads to wake up
     * @key: is directly passed to the wakeup function
     *
     * It may be assumed that this function implies a write memory barrier before
     * changing the task state if and only if any tasks are woken up.
     */
    void __wake_up(wait_queue_head_t *q, unsigned int mode,
    			int nr_exclusive, void *key)
    {
    	unsigned long flags;
    
    	spin_lock_irqsave(&q->lock, flags);
    	__wake_up_common(q, mode, nr_exclusive, 0, key);
    	spin_unlock_irqrestore(&q->lock, flags);
    }
    EXPORT_SYMBOL(__wake_up);

  * __wake_up_common の実装
    * 指定したキューに繋がっているプロセスを逐一起床させていく
    * 全て起床させるかどうかは、上位のメソッドのパラメータ (nr_exclusive) で決定する 
        
    /*
     * The core wakeup function. Non-exclusive wakeups (nr_exclusive == 0) just
     * wake everything up. If it's an exclusive wakeup (nr_exclusive == small +ve
     * number) then we wake all the non-exclusive tasks and one exclusive task.
     *
     * There are circumstances in which we can try to wake a task which has already
     * started to run but is not in state TASK_RUNNING. try_to_wake_up() returns
     * zero in this (rare) case, and we handle it by continuing to scan the queue.
     */
    static void __wake_up_common(wait_queue_head_t *q, unsigned int mode,
    			int nr_exclusive, int wake_flags, void *key)
    {
    	wait_queue_t *curr, *next;

        // キューにぶら下がってるプロセスを起床 (全部起床させるかどうかは nr_exclusive の値で調整 )
    	list_for_each_entry_safe(curr, next, &q->task_list, task_list) {
    		unsigned flags = curr->flags;
    
    		if (curr->func(curr, mode, wake_flags, key) &&
    				(flags & WQ_FLAG_EXCLUSIVE) && !--nr_exclusive)
    			break;
    	}
    }
  
  * シグナルを受けて TASK_INTERRUPTIBLE からの起床 => spurious wake up 見せかけの起床 と呼ぶらしい
    * マルチスレッド周りの用語でもあるぽい

