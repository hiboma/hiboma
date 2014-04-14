## 4.2.1 Layout of the Process Address Space

address_apce プロセスのメモリレイアウト ってどやって決まるんだけの章

```c
struct mm_struct {
...
    /* mmap する際に空きを探すメソッド */
	unsigned long (*get_unmapped_area) (struct file *filp,
				unsigned long addr, unsigned long len,
				unsigned long pgoff, unsigned long flags);
       unsigned long (*get_unmapped_exec_area) (struct file *filp,
				unsigned long addr, unsigned long len,
				unsigned long pgoff, unsigned long flags);
	void (*unmap_area) (struct mm_struct *mm, unsigned long addr);

    /* mmap するアドレスのベース *
	unsigned long mmap_base;		/* base of mmap area */
    /* TASK_SIZE と等しい 64bitの場合はバイナリによる */
	unsigned long task_size;		/* size of task vm space */

	pgd_t * pgd;

    /* テキストセグメントとデータセグメントの始端〜終端 */
	unsigned long start_code, end_code, start_data, end_data;

    /* ヒープとスタック始端。brk は変わるよ　*/
	unsigned long start_brk, brk, start_stack;

   /* argv[], env[] */
	unsigned long arg_start, arg_end, env_start, env_end;

...
};
```

 * arch_pick_mmap_layout, HAVE_ARCH_PICK_MMAP_LAYOUT
   * アーキテクチャ依存の mmap レイアウトを作りたい場合に定義する
 * arch_get_unmapped_area, HAVE_ARCH_UNMAPPED_AREA
   * mmap する空きアドレスを探す場合にアーキテクチャ依存の方法にする
 * arch_get_unmapped_area_topdown
   * mmap するアドレスは 低 => 高 で探す
   * HAVE_ARCH_ GET_UNMAPPED_AREA. して別の実装もとれる

