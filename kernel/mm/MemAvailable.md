# /proc/meminfo の MemAvailable

プロセスから見ての「空きメモリの量」を出してくれる

 * **free** と **cached** から算出するのは、今日では間違いである
   * **Cacehd** には、解放できないページキャッシュ(共有メモリセグメント、 tmpfs, ramfs ) を含む
   * **Cached** には、再利用可能(reclaimable) な slab を含まない
 * スワップしないようにするメモリ量は、MemFree、Active(file), Inactive(file), SReclaimable と /proc/zoneinfo の **low** から算出できるけど ...
   * ただし、将来的に仕様が変わるかもしれないので、ここから数値を見積もれると期待すべきでない
 * ということで MemAvailable てな便利なのを追加する

## サンプル出力

カーネルが 3.19.1 なのです

```
$ uname -a
Linux vagrant-centos65.vagrantup.com 3.19.1 #1 SMP Sun Mar 8 14:51:58 UTC 2015 x86_64 x86_64 x86_64 GNU/Linux

$ cat /proc/meminfo 
MemTotal:        2006864 kB
MemFree:         1931512 kB
MemAvailable:    1890008 kB // ★
Buffers:            6080 kB
Cached:            16748 kB
SwapCached:          700 kB
Active:            18628 kB
Inactive:           7992 kB
Active(anon):       2888 kB
Inactive(anon):     1244 kB
Active(file):      15740 kB
Inactive(file):     6748 kB
Unevictable:           0 kB
Mlocked:               0 kB
SwapTotal:        262140 kB
SwapFree:         255944 kB
Dirty:                28 kB
Writeback:             0 kB
AnonPages:          3452 kB
Mapped:            10168 kB
Shmem:               308 kB
Slab:              36148 kB
SReclaimable:       7128 kB
SUnreclaim:        29020 kB
KernelStack:        1504 kB
PageTables:         1768 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:     1265572 kB
Committed_AS:      55088 kB
VmallocTotal:   34359738367 kB
VmallocUsed:        6120 kB
VmallocChunk:   34359708492 kB
HardwareCorrupted:     0 kB
AnonHugePages:         0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
DirectMap4k:       24512 kB
DirectMap2M:     2023424 kB
```

## 実装

#### fs/proc/meminfo.c

```c
	for_each_zone(zone)
		wmark_low += zone->watermark[WMARK_LOW];

	/*
	 * Estimate the amount of memory available for userspace allocations,
	 * without causing swapping.
	 *
	 * Free memory cannot be taken below the low watermark, before the
	 * system starts swapping.
	 */
	available = i.freeram - wmark_low;

	/*
	 * Not all the page cache can be freed, otherwise the system will
	 * start swapping. Assume at least half of the page cache, or the
	 * low watermark worth of cache, needs to stay.
	 */
	pagecache = pages[LRU_ACTIVE_FILE] + pages[LRU_INACTIVE_FILE];
	pagecache -= min(pagecache / 2, wmark_low);
	available += pagecache;

	/*
	 * Part of the reclaimable slab consists of items that are in use,
	 * and cannot be freed. Cap this estimate at the low watermark.
	 */
	available += global_page_state(NR_SLAB_RECLAIMABLE) -
		     min(global_page_state(NR_SLAB_RECLAIMABLE) / 2, wmark_low);

	if (available < 0)
		available = 0;

	/*
	 * Tagged format, for easy grepping and expansion.
	 */
	seq_printf(m,
		"MemTotal:       %8lu kB\n"
		"MemFree:        %8lu kB\n"
		"MemAvailable:   %8lu kB\n"

//...

		K(i.totalram),
		K(i.freeram),
		K(available), // ★
```

コミットは http://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/commit/?id=34e431b0ae398fc54ea69ff85ec700722c9da773 である。冒頭に３行まとめを書いたけど、ここの解説を読んでもらうのが一番正しいのである。

```
$ git show 34e431b0ae398fc54ea69ff85ec700722c9da773 | head -n 34
commit 34e431b0ae398fc54ea69ff85ec700722c9da773
Author: Rik van Riel <riel@redhat.com>
Date:   Tue Jan 21 15:49:05 2014 -0800

    /proc/meminfo: provide estimated available memory

    Many load balancing and workload placing programs check /proc/meminfo to
    estimate how much free memory is available.  They generally do this by
    adding up "free" and "cached", which was fine ten years ago, but is
    pretty much guaranteed to be wrong today.

    It is wrong because Cached includes memory that is not freeable as page
    cache, for example shared memory segments, tmpfs, and ramfs, and it does
    not include reclaimable slab memory, which can take up a large fraction
    of system memory on mostly idle systems with lots of files.

    Currently, the amount of memory that is available for a new workload,
    without pushing the system into swap, can be estimated from MemFree,
    Active(file), Inactive(file), and SReclaimable, as well as the "low"
    watermarks from /proc/zoneinfo.

    However, this may change in the future, and user space really should not
    be expected to know kernel internals to come up with an estimate for the
    amount of free memory.

    It is more convenient to provide such an estimate in /proc/meminfo.  If
    things change in the future, we only have to change it in one place.

    Signed-off-by: Rik van Riel <riel@redhat.com>
    Reported-by: Erik Mouw <erik.mouw_2@nxp.com>
    Acked-by: Johannes Weiner <hannes@cmpxchg.org>
    Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
    Signed-off-by: Linus Torvalds <torvalds@linux-foundation.org>

```