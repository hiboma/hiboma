# unmap_vmas

```
# Overhead          Command      Shared Object          Symbol
# ........  ...............  .................  ..............
#
    68.75%           suexec  [kernel.kallsyms]  [k] unmap_vmas
                     |          
                     |--80.94%-- __execve
                     |          stub_execve
                     |          sys_execve
                     |          do_execve
                     |          search_binary_handler
                     |          |          
                     |          |--99.98%-- load_elf_binary
                     |          |          flush_old_exec
                     |          |          mmput
                     |          |          exit_mmap
                     |          |          unmap_vmas
                     |           --0.02%-- [...]
                     |          
                     |--8.69%-- system_call
                     |          sys_exit_group
                     |          do_group_exit
                     |          do_exit
                     |          exit_mm
                     |          mmput
                     |          |          
                     |          |--99.93%-- exit_mmap
                     |          |          unmap_vmas
                     |           --0.07%-- [...]
                     |          
```

## annotation

```
       │                             }
       │                             ptent = ptep_get_and_clear_full(mm, addr, pte,
       │                                                             tlb->fullmm);
       │                             tlb_remove_tlb_entry(tlb, pte, addr);
  0.13 │6b8:   mov    -0x50(%rbp),%rax
  0.07 │       movl   $0x1,0xc(%rax)
       │                             if (unlikely(!page))
  0.19 │       cmpq   $0x0,-0x58(%rbp)
  0.71 │     ↑ je     471
       │                                     continue;
       │                             if (unlikely(details) && details->nonlinear_vma
  0.07 │       cmpb   $0x0,-0x91(%rbp)
  0.05 │     ↓ jne    ae6
       │                                 && linear_page_index(details->nonlinear_vma,
       │                                                     addr) != page->index)
       │                                     set_pte_at(mm, addr, pte,
       │                                                pgoff_to_pte(page->index));
       │                             if (PageAnon(page)) {
 ▒0.09 │6db:   mov    -0x58(%rbp),%rax
  0.78 │       testb  $0x1,0x18(%rax)
 55.34 │     ↓ je     7d0
       │             TP_printk("mm=%lx address=%lx",
 ▒     │                    (unsigned long)__entry->mm, __entry->address)│             );
       │
       │     TRACE_EVENT(mm_anon_userfree,
  0.52 │       mov    __tracepoint_mm_anon_userfree+0x8,%r9d
       │                                     anon_rss--;
  0.05 │       subl   $0x1,-0x80(%rbp)
  0.50 │       test   %r9d,%r9d

 ```

unmap_vmas から

-> unmap_page_range
-> zap_pud_range
-> zap_pmd_range
-> zap_pte_range

```c
static unsigned long zap_pte_range(struct mmu_gather *tlb,
				struct vm_area_struct *vma, pmd_t *pmd,
				unsigned long addr, unsigned long end,
				long *zap_work, struct zap_details *details)
{
	struct mm_struct *mm = tlb->mm;
	pte_t *pte;
	spinlock_t *ptl;
	int file_rss = 0;
	int anon_rss = 0;
	int swap_usage = 0;

	pte = pte_offset_map_lock(mm, pmd, addr, &ptl);
	arch_enter_lazy_mmu_mode();
	do {
		pte_t ptent = *pte;
		if (pte_none(ptent)) {
			(*zap_work)--;
			continue;
		}

		(*zap_work) -= PAGE_SIZE;

		if (pte_present(ptent)) {
			struct page *page;

			page = vm_normal_page(vma, addr, ptent);
			if (unlikely(details) && page) {
				/*
				 * unmap_shared_mapping_pages() wants to
				 * invalidate cache without truncating:
				 * unmap shared but keep private pages.
				 */
				if (details->check_mapping &&
				    details->check_mapping != page->mapping)
					continue;
				/*
				 * Each page->index must be checked when
				 * invalidating or truncating nonlinear.
				 */
				if (details->nonlinear_vma &&
				    (page->index < details->first_index ||
				     page->index > details->last_index))
					continue;
			}
			ptent = ptep_get_and_clear_full(mm, addr, pte,
							tlb->fullmm);
			tlb_remove_tlb_entry(tlb, pte, addr);

			if (unlikely(!page))
				continue;

			if (unlikely(details) && details->nonlinear_vma
			    && linear_page_index(details->nonlinear_vma,
						addr) != page->index)
				set_pte_at(mm, addr, pte,
					   pgoff_to_pte(page->index));

            // ここらへん ★
			if (PageAnon(page)) {
				anon_rss--;
				trace_mm_anon_userfree(mm, addr);
			} else {
				if (pte_dirty(ptent))
					set_page_dirty(page);
				if (pte_young(ptent) &&
				    likely(!VM_SequentialReadHint(vma)))
					mark_page_accessed(page);
				file_rss--;
				trace_mm_filemap_userunmap(mm, addr);
			}

			page_remove_rmap(page);
			if (unlikely(page_mapcount(page) < 0))
				print_bad_pte(vma, addr, ptent, page);
			tlb_remove_page(tlb, page);
			continue;
		}
		/*
		 * If details->check_mapping, we leave swap entries;
		 * if details->nonlinear_vma, we leave file entries.
		 */
		if (unlikely(details))
			continue;
		if (pte_file(ptent)) {
			if (unlikely(!(vma->vm_flags & VM_NONLINEAR)))
				print_bad_pte(vma, addr, ptent, NULL);
		} else {
			swp_entry_t ent = pte_to_swp_entry(ptent);

			if (!is_migration_entry(ent))
				swap_usage--;
			if (unlikely(!free_swap_and_cache(ent)))
				print_bad_pte(vma, addr, ptent, NULL);
		}
		pte_clear_not_present_full(mm, addr, pte, tlb->fullmm);
	} while (pte++, addr += PAGE_SIZE, (addr != end && *zap_work > 0));

	add_mm_rss(mm, file_rss, anon_rss, swap_usage);
	arch_leave_lazy_mmu_mode();
	pte_unmap_unlock(pte - 1, ptl);

	return addr;
}
```

## unmap_vmas

```c
/**
 * unmap_vmas - unmap a range of memory covered by a list of vma's
 * @tlbp: address of the caller's struct mmu_gather
 * @vma: the starting vma
 * @start_addr: virtual address at which to start unmapping
 * @end_addr: virtual address at which to end unmapping
 * @nr_accounted: Place number of unmapped pages in vm-accountable vma's here
 * @details: details of nonlinear truncation or shared cache invalidation
 *
 * Returns the end address of the unmapping (restart addr if interrupted).
 *
 * Unmap all pages in the vma list.
 *
 * We aim to not hold locks for too long (for scheduling latency reasons).
 * So zap pages in ZAP_BLOCK_SIZE bytecounts.  This means we need to
 * return the ending mmu_gather to the caller.
 *
 * Only addresses between `start' and `end' will be unmapped.
 *
 * The VMA list must be sorted in ascending virtual address order.
 *
 * unmap_vmas() assumes that the caller will flush the whole unmapped address
 * range after unmap_vmas() returns.  So the only responsibility here is to
 * ensure that any thus-far unmapped pages are flushed before unmap_vmas()
 * drops the lock and schedules.
 */
unsigned long unmap_vmas(struct mmu_gather **tlbp,
		struct vm_area_struct *vma, unsigned long start_addr,
		unsigned long end_addr, unsigned long *nr_accounted,
		struct zap_details *details, int fullmm)
{
	long zap_work = ZAP_BLOCK_SIZE;
	unsigned long tlb_start = 0;	/* For tlb_finish_mmu */
	int tlb_start_valid = 0;
	unsigned long start = start_addr;
	spinlock_t *i_mmap_lock = details? details->i_mmap_lock: NULL;
	struct mm_struct *mm = vma->vm_mm;

	/*
	 * mmu_notifier_invalidate_range_start can sleep. Don't initialize
	 * mmu_gather until it completes
	 */
	mmu_notifier_invalidate_range_start(mm, start_addr, end_addr);
	*tlbp = tlb_gather_mmu(mm, fullmm);
	for ( ; vma && vma->vm_start < end_addr; vma = vma->vm_next) {
		unsigned long end;

		start = max(vma->vm_start, start_addr);
		if (start >= vma->vm_end)
			continue;
		end = min(vma->vm_end, end_addr);
		if (end <= vma->vm_start)
			continue;

		if (vma->vm_flags & VM_ACCOUNT)
			*nr_accounted += (end - start) >> PAGE_SHIFT;

		if (unlikely(is_pfn_mapping(vma)))
			untrack_pfn_vma(vma, 0, 0);

		while (start != end) {
			if (!tlb_start_valid) {
				tlb_start = start;
				tlb_start_valid = 1;
			}

			if (unlikely(is_vm_hugetlb_page(vma))) {
				/*
				 * It is undesirable to test vma->vm_file as it
				 * should be non-null for valid hugetlb area.
				 * However, vm_file will be NULL in the error
				 * cleanup path of do_mmap_pgoff. When
				 * hugetlbfs ->mmap method fails,
				 * do_mmap_pgoff() nullifies vma->vm_file
				 * before calling this function to clean up.
				 * Since no pte has actually been setup, it is
				 * safe to do nothing in this case.
				 */
				if (vma->vm_file) {
					unmap_hugepage_range(vma, start, end, NULL);
					zap_work -= (end - start) /
					pages_per_huge_page(hstate_vma(vma));
				}

				start = end;
			} else
				start = unmap_page_range(*tlbp, vma,
						start, end, &zap_work, details);

			if (zap_work > 0) {
				BUG_ON(start != end);
				break;
			}

			tlb_finish_mmu(*tlbp, tlb_start, start);

			if (need_resched() ||
				(i_mmap_lock && spin_needbreak(i_mmap_lock))) {
				if (i_mmap_lock) {
					*tlbp = NULL;
					goto out;
				}
				cond_resched();
			}

			*tlbp = tlb_gather_mmu(vma->vm_mm, fullmm);
			tlb_start_valid = 0;
			zap_work = ZAP_BLOCK_SIZE;
		}
	}
out:
	mmu_notifier_invalidate_range_end(mm, start_addr, end_addr);
	return start;	/* which is now the end (or restart) address */
}
```