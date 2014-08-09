# VmRSS

```c
struct mm_struct {

//...

	/* Special counters, in some configurations protected by the
	 * page_table_lock, in other configurations by being atomic.
	 */
	mm_counter_t _file_rss;
	mm_counter_t _anon_rss;
	mm_counter_t _swap_usage;
```

USE_SPLIT_PTLOCKS は http://d.hatena.ne.jp/hsyd/20100515/1273945372 を読んで理解

```c
#if USE_SPLIT_PTLOCKS
/*
 * The mm counters are not protected by its page_table_lock,
 * so must be incremented atomically.
 */
#define set_mm_counter(mm, member, value) atomic_long_set(&(mm)->_##member, value)
#define get_mm_counter(mm, member) ((unsigned long)atomic_long_read(&(mm)->_##member))
#define add_mm_counter(mm, member, value) atomic_long_add(value, &(mm)->_##member)
#define inc_mm_counter(mm, member) atomic_long_inc(&(mm)->_##member)
#define dec_mm_counter(mm, member) atomic_long_dec(&(mm)->_##member)

#else  /* !USE_SPLIT_PTLOCKS */
/*
 * The mm counters are protected by its page_table_lock,
 * so can be incremented directly.
 */
#define set_mm_counter(mm, member, value) (mm)->_##member = (value)
#define get_mm_counter(mm, member) ((mm)->_##member)
#define add_mm_counter(mm, member, value) (mm)->_##member += (value)
#define inc_mm_counter(mm, member) (mm)->_##member++
#define dec_mm_counter(mm, member) (mm)->_##member--

#endif /* !USE_SPLIT_PTLOCKS */

#define get_mm_rss(mm)					\
	(get_mm_counter(mm, file_rss) + get_mm_counter(mm, anon_rss))
#define update_hiwater_rss(mm)	do {			\
	unsigned long _rss = get_mm_rss(mm);		\
	if ((mm)->hiwater_rss < _rss)			\
		(mm)->hiwater_rss = _rss;		\
} while (0)

static inline unsigned long get_mm_hiwater_rss(struct mm_struct *mm)
{
	return max(mm->hiwater_rss, get_mm_rss(mm));
}

static inline void setmax_mm_hiwater_rss(unsigned long *maxrss,
					 struct mm_struct *mm)
{
	unsigned long hiwater_rss = get_mm_hiwater_rss(mm);

	if (*maxrss < hiwater_rss)
		*maxrss = hiwater_rss;
}
```

## set_mm_counter

 * kernel/fork.c
 * mm_init で mm_struct の初期化時に使われるマクロ

```c
static struct mm_struct * mm_init(struct mm_struct * mm, struct task_struct *p)
{
	atomic_set(&mm->mm_users, 1);
	atomic_set(&mm->mm_count, 1);
	init_rwsem(&mm->mmap_sem);
	INIT_LIST_HEAD(&mm->mmlist);
	mm->flags = (current->mm) ?
		(current->mm->flags & MMF_INIT_MASK) : default_dump_filter;
	mm->core_state = NULL;
	mm->nr_ptes = 0;
	set_mm_counter(mm, file_rss, 0);
	set_mm_counter(mm, anon_rss, 0);
	set_mm_counter(mm, swap_usage, 0);
```

## add_mm_counter

使われいるのは2箇所だった

### acct_arg_size

 * fs/exec.c
 * argv のページ数なのかな
 

```c
#ifdef CONFIG_MMU

void acct_arg_size(struct linux_binprm *bprm, unsigned long pages)
{
	struct mm_struct *mm = current->mm;

   /* この数値を */
	long diff = (long)(pages - bprm->vma_pages);

	if (!mm || !diff)
		return;

	bprm->vma_pages = pages;

    /* 足す */
#ifdef USE_SPLIT_PTLOCKS
	add_mm_counter(mm, anon_rss, diff);
#else
	spin_lock(&mm->page_table_lock);
	add_mm_counter(mm, anon_rss, diff);
	spin_unlock(&mm->page_table_lock);
#endif
}
```

もう一カ所は mm/memory.c で使われている

```c
static inline void
add_mm_rss(struct mm_struct *mm, int file_rss, int anon_rss, int swap_usage)
{
	if (file_rss)
		add_mm_counter(mm, file_rss, file_rss);
	if (anon_rss)
		add_mm_counter(mm, anon_rss, anon_rss);
	if (swap_usage)
		add_mm_counter(mm, swap_usage, swap_usage);
}
```

add_mm_rss を呼び出すコールスタックは書きの通りで、fork(2) = clone(2) のパスである

 * do_fork
 * copy_process
 * copy_mm
 * dup_mm
 * dup_mmap
 * copy_page_range
 * -> copy_pud_range
 * -> copy_pmd_range
 * -> copy_pte_range
 * -> add_mm_rss

PTE をコピり終わった後に rss の値を足しまくる 

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
		if (pte_none(*src_pte)) {
			progress++;
			continue;
		}
		entry.val = copy_one_pte(dst_mm, src_mm, dst_pte, src_pte,
							vma, addr, rss);
		if (entry.val)
			break;
		progress += 8;
	} while (dst_pte++, src_pte++, addr += PAGE_SIZE, addr != end);

	arch_leave_lazy_mmu_mode();
	spin_unlock(src_ptl);
	pte_unmap_nested(orig_src_pte);

    /* ここで呼び出し */
	add_mm_rss(dst_mm, rss[0], rss[1], rss[2]);
```

脇道で copy_one_pte の中身も見ておこう

```c
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
			swp_entry_t entry = pte_to_swp_entry(pte);

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
		get_page(page);
		page_dup_rmap(page);
		rss[PageAnon(page)]++;
	}

out_set_pte:
	set_pte_at(dst_mm, addr, dst_pte, pte);
	return 0;
}
```