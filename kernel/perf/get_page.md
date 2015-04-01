# get_page

## perf report --stdio -G 

```
# Overhead          Command                  Shared Object
# ........  ...............  .............................
#
     1.69%            httpd  [kernel.kallsyms]              [k] get_page
                      |
                      --- apr_proc_create
                          __libc_fork
                          stub_clone
                          sys_clone
                          do_fork
                          copy_process
                          dup_mm
                          copy_page_range
                         |          
                         |--99.52%-- copy_pte_range
                         |          get_page
                          --0.48%-- [...]
```

#### get_page annotation

```
       │    void get_page(struct page *page)
       │    {
  0.13 │      push   %rbp
  0.11 │      mov    %rsp,%rbp
  0.75 │      sub    $0x10,%rsp
  0.02 │      mov    %rbx,(%rsp)
  0.13 │      mov    %r12,0x8(%rsp)
  0.84 │    → callq  mcount  // ftrace するかどうか
       │      cmpw   $0x0,(%rdi)
 61.33 │      mov    %rdi,%rbx
       │            if (unlikely(PageTail(page)))
  0.27 │    ↓ js     2e
       │     *
       │     * Atomically increments @v by 1.
       │     */
       │    static inline void atomic_inc(atomic_t *v)
       │    {
       │            asm volatile(LOCK_PREFIX "incl %0"
  0.66 │1f:   lock   incl   0x8(%rbx)
       │             * Getting a normal page or the head of a compound page
       │             * requires to already have an elevated page->_count.
       │             */
       │            VM_BUG_ON(atomic_read(&page->_count) <= 0);
       │            atomic_inc(&page->_count);
       │    }
 34.66 │23:   mov    (%rsp),%rbx
  0.14 │      mov    0x8(%rsp),%r12
  0.05 │      leaveq
  0.91 │    ← retq
```

#### call stack

 * get_page
 * -> copy_pte_range
 * -> ( copy_one_pte )
 * -> ...

## get_page

```c
void get_page(struct page *page)
{
	if (unlikely(PageTail(page)))
		if (likely(___get_page_tail(page)))
			return;
	/*
	 * Getting a normal page or the head of a compound page
	 * requires to already have an elevated page->_count.
	 */
	VM_BUG_ON(atomic_read(&page->_count) <= 0);
	atomic_inc(&page->_count);
}
EXPORT_SYMBOL(get_page);
```

## copy_pte_range

```c
int copy_pte_range(struct mm_struct *dst_mm, struct mm_struct *src_mm,
		   pmd_t *dst_pmd, pmd_t *src_pmd, struct vm_area_struct *vma,
		   unsigned long addr, unsigned long end)
{
	pte_t *orig_src_pte, *orig_dst_pte;
	pte_t *src_pte, *dst_pte;
	spinlock_t *src_ptl, *dst_ptl;
	int progress = 0;
	int rss[3];
	swp_entry_t entry = (swp_entry_t){0};

again:
	rss[2] = rss[1] = rss[0] = 0;
	dst_pte = pte_alloc_map_lock(dst_mm, dst_pmd, addr, &dst_ptl);
	if (!dst_pte)
		return -ENOMEM;
	src_pte = pte_offset_map_nested(src_pmd, addr);
	src_ptl = pte_lockptr(src_mm, src_pmd);
	spin_lock_nested(src_ptl, SINGLE_DEPTH_NESTING);
	orig_src_pte = src_pte;
	orig_dst_pte = dst_pte;
	arch_enter_lazy_mmu_mode();

	do {
		/*
		 * We are holding two locks at this point - either of them
		 * could generate latencies in another task on another CPU.
		 */
		if (progress >= 32) {
			progress = 0;
			if (need_resched() ||
			    spin_needbreak(src_ptl) || spin_needbreak(dst_ptl))
				break;
		}

        // PTE が無い
		if (pte_none(*src_pte)) {
			progress++;
			continue;
		}
        // swap の場合
		entry.val = copy_one_pte(dst_mm, src_mm, dst_pte, src_pte,
							vma, addr, rss);
		if (entry.val)
			break;
		progress += 8;
	} while (dst_pte++, src_pte++, addr += PAGE_SIZE, addr != end);

	arch_leave_lazy_mmu_mode();
	spin_unlock(src_ptl);
	pte_unmap_nested(orig_src_pte);
	add_mm_rss(dst_mm, rss[0], rss[1], rss[2]);
	pte_unmap_unlock(orig_dst_pte, dst_ptl);
	cond_resched();

	if (entry.val) {
		if (add_swap_count_continuation(entry, GFP_KERNEL) < 0)
			return -ENOMEM;
		progress = 0;
	}
	if (addr != end)
		goto again;
	return 0;
}
```

## copy_one_pte

vm_area をコピーする

```c
/*
 * copy one vm_area from one task to the other. Assumes the page tables
 * already present in the new task to be cleared in the whole range
 * covered by this vma.
 */

static inline unsigned long
copy_one_pte(struct mm_struct *dst_mm, struct mm_struct *src_mm,
		pte_t *dst_pte, pte_t *src_pte, struct vm_area_struct *vma,
		unsigned long addr, int *rss)
{
	unsigned long vm_flags = vma->vm_flags;
	pte_t pte = *src_pte;
	struct page *page;

	/* pte contains position in swap or file, so copy. */
	if (unlikely(!pte_present(pte))) {
		if (!pte_file(pte)) {

            // anon なページだよ
			swp_entry_t entry = pte_to_swp_entry(pte);

            // swap エントリの参照カウントを増やす
			if (swap_duplicate(entry) < 0)
				return entry.val;

			/* make sure dst_mm is on swapoff's mmlist. */
			if (unlikely(list_empty(&dst_mm->mmlist))) {
				spin_lock(&mmlist_lock);
				if (list_empty(&dst_mm->mmlist))
					list_add(&dst_mm->mmlist,
						 &src_mm->mmlist);
				spin_unlock(&mmlist_lock);
			}
			if (!is_migration_entry(entry))
				rss[2]++;
			else if (is_write_migration_entry(entry) &&
					is_cow_mapping(vm_flags)) {
				/*
				 * COW mappings require pages in both parent
				 * and child to be set to read.
				 */
				make_migration_entry_read(&entry);
				pte = swp_entry_to_pte(entry);
				set_pte_at(src_mm, addr, src_pte, pte);
			}
		}
		goto out_set_pte;
	}

	/*
	 * If it's a COW mapping, write protect it both
	 * in the parent and the child
	 */
	if (is_cow_mapping(vm_flags)) {
		ptep_set_wrprotect(src_mm, addr, src_pte);
		pte = pte_wrprotect(pte);
	}

	/*
	 * If it's a shared mapping, mark it clean in
	 * the child
	 */
	if (vm_flags & VM_SHARED)
		pte = pte_mkclean(pte);
	pte = pte_mkold(pte);

	page = vm_normal_page(vma, addr, pte);
	if (page) {
        // ここで get_page するのがコスト高いの???
		get_page(page);
		page_dup_rmap(page);
		rss[PageAnon(page)]++;
	}

out_set_pte:
	set_pte_at(dst_mm, addr, dst_pte, pte);
	return 0;
}
```