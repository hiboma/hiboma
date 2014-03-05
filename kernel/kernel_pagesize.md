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
``

 * pte_present
   * pte_flags(a) & (_PAGE_PRESENT | _PAGE_PROTNONE);
 * pte_file
   * pte_flags(pte) & _PAGE_FILE;
 * pte_none
   * !pte.pte;
 * is_swap_pte = !pte_none(pte) && !pte_present(pte) && !pte_file(pte);
 * pte_dirty
 * pte_young
   * pte_flags(pte) & _PAGE_ACCESSED;
 * PageAnon
 * PageDirty
 * PageReferenced

```c
static void smaps_pte_entry(pte_t ptent, unsigned long addr,
		unsigned long ptent_size, struct mm_walk *walk)
{
	struct mem_size_stats *mss = walk->private;
	struct vm_area_struct *vma = mss->vma;
	struct page *page;
	int mapcount;

	if (is_swap_pte(ptent)) {
		mss->swap += ptent_size;
		return;
	}

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

