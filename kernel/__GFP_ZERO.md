# __GFP_ZERO

```
#define __GFP_ZERO	((__force gfp_t)___GFP_ZERO)	/* Return zeroed page on success */
```

一例として kzalloc() を追って __GFP_ZERO の使われ方を見る

```c
/**
 * kzalloc - allocate memory. The memory is set to zero.
 * @size: how many bytes of memory are required.
 * @flags: the type of memory to allocate (see kmalloc).
 */
static inline void *kzalloc(size_t size, gfp_t flags)
{
	return kmalloc(size, flags | __GFP_ZERO);
}
```

slab の場合

 * kmalloc
 * -> __kmalloc
 * -> __do_kmalloc
 * -> slab_alloc

と呼び出していって、 slab_alloc() で memset() で 0 初期化している

```c
static __always_inline void *
slab_alloc(struct kmem_cache *cachep, gfp_t flags, unsigned long caller)
{
	unsigned long save_flags;
	void *objp;

...

	local_irq_save(save_flags);
	objp = __do_cache_alloc(cachep, flags);
	local_irq_restore(save_flags);

...

	if (unlikely((flags & __GFP_ZERO) && objp))
		memset(objp, 0, cachep->object_size);

	return objp;
}
```

# 検証

適当なカーネルモジュールで kzalloc() と kmalloc() したアドレスを dmesg に出す

```c
#include <linux/module.h>
#include <linux/slab.h>

MODULE_AUTHOR("hiroya");
MODULE_DESCRIPTION("kzalloc test");
MODULE_LICENSE("GPL");

void *kz, *km;

static int __init kzalloc_init(void)
{
	kz	= kzalloc(PAGE_SIZE, GFP_KERNEL);
	km	= kmalloc(PAGE_SIZE, GFP_KERNEL);
	pr_info("kzalloc: %p kmalloc: %p\n", kz, km);

	return 0;
}

static void __exit kzalloc_exit(void)
{
	kfree(kz);
	kfree(km);
}

module_init(kzalloc_init);
module_exit(kzalloc_exit);
```

dmesg の内容はこんな感じ

```
[  334.125706] kzalloc: ffff880019f0d000 kmalloc: ffff880019f0f000
```

このアドレスを gdb でダンプする

```
$ sudo gdb /usr/lib/debug/lib/modules/3.10.0-327.36.3.el7.x86_64/vmlinux /proc/kcore
(gdb) dump mem /tmp/kzalloc 0xffff880019f0d000 0xffff880019f0e000
(gdb) dump mem /tmp/kmalloc 0xffff880019f1d000 0xffff880019f1e000
```

kzalloc で割り当てた範囲のダンプは 0 初期化されている

```
$ hexdump -C /tmp/kzalloc 
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00001000
```

kmalloc で割り当てた範囲のダンプは ゴミが混じっている。何のデータ化はわからない

```
$ hexdump -C /tmp/kmalloc 
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
000002c0  00 00 00 00 00 00 00 00  67 b0 04 17 00 00 00 80  |........g.......|
000002d0  67 50 69 17 00 00 00 80  67 70 41 17 00 00 00 80  |gPi.....gpA.....|
000002e0  67 f0 68 17 00 00 00 80  00 00 00 00 00 00 00 00  |g.h.............|
000002f0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00000710  25 10 94 01 00 00 00 00  00 00 00 00 00 00 00 00  |%...............|
00000720  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00001000
```

