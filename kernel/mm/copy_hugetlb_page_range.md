# copy_hugetlb_page_range

## How to probe by systemtap

```
#!/usr/bin/env stap

# probe kprocess.exit {
# kernel.function("copy_hugetlb_page_range@mm/hugetlb.c:2520") $dst:struct mm_struct* $src:struct mm_struct* $vma:struct vm_area_struct*
probe kernel.function("copy_hugetlb_page_range") {
      printf("%016x   %s", $vma->vm_start, bytes_to_string($vma->vm_end - $vma->vm_start))
      printf("%-25s [%d:%d] %-16s\n", tz_ctime(gettimeofday_s()), pid(), tid(), pid2execname(pid()))
}
```

This tap outputs memory maps of vm_area_struct used for HugeTLBPage. (like `pmap`)

#### usage

 * make a process using hugetlbfs and call fork(2)

```
[vagrant@localhost ~]$ HUGETLB_MORECORE=yes LD_PRELOAD=/usr/lib64/libhugetlbfs.so perl -e '@a = 1 x 1024 x 1024; fork; ; sleep 10' &
[vagrant@localhost ~] pmap $( pgrep perl) | grep anon_hugepage
[15] 7874
0000000001c00000   2048K rw--- anon_hugepage (deleted)
0000000001e00000   2048K rw--- anon_hugepage (deleted)
```

 * In an another terminal session, probe is running

```
[vagrant@localhost ~]$ sudo stap copy_hugetlb_page_range.stp 
0000000001c00000   2.00M Tue Jul 12 17:54:28 2016 EDT [7874:7874] perl
0000000001e00000   2.00M Tue Jul 12 17:54:28 2016 EDT [7874:7874] perl
```

## copy_hugetlb_page_range

```c
int copy_hugetlb_page_range(struct mm_struct *dst, struct mm_struct *src,
			    struct vm_area_struct *vma)
{
	pte_t *src_pte, *dst_pte, entry;
	struct page *ptepage;
	unsigned long addr;
	int cow;
	struct hstate *h = hstate_vma(vma);
	unsigned long sz = huge_page_size(h);
	unsigned long mmun_start;	/* For mmu_notifiers */
	unsigned long mmun_end;		/* For mmu_notifiers */
	int ret = 0;

    // コピーオンライトかどうか?
	cow = (vma->vm_flags & (VM_SHARED | VM_MAYWRITE)) == VM_MAYWRITE;

	mmun_start = vma->vm_start;
	mmun_end = vma->vm_end;

    // MMU = Memory Management Unit の何かを無効にする? 際の通知を出す
	if (cow)
		mmu_notifier_invalidate_range_start(src, mmun_start, mmun_end);

    // [                   VMA                   ]
    // |---->|---->|---->|---->|---->|---->|---->|  sz = HugePageSize ごとのステップ
    //
    // huge_page_size ごとに vm_area_struct をいてレートする
	for (addr = vma->vm_start; addr < vma->vm_end; addr += sz) {
		spinlock_t *src_ptl, *dst_ptl;

        // pgd_offset
        //   -> pud_offset
        //     -> pmd__offset
		src_pte = huge_pte_offset(src, addr);
		if (!src_pte)
			continue;
		dst_pte = huge_pte_alloc(dst, addr, sz);
		if (!dst_pte) {
			ret = -ENOMEM;
			break;
		}

		/* If the pagetables are shared don't copy or take references */
		if (dst_pte == src_pte)
			continue;

		dst_ptl = huge_pte_lock(h, dst, dst_pte);
		src_ptl = huge_pte_lockptr(h, src, src_pte);
		spin_lock_nested(src_ptl, SINGLE_DEPTH_NESTING);
		if (!huge_pte_none(huge_ptep_get(src_pte))) {

            // copy on write なので書き込み禁止にする => fault でコピー発生
			if (cow) {
				huge_ptep_set_wrprotect(src, addr, src_pte);
				mmu_notifier_invalidate_range(src, mmun_start,
							      mmun_end);
			}
			entry = huge_ptep_get(src_pte);
			ptepage = pte_page(entry);
			get_page(ptepage);
			page_dup_rmap(ptepage);
			set_huge_pte_at(dst, addr, dst_pte, entry);
		}
		spin_unlock(src_ptl);
		spin_unlock(dst_ptl);
	}

	if (cow)
		mmu_notifier_invalidate_range_end(src, mmun_start, mmun_end);

	return ret;
}
```

## huge_ptep_allc

```
page global directory
  -> pud_alloc = page upper directory 
  -> pmd_alloc = page middle directory
  -> ( pte_alloc を呼ばない ）
```  

```
pte_t *huge_pte_alloc(struct mm_struct *mm,
			unsigned long addr, unsigned long sz)
{
	pgd_t *pgd;
	pud_t *pud;
	pte_t *pte = NULL;

	pgd = pgd_offset(mm, addr);
	pud = pud_alloc(mm, pgd, addr);
	if (pud) {
		if (sz == PUD_SIZE) {
			pte = (pte_t *)pud;
		} else {
			BUG_ON(sz != PMD_SIZE);
			if (pud_none(*pud))
				pte = huge_pmd_share(mm, addr, pud);
			else
				pte = (pte_t *)pmd_alloc(mm, pud, addr);
		}
	}
	BUG_ON(pte && !pte_none(*pte) && !pte_huge(*pte));

	return pte;
}
```

 pte_t is allocated by pmd_alloc 

#### Where is caller?

```
do_fork
 copy_process
  copy_mm
   dup_mm
    dup_mmap
     copy_page_range
```     

```c
int copy_page_range(struct mm_struct *dst_mm, struct mm_struct *src_mm,
		struct vm_area_struct *vma)
{
	pgd_t *src_pgd, *dst_pgd;
	unsigned long next;
	unsigned long addr = vma->vm_start;
	unsigned long end = vma->vm_end;
	unsigned long mmun_start;	/* For mmu_notifiers */
	unsigned long mmun_end;		/* For mmu_notifiers */
	bool is_cow;
	int ret;

	/*
	 * Don't copy ptes where a page fault will fill them correctly.
	 * Fork becomes much lighter when there are big shared or private
	 * readonly mappings. The tradeoff is that copy_page_range is more
	 * efficient than faulting.
	 */
	if (!(vma->vm_flags & (VM_HUGETLB | VM_NONLINEAR |
			       VM_PFNMAP | VM_MIXEDMAP))) {
		if (!vma->anon_vma)
			return 0;
	}

	if (is_vm_hugetlb_page(vma))
		return copy_hugetlb_page_range(dst_mm, src_mm, vma); <================
```

```
/**
 * follow_page_mask - look up a page descriptor from a user-virtual address
 * @vma: vm_area_struct mapping @address
 * @address: virtual address to look up
 * @flags: flags modifying lookup behaviour
 * @page_mask: on output, *page_mask is set according to the size of the page
 *
 * @flags can have FOLL_ flags set, defined in <linux/mm.h>
 *
 * Returns the mapped (struct page *), %NULL if no mapping exists, or
 * an error pointer if there is a mapping to something not represented
 * by a page descriptor (see also vm_normal_page()).
 */
struct page *follow_page_mask(struct vm_area_struct *vma,
			      unsigned long address, unsigned int flags,
			      unsigned int *page_mask)
{
	pgd_t *pgd;
	pud_t *pud;
	pmd_t *pmd;
	pte_t *ptep, pte;
	spinlock_t *ptl;
	struct page *page;
	struct mm_struct *mm = vma->vm_mm;

...

	page = NULL;
	pgd = pgd_offset(mm, address);
	if (pgd_none(*pgd) || unlikely(pgd_bad(*pgd)))
		goto no_page_table;

	pud = pud_offset(pgd, address);
	if (pud_none(*pud))
		goto no_page_table;

    // PUD が HugeTLBPages 化している。 PUD から page を探す
	if (pud_huge(*pud) && vma->vm_flags & VM_HUGETLB) {
		BUG_ON(flags & FOLL_GET);
		page = follow_huge_pud(mm, address, pud, flags & FOLL_WRITE);
		goto out;
	}
	if (unlikely(pud_bad(*pud)))
		goto no_page_table;

	pmd = pmd_offset(pud, address);
	if (pmd_none(*pmd))
		goto no_page_table;

    // PMD が HugeTLBPages 化している。PMD から page を探す
	if (pmd_huge(*pmd) && vma->vm_flags & VM_HUGETLB) {
		BUG_ON(flags & FOLL_GET);
		page = follow_huge_pmd(mm, address, pmd, flags & FOLL_WRITE);
		goto out;
	}

    // PTE から page を探す

```

## follow_huge_pmd / follow_huge_pud

```
struct page *
follow_huge_pmd(struct mm_struct *mm, unsigned long address,
		pmd_t *pmd, int write)
{
	struct page *page;

// #define PMD_SIZE	(_AC(1, UL) << PMD_SHIFT)
// #define PMD_MASK	(~(PMD_SIZE - 1))

	page = pte_page(*(pte_t *)pmd);
	if (page)
		page += ((address & ~PMD_MASK) >> PAGE_SHIFT);
	return page;
}

struct page *
follow_huge_pud(struct mm_struct *mm, unsigned long address,
		pud_t *pud, int write)
{
	struct page *page;

// #define PUD_SIZE	(_AC(1, UL) << PUD_SHIFT)
// #define PUD_MASK	(~(PUD_SIZE - 1))

	page = pte_page(*(pte_t *)pud);
	if (page)
		page += ((address & ~PUD_MASK) >> PAGE_SHIFT);
	return page;
}
```