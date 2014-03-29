# lwn.net: zswap: compressed swap caching

 * http://lwn.net/Articles/552791/

## 斜め訳

 * v3.11 から
 * ___memory compression___

``` 
Useful References:

LSFMM: In-kernel memory compression
https://lwn.net/Articles/548109/

The zswap compressed swap cache
https://lwn.net/Articles/537422/
```

## zswap

swap page の圧縮

 * プロセスの swapout されるページを、動的に確保されたRAMのメモリプールにいれとく
   * 成功すると swap device への writeback を遅延、もしくは 防ぐことができる
   * swap するシステムでめっちゃ I/O 減らせる

ベンチマーク

 * 53% の runtime reduction
 * 76% の I/O reduction
 * プールのサイズ制限に達したか buddy アロケータからページを確保できない時に圧縮したキャッシュを swap device に追いやることができる

基本原則

 * CPU <=> swap I/O 削減 とのトレードオフ
 * 圧縮キャッシュへの read/write >>>> swap device の非同期ブロックI/O

使えそうなとこ

 * RAMの少ないデスクトップ/ラップトップで swap の軽減
 * I/O を共有しててオーバーコミットしてるVMゲストで swap プレッシャーの軽減
   * hypervisor へひどい I/O がいってしまうのを防ぐ
 * SSD を swap にしている場合に write で寿命縮むのを防ぐ

zcache

 * zcache は RAM で page cache 圧縮。zcache でも swap の圧縮はできる
 * zswap は別のやり方で swap 圧縮の利便性を提供

## 設計

```
swap page =>=>=> frontswap =>=>=> zswap =>=>=> swap device
```

 * zswap は Frontswap API からページを受け取る?
 * LRUにのっとって、圧縮プールから swapデバイスに ページを writeback して evict できる
   * 圧縮プールがいっぱい、もしくは buddy allocator から割り当てできない時
 * zswap は __zbud__ を利用する
   * z(lib?) buddy allocator ?
   * 圧縮プールは動的に伸縮する。事前割り当てされない

#### zbud   

> * zbud is an special purpose allocator for storing compressed pages.  Contrary
> * to what its name may suggest, zbud is not a buddy allocator, but rather an
> * allocator that "buddies" two compressed pages together in a single memory
> * page.

> * zbud works by storing compressed pages, or "zpages", together in pairs in a
> * single memory page called a "zbud page".  The first buddy is "left
> * justified" at the beginning of the zbud page, and the last buddy is "right
> * justified" at the end of the zbud page.  The benefit is that if either
> * buddy is freed, the freed buddy space, coalesced with whatever slack space
> * that existed between the buddies, results in the largest possible free region
> * within the zbud page.

```
[ left justified ][][][][][][ right justified ]
```

??? 圧縮自体は zbud ではしないのかな

#### sysfs 
 
 * max_compression_ratio
 * max_pool_percent

#### debugfs

 * 統計とれる

```
 Documentation/vm/zswap.txt |   68 ++++
 fs/debugfs/file.c          |   42 ++
 include/linux/debugfs.h    |    2 +
 include/linux/zbud.h       |   22 ++
 lib/fault-inject.c         |   21 -
 mm/Kconfig                 |   30 ++
 mm/Makefile                |    2 +
 mm/zbud.c                  |  526 ++++++++++++++++++++++++
 mm/zswap.c                 |  943 ++++++++++++++++++++++++++++++++++++++++++++
 9 files changed, 1635 insertions(+), 21 deletions(-)
 create mode 100644 Documentation/vm/zswap.txt
 create mode 100644 include/linux/zbud.h
 create mode 100644 mm/zbud.c
 create mode 100644 mm/zswap.c
```

## 圧縮プール

linux-3.13.5/mm/zbud.c

```c
/**
 * struct zbud_pool - stores metadata for each zbud pool
 * @lock:	protects all pool fields and first|last_chunk fields of any
 *		zbud page in the pool
 * @unbuddied:	array of lists tracking zbud pages that only contain one buddy;
 *		the lists each zbud page is added to depends on the size of
 *		its free region.
 * @buddied:	list tracking the zbud pages that contain two buddies;
 *		these zbud pages are full
 * @lru:	list tracking the zbud pages in LRU order by most recently
 *		added buddy.
 * @pages_nr:	number of zbud pages in the pool.
 * @ops:	pointer to a structure of user defined operations specified at
 *		pool creation time.
 *
 * This structure is allocated at pool creation time and maintains metadata
 * pertaining to a particular zbud pool.
 */
struct zbud_pool {
	spinlock_t lock;
	struct list_head unbuddied[NCHUNKS];
	struct list_head buddied;
	struct list_head lru;
	u64 pages_nr;
	struct zbud_ops *ops;
};
```