![2014-04-13 16 19 44](https://cloud.githubusercontent.com/assets/172456/2688992/215f1e5a-c2dc-11e3-9b5e-7b726396ada1.png)

 * ___top to bottom___
   * スタックの上限を固定

## 4.2.2 Creating the Layout

execve(2) の load_elf_binary する際に address_space が決まる

#### Figure-4.3

```
load_elf_binary
 -> PF_RANDOMIZE
 -> arch_pick_mmap_layout
 -> setup_arg_pages
```

___ASR = Address Space Randomization___

アドレス空間レイアウトのランダム化

 * **/proc/sys/kernel/randomize_va_space** で切り替え
   * 0 無効
   * 1 ヒープのみ無効 COFIG_COMPAT_BRK
     * http://tsueyasu.blogspot.jp/2008/12/randomizevaspace.html
   * 2 有効

#### randomize_va_space = 0 で無効にした場合

以下のレイアウトで固定される

```
[vagrant@vagrant-centos65 ~]$ bash -c 'pmap $$'
4765:   pmap 4765
0000000000400000     12K r-x--  /usr/bin/pmap
0000000000602000      4K rw---  /usr/bin/pmap
0000000000603000    132K rw---    [ anon ]
00007ffff7826000   1580K r-x--  /lib64/libc-2.12.so
00007ffff79b1000   2044K -----  /lib64/libc-2.12.so
00007ffff7bb0000     16K r----  /lib64/libc-2.12.so
00007ffff7bb4000      4K rw---  /lib64/libc-2.12.so
00007ffff7bb5000     20K rw---    [ anon ]
00007ffff7bba000     56K r-x--  /lib64/libproc-3.2.8.so
00007ffff7bc8000   2048K -----  /lib64/libproc-3.2.8.so
00007ffff7dc8000      4K rw---  /lib64/libproc-3.2.8.so
00007ffff7dc9000     80K rw---    [ anon ]
00007ffff7ddd000    128K r-x--  /lib64/ld-2.12.so
00007ffff7ff2000     12K rw---    [ anon ]
00007ffff7ff8000     12K rw---    [ anon ]
00007ffff7ffb000      4K r-x--    [ anon ]
00007ffff7ffc000      4K r----  /lib64/ld-2.12.so
00007ffff7ffd000      4K rw---  /lib64/ld-2.12.so
00007ffff7ffe000      4K rw---    [ anon ]
00007ffffffea000     84K rw---    [ stack ]
ffffffffff600000      4K r-x--    [ anon ]
 total             6256K
```

#### randomize_va_space = 1 で無効にした場合

ヒープのアドレスだけ固定で他はランダムに変わる。2 にするとヒープも変わる

```
[vagrant@vagrant-centos65 ~]$ bash -c 'pmap $$'
4822:   pmap 4822
0000000000400000     12K r-x--  /usr/bin/pmap
0000000000602000      4K rw---  /usr/bin/pmap
0000000000603000    132K rw---    [ anon ]                # <= ヒープ
00007f0bc5a15000   1580K r-x--  /lib64/libc-2.12.so
00007f0bc5ba0000   2044K -----  /lib64/libc-2.12.so
00007f0bc5d9f000     16K r----  /lib64/libc-2.12.so
00007f0bc5da3000      4K rw---  /lib64/libc-2.12.so
00007f0bc5da4000     20K rw---    [ anon ]
00007f0bc5da9000     56K r-x--  /lib64/libproc-3.2.8.so
00007f0bc5db7000   2048K -----  /lib64/libproc-3.2.8.so
00007f0bc5fb7000      4K rw---  /lib64/libproc-3.2.8.so
00007f0bc5fb8000     80K rw---    [ anon ]
00007f0bc5fcc000    128K r-x--  /lib64/ld-2.12.so
00007f0bc61e2000     12K rw---    [ anon ]
00007f0bc61e8000     12K rw---    [ anon ]
00007f0bc61eb000      4K r----  /lib64/ld-2.12.so
00007f0bc61ec000      4K rw---  /lib64/ld-2.12.so
00007f0bc61ed000      4K rw---    [ anon ]
00007fff83f8d000     84K rw---    [ stack ]
00007fff83fff000      4K r-x--    [ anon ]
ffffffffff600000      4K r-x--    [ anon ]
 total             6256K
```

address_space のレイアウトは ___arch_pick_mmap_layout___ で決まる

```c
/*
 * This function, called very early during the creation of a new
 * process VM image, sets up which VM layout function to use:
 */
void arch_pick_mmap_layout(struct mm_struct *mm)
{
	if (!(2 & exec_shield) && mmap_is_legacy()) {
       // レガシーレイアウト
		mm->mmap_base = mmap_legacy_base();
		mm->get_unmapped_area = arch_get_unmapped_area;
		mm->unmap_area = arch_unmap_area;
	} else {
		mm->mmap_base = mmap_base();
		mm->get_unmapped_area = arch_get_unmapped_area_topdown;
		if (!(current->personality & READ_IMPLIES_EXEC)
		    && mmap_is_ia32()) {
			mm->get_unmapped_exec_area = arch_get_unmapped_exec_area;
			mm->shlib_base = SHLIB_BASE + mmap_rnd();
		}
		mm->unmap_area = arch_unmap_area_topdown;
	}
}
```

### レガシーレイアウトとは?

 * `RLIMIT_STACK == RLIM_INFINITY`
 * `/proc/sys/vm/legacy_va_layout > 0`
   * ___bottom to top___

```c 
static int mmap_is_legacy(void)
{
	if (current->personality & ADDR_COMPAT_LAYOUT)
		return 1;

	if (current->signal->rlim[RLIMIT_STACK].rlim_cur == RLIM_INFINITY)
		return 1;

	return sysctl_legacy_va_layout;
}
```

## 新しいレイアウト


 * ___top to bottom___                        .
   * mmap_base は RLIMIT_STACK で決定される。ただし
   * MIN_GAP = 128MB + ランダムサイズ 以下にならないようにする
   * MAX_GAP 以上にならないようにする

```c
#define MIN_GAP (128*1024*1024UL + stack_maxrandom_size())
#define MAX_GAP (TASK_SIZE/6*5)

static unsigned long mmap_base(void)
{
	unsigned long gap = current->signal->rlim[RLIMIT_STACK].rlim_cur;

	if (gap < MIN_GAP)
		gap = MIN_GAP;
	else if (gap > MAX_GAP)
		gap = MAX_GAP;

	return PAGE_ALIGN(TASK_SIZE - gap - mmap_rnd());
}
```

図解

```
+---------+ TASK_SIZE            
|---------|                   
|//stack//|                       
+----v----+                  
|         |               
+---------+ mm->mmap_base 
|//MMAP///|                     
+----v----+                     
|         |               
|         |                     
|         |                 
+----^----+                       
|///Heap//|                 
+---------+                
|///TEXT//|               
+---------+                   
```

32bit (CentOS4..) で bash の pmap を取る

```
# pmap の結果を逆転させているので注意

ffffe000      4K r-x--    [ anon ]
bff66000    616K rw---    [ stack ] 

....                                                       # 128MB

b7fb0000      8K rw---    [ anon ]                         # GAP?
b7f78000      8K rw---    [ anon ]                         # GAP?
b7d78000   2048K r----  /usr/lib/locale/locale-archive     # mm->mmap_base
b7c94000    912K r----  /usr/lib/locale/locale-archive
b7c8e000     24K r--s-  /usr/lib/gconv/gconv-modules.cache
0a0b7000   1460K rw---    [ anon ]                         # heap
080de000     20K rw---    [ anon ]                         # ????
080d8000     24K rw---  /bin/bash                          # data
08047000    580K r-x--  /bin/bash                          # text
00b31000      4K rw---  /lib/libtermcap.so.2.0.8
00b2e000     12K r-x--  /lib/libtermcap.so.2.0.8
00b1d000      4K rw---  /lib/libdl-2.3.4.so
00b1c000      4K r----  /lib/libdl-2.3.4.so
00b1a000      8K r-x--  /lib/libdl-2.3.4.so
00af1000      8K rw---    [ anon ]
00aef000      8K rw---  /lib/tls/libc-2.3.4.so
00aed000      8K r----  /lib/tls/libc-2.3.4.so
009c3000   1192K r-x--  /lib/tls/libc-2.3.4.so
009c0000      4K rw---  /lib/ld-2.3.4.so
009bf000      4K r----  /lib/ld-2.3.4.so
009a9000     88K r-x--  /lib/ld-2.3.4.so
00321000      4K rw---  /lib/libnss_files-2.3.4.so
00320000      4K r----  /lib/libnss_files-2.3.4.so
00317000     36K r-x--  /lib/libnss_files-2.3.4.so
```

ところが 64bit だとだいぶ様子が違う感じ

```
# pmap の結果を逆転させているので注意

ffffffffff600000      4K r-x--    [ anon ]
00007fff93dff000      4K r-x--    [ anon ]               
00007fff93ccf000     84K rw---    [ stack ]              # スタック
                                                         # 
...                                                      # スタックから mmap_base まで 703GB
                                                         #
00007f4fac724000      4K rw---    [ anon ]               # GAP
00007f4fac723000      4K rw---  /lib64/ld-2.12.so        # mmap_base ?
00007f4fac722000      4K r----  /lib64/ld-2.12.so
00007f4fac71f000     12K rw---    [ anon ]
00007f4fac719000     12K rw---    [ anon ]
00007f4fac503000    128K r-x--  /lib64/ld-2.12.so
00007f4fac4ef000     80K rw---    [ anon ]
00007f4fac4ee000      4K rw---  /lib64/libproc-3.2.8.so
00007f4fac2ee000   2048K -----  /lib64/libproc-3.2.8.so
00007f4fac2e0000     56K r-x--  /lib64/libproc-3.2.8.so
00007f4fac2db000     20K rw---    [ anon ]
00007f4fac2da000      4K rw---  /lib64/libc-2.12.so
00007f4fac2d6000     16K r----  /lib64/libc-2.12.so
00007f4fac0d7000   2044K -----  /lib64/libc-2.12.so
00007f4fabf4c000   1580K r-x--  /lib64/libc-2.12.so

...                                                      # 130366GB

0000000001f77000    132K rw---    [ anon ]               # ヒープ
0000000000602000      4K rw---  /usr/bin/pmap            # data セグメント
0000000000400000     12K r-x--  /usr/bin/pmap            # text セグメント
```

load_elf_binary の setup_arg_pages でスタックの位置を決める

 * argv[] の arg ?

## 4.3 Principle of Memory Mappings

demand paging, backing store, address_space の話

## 4.4 Data Structures

```c
struct mm_struct {
	struct vm_area_struct * mmap;		/* list of VMAs */

    /* vm_area_struct の 赤黒木 */
	struct rb_root mm_rb;

   /* 直近の find_vma の結果を保持 */
	struct vm_area_struct * mmap_cache;	/* last find_vma result */
```

### 4.4.1 Trees and Lists

mm_struct から vm_area_struct ( ___region___ )を辿る方法は二種類用意されている

![2014-04-13 23 48 29](https://cloud.githubusercontent.com/assets/172456/2689732/bf124a80-c31a-11e3-8331-74ccb4d3074c.png)

 * 1. mm_struct->mmap
   * linked-list
 * 2. mm_struct->mm_rb
   * 赤黒木
   * 追加、削除、探索が O(logN)

## 4.4.2 Representation of Regions

___Region = vm_area_struct___ の定義

```c
/*
 * This struct defines a memory VMM memory area. There is one of these
 * per VM-area/task.  A VM area is any part of the process virtual memory
 * space that has a special rule for the page-fault handlers (ie a shared
 * library, the executable area etc).
 */
struct vm_area_struct {
	struct mm_struct * vm_mm;	/* The address space we belong to. */

    /* ユーザ空間での始端と終端 */
	unsigned long vm_start;		/* Our start address within vm_mm. */
	unsigned long vm_end;		/* The first byte after our end address
					   within vm_mm. */

	/* linked list of VM areas per task, sorted by address */
	struct vm_area_struct *vm_next, *vm_prev;

    /* パーミッション */
	pgprot_t vm_page_prot;		/* Access permissions of this VMA. */
	unsigned long vm_flags;		/* Flags, see mm.h. */

	struct rb_node vm_rb;

	/*
	 * For areas with an address space and backing store,
	 * linkage into the address_space->i_mmap prio tree, or
	 * linkage to the list of like vmas hanging off its node, or
	 * linkage of vma in the address_space->i_mmap_nonlinear list.
	 */
	union {
		struct {
			struct list_head list;
			void *parent;	/* aligns with prio_tree_node parent */
			struct vm_area_struct *head;
		} vm_set;

        /* shared mapping の場合 raw_prio_tree に繋がれている? */
		struct raw_prio_tree_node prio_tree_node;
	} shared;

    /* 共有の anon ページの ２重リンクリスト */
	/*
	 * A file's MAP_PRIVATE vma can be in both i_mmap tree and anon_vma
	 * list, after a COW of one of the file pages.	A MAP_SHARED vma
	 * can only be in the i_mmap tree.  An anonymous MAP_PRIVATE, stack
	 * or brk vma (with NULL file) can only be in an anon_vma list.
	 */
	struct list_head anon_vma_chain; /* Serialized by mmap_sem &
					  * page_table_lock */
	struct anon_vma *anon_vma;	/* Serialized by page_table_lock */

	/* Function pointers to deal with this struct. */
    /* ページフォルトの際に呼ばれる .fault が重要 */
	const struct vm_operations_struct *vm_ops;

	/* Information about our backing store: */
    /* ファイルを mmap した際のオフセット 1 = 4KB, 2 = 8KB, 3 = ... */
	unsigned long vm_pgoff;		/* Offset (within vm_file) in PAGE_SIZE
					   units, *not* PAGE_CACHE_SIZE */
	struct file * vm_file;		/* File we map to (can be NULL). */
	void * vm_private_data;		/* was vm_pte (shared mem) */
	unsigned long vm_truncate_count;/* truncate_count or restart_addr */

#ifndef CONFIG_MMU
	struct vm_region *vm_region;	/* NOMMU mapping region */
#endif
#ifdef CONFIG_NUMA
	struct mempolicy *vm_policy;	/* NUMA policy for the VMA */
#endif
	/* reserved for Red Hat */
	unsigned long rh_reserved[2];
};
```