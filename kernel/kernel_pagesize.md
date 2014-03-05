## KernelPageSize, KernelPageSize

___/proc/<pid>/smaps___ 

 * vm_area_struct に割り当てた ページサイズなのかな?
 * だいたいは PTE = ページテーブルエントリのサイズと一緒とのこと

```
		   "KernelPageSize: %8lu kB\n"
		   "MMUPageSize:    %8lu kB\n",
// ...
		   vma_kernel_pagesize(vma) >> 10,
		   vma_mmu_pagesize(vma) >> 10);
```

```c
/*
 * Return the size of the pages allocated when backing a VMA. In the majority
 * cases this will be same size as used by the page table entries.
 */
unsigned long vma_kernel_pagesize(struct vm_area_struct *vma)
{
	struct hstate *hstate;

    /* VM_HUGETLB か否か */
	if (!is_vm_hugetlb_page(vma))
		return PAGE_SIZE;

	hstate = hstate_vma(vma);

	return 1UL << (hstate->order + PAGE_SHIFT);
}
EXPORT_SYMBOL_GPL(vma_kernel_pagesize);
```

vm_area_struct + MMU 

```c
/*
 * Return the page size being used by the MMU to back a VMA. In the majority
 * of cases, the page size used by the kernel matches the MMU size. On
 * architectures where it differs, an architecture-specific version of this
 * function is required.
 */
#ifndef vma_mmu_pagesize
unsigned long vma_mmu_pagesize(struct vm_area_struct *vma)
{
	return vma_kernel_pagesize(vma);
}
#endif
```

## fs/proc/task_mmu.c

```c
	seq_printf(m,
		   "Size:           %8lu kB\n"
		   "Rss:            %8lu kB\n"
		   "Pss:            %8lu kB\n"
		   "Shared_Clean:   %8lu kB\n"
		   "Shared_Dirty:   %8lu kB\n"
		   "Private_Clean:  %8lu kB\n"
		   "Private_Dirty:  %8lu kB\n"
		   "Referenced:     %8lu kB\n"
		   "Anonymous:      %8lu kB\n"
		   "AnonHugePages:  %8lu kB\n"
		   "Swap:           %8lu kB\n"
		   "KernelPageSize: %8lu kB\n"
		   "MMUPageSize:    %8lu kB\n",
		   (vma->vm_end - vma->vm_start) >> 10,
		   mss.resident >> 10,
		   (unsigned long)(mss.pss >> (10 + PSS_SHIFT)),
		   mss.shared_clean  >> 10,
		   mss.shared_dirty  >> 10,
		   mss.private_clean >> 10,
		   mss.private_dirty >> 10,
		   mss.referenced >> 10,
		   mss.anonymous >> 10,
		   mss.anonymous_thp >> 10,
		   mss.swap >> 10,
		   vma_kernel_pagesize(vma) >> 10,
		   vma_mmu_pagesize(vma) >> 10);
```

 * pte_present
   * pte_flags(a) & (_PAGE_PRESENT | _PAGE_PROTNONE);
 * pte_file
   * pte_flags(pte) & _PAGE_FILE;
 * pte_none
   * !pte.pte;
 * is_swap_pte = !pte_none(pte) && !pte_present(pte) && !pte_file(pte);
 * pte_dirty
   * pte_flags(pte) & (_PAGE_DIRTY | _PAGE_SOFTDIRTY); 
 * pte_young
   * pte_flags(pte) & _PAGE_ACCESSED;
 * PageAnon
   * ((unsigned long)page->mapping & PAGE_MAPPING_ANON) != 0;
 * PageDirty
   * ?
 * PageReferenced
   * ?

``` c
#define _PAGE_BIT_PRESENT	0	/* is present */
#define _PAGE_BIT_RW		1	/* writeable */
#define _PAGE_BIT_USER		2	/* userspace addressable */
#define _PAGE_BIT_PWT		3	/* page write through */
#define _PAGE_BIT_PCD		4	/* page cache disabled */
#define _PAGE_BIT_ACCESSED	5	/* was accessed (raised by CPU) */
#define _PAGE_BIT_DIRTY		6	/* was written to (raised by CPU) */
#define _PAGE_BIT_PSE		7	/* 4 MB (or 2MB) page */
#define _PAGE_BIT_PAT		7	/* on 4KB pages */
#define _PAGE_BIT_GLOBAL	8	/* Global TLB entry PPro+ */
#define _PAGE_BIT_UNUSED1	9	/* available for programmer */
#define _PAGE_BIT_IOMAP		10	/* flag used to indicate IO mapping */
#define _PAGE_BIT_HIDDEN	11	/* hidden by kmemcheck */
#define _PAGE_BIT_PAT_LARGE	12	/* On 2MB or 1GB pages */
#define _PAGE_BIT_SPECIAL	_PAGE_BIT_UNUSED1
#define _PAGE_BIT_CPA_TEST	_PAGE_BIT_UNUSED1
#define _PAGE_BIT_SOFTDIRTY	_PAGE_BIT_HIDDEN
#define _PAGE_BIT_SPLITTING	_PAGE_BIT_UNUSED1 /* only valid on a PSE pmd */
#define _PAGE_BIT_NX           63       /* No execute: only valid after cpuid check */
```

pte_t からページの利用種別に統計を取る

```c
static void smaps_pte_entry(pte_t ptent, unsigned long addr,
		unsigned long ptent_size, struct mm_walk *walk)
{
	struct mem_size_stats *mss = walk->private;
	struct vm_area_struct *vma = mss->vma;
	struct page *page;
	int mapcount;

    // ページテーブルの内容は swap されている
	if (is_swap_pte(ptent)) {
		mss->swap += ptent_size;
		return;
	}

    // ページテーブルエントリが無いので加算されない
	if (!pte_present(ptent))
		return;

	page = vm_normal_page(vma, addr, ptent);
	if (!page)
		return;

	if (PageAnon(page))
		mss->anonymous += ptent_size;
	mss->resident += ptent_size;

	/* Accumulate the size in pages that have been accessed. */
	if (pte_young(ptent) || PageReferenced(page))
		mss->referenced += ptent_size;

    // atomic_read(&(page)->_mapcount) + 1;        
	mapcount = page_mapcount(page);

	if (mapcount >= 2) {
        // mapcount が 2 == 複数プロセスで shared なページ
		if (pte_dirty(ptent) || PageDirty(page))
			mss->shared_dirty += ptent_size;
		else
			mss->shared_clean += ptent_size;

        // 1プロセス分に換算して足し算
		mss->pss += (ptent_size << PSS_SHIFT) / mapcount;
	} else {
        // mapcount が 1 == private なページ
		if (pte_dirty(ptent) || PageDirty(page))
			mss->private_dirty += ptent_size;
		else
			mss->private_clean += ptent_size;
		mss->pss += (ptent_size << PSS_SHIFT);
	}
}
```

