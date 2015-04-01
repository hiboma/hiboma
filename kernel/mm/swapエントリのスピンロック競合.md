# swapエントリのスピンロック競合

自称

 * CoW な複数プロセスがいて、fork と exec する
 * swap out されたページが、 fork と exec するプロセスで共有されている ( CoW ???)
 * fork / exec が頻発すると、スピンロックが競合しやすい

原因
 
 * swap_lock がグローバルで一個だけなので、競合の度合いが高くなる
 * swap_entry_t が増えるにつれて、競合する度合いも高まる?

## 調査方法

```sh
sudo perf record -ag
sudo perf report --call-graph --stdio -G -i perf.data-20150317
```

```
#
# Overhead         Command                 Shared Object                                                         Symbol
# ........  ..............  ............................  .............................................................
#
    29.39%           httpd  [kernel.kallsyms]             [k] _spin_lock                                               
                     |          
                     |--97.52%-- run_cgi_child
                     |          |          
                     |          |--100.00%-- apr_proc_create
                     |          |          __libc_fork
                     |          |          stub_clone
                     |          |          sys_clone
                     |          |          do_fork
                     |          |          |          
                     |          |          |--100.00%-- copy_process
                     |          |          |          |          
                     |          |          |          |--100.00%-- dup_mm
                     |          |          |          |          |          
                     |          |          |          |          |--99.99%-- copy_page_range
                     |          |          |          |          |          |          
                     |          |          |          |          |          |--100.00%-- copy_pte_range
                     |          |          |          |          |          |          |          
                     |          |          |          |          |          |          |--99.95%-- swap_duplicate
                     |          |          |          |          |          |          |          |          
                     |          |          |          |          |          |          |          |--99.84%-- __swap_duplicate
                     |          |          |          |          |          |          |          |          |          
                     |          |          |          |          |          |          |          |          |--99.97%-- _spin_lock
                     |          |          |          |          |          |          |          |           --0.03%-- [...]
                     |          |          |          |          |          |          |           --0.16%-- [...]
                     |          |          |          |          |          |           --0.05%-- [...]
                     |          |          |          |          |           --0.00%-- [...]
                     |          |          |          |           --0.01%-- [...]
                     |          |          |           --0.00%-- [...]
                     |          |           --0.00%-- [...]
                     |           --0.00%-- [...]
                     |          
                     |--2.39%-- __execve
                     |          stub_execve
                     |          sys_execve
                     |          do_execve
                     |          search_binary_handler
                     |          load_elf_binary
                     |          flush_old_exec
                     |          mmput
                     |          exit_mmap
                     |          unmap_vmas
                     |          |          
                     |          |--99.95%-- free_swap_and_cache
                     |          |          |          
                     |          |          |--99.87%-- swap_info_get
                     |          |          |          |          
                     |          |          |          |--99.99%-- _spin_lock
                     |          |          |           --0.01%-- [...]
                     |          |           --0.13%-- [...]
                     |           --0.05%-- [...]
                      --0.09%-- [...]
    24.76%      foo.cgi  [kernel.kallsyms]             [k] _spin_lock
                |
                --- 0x3748aacda7
                    stub_execve
                    sys_execve
                    do_execve
                    search_binary_handler
                    load_elf_binary
                   |          
                   |--99.67%-- flush_old_exec
                   |          mmput
                   |          exit_mmap
                   |          |          
                   |          |--99.98%-- unmap_vmas
                   |          |          |          
                   |          |          |--99.95%-- free_swap_and_cache
                   |          |          |          |          
                   |          |          |          |--99.85%-- swap_info_get
                   |          |          |          |          |          
                   |          |          |          |          |--99.97%-- _spin_lock
                   |          |          |          |           --0.03%-- [...]
                   |          |          |           --0.15%-- [...]
                   |          |           --0.05%-- [...]
                   |           --0.02%-- [...]
                    --0.33%-- [...]
```

## fork(2) 側

fork -> dup_mm で mm_struct 複製 -> swap エントリの参照カウントを増やす

### copy_one_pte

``c
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

        // PTE が存在しない + PTE が file でない => swap
        // ということは、 fork するプロセスの PTE が swap されていなければ、ここを回避する
		if (!pte_file(pte)) {
            // PTE を swap_entry_t に変換
			swp_entry_t entry = pte_to_swp_entry(pte);

            // ★ この中にもぐってスピンロックを取る
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

//...
```

### swap_duplicate

```c
/*
 * increase reference count of swap entry by 1.
 */
int swap_duplicate(swp_entry_t entry)
{
	int err = 0;

	while (!err && __swap_duplicate(entry, 1) == -ENOMEM)
		err = add_swap_count_continuation(entry, GFP_ATOMIC);
	return err;
}
```

### __swap_duplicate

```c
/*
 * Verify that a swap entry is valid and increment its swap map count.
 *
 * Returns error code in following case.
 * - success -> 0
 * - swp_entry is invalid -> EINVAL
 * - swp_entry is migration entry -> EINVAL
 * - swap-cache reference is requested but there is already one. -> EEXIST
 * - swap-cache reference is requested but the entry is not used. -> ENOENT
 * - swap-mapped reference requested but needs continued swap count. -> ENOMEM
 */
static int __swap_duplicate(swp_entry_t entry, unsigned char usage)
{
	struct swap_info_struct *p;
	unsigned long offset, type;
	unsigned char count;
	unsigned char has_cache;
	int err = -EINVAL;

    // ???
    // swap でなければ、 spin_lock を取らない
	if (non_swap_entry(entry))
		goto out;

	type = swp_type(entry);
	if (type >= nr_swapfiles)
		goto bad_file;
	p = swap_info[type];
	offset = swp_offset(entry);

    // ★ ここでロック獲得
	spin_lock(&swap_lock);
	if (unlikely(offset >= p->max))
		goto unlock_out;

    // offset のスロットから swapエントリを取る。 count は参照カウント?
    // http://wiki.bit-hive.com/north/pg/swapon
	count = p->swap_map[offset];
    // swapエントリに対応する、ページキャッシュがあるかどうか?
	has_cache = count & SWAP_HAS_CACHE;
	count &= ~SWAP_HAS_CACHE;
	err = 0;

	if (usage == SWAP_HAS_CACHE) {

		/* set SWAP_HAS_CACHE if there is no cache and entry is used */
		if (!has_cache && count)
			has_cache = SWAP_HAS_CACHE;
		else if (has_cache)		/* someone else added cache */
			err = -EEXIST;
		else				/* no users remaining */
			err = -ENOENT;

	} else if (count || has_cache) {

		if ((count & ~COUNT_CONTINUED) < SWAP_MAP_MAX)
			count += usage;
		else if ((count & ~COUNT_CONTINUED) > SWAP_MAP_MAX)
			err = -EINVAL;
		else if (swap_count_continued(p, offset, count))
			count = COUNT_CONTINUED;
		else
			err = -ENOMEM;
	} else
		err = -ENOENT;			/* unused swap entry */

	p->swap_map[offset] = count | has_cache;

unlock_out:
    // ★ ここでロック解除
	spin_unlock(&swap_lock);
out:
	return err;

bad_file:
	printk(KERN_ERR "swap_dup: %s%08lx\n", Bad_file, entry.val);
	goto out;
}
```

## execve(2) 側

 * unmap_vmas
 * -> unmap_page_range
 * -> zap_pud_range
 * -> zap_pmd_range
 * -> zap_pte_range
 * -> free_swap_and_cache

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

//...
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
            // ★
			swp_entry_t ent = pte_to_swp_entry(ptent);

			if (!is_migration_entry(ent))
				swap_usage--;
            // ★
			if (unlikely(!free_swap_and_cache(ent)))
				print_bad_pte(vma, addr, ptent, NULL);
		}
		pte_clear_not_present_full(mm, addr, pte, tlb->fullmm);
	} while (pte++, addr += PAGE_SIZE, (addr != end && *zap_work > 0));
```

### free_swap_and_cache

```c
/*
 * Free the swap entry like above, but also try to
 * free the page cache entry if it is the last user.
 */
int free_swap_and_cache(swp_entry_t entry)
{
	struct swap_info_struct *p;
	struct page *page = NULL;

	if (non_swap_entry(entry))
		return 1;

    // ★ 中でスピンロック獲得
	p = swap_info_get(entry); 
	if (p) {
		if (swap_entry_free(p, entry, 1) == SWAP_HAS_CACHE) {
			page = find_get_page(&swapper_space, entry.val);
			if (page && !trylock_page(page)) {
				page_cache_release(page);
				page = NULL;
			}
		}
        // ★ スピンロック解除
		spin_unlock(&swap_lock);
	}
	if (page) {
		/*
		 * Not mapped elsewhere, or swap space full? Free it!
		 * Also recheck PageSwapCache now page is locked (above).
		 */
		if (PageSwapCache(page) && !PageWriteback(page) &&
				(!page_mapped(page) || vm_swap_full())) {
			delete_from_swap_cache(page);
			SetPageDirty(page);
		}
		unlock_page(page);
		page_cache_release(page);
	}
	return p != NULL;
}
```

```c
static struct swap_info_struct *swap_info_get(swp_entry_t entry)
{
	struct swap_info_struct *p;
	unsigned long offset, type;

    // swap されたブロックが無ければ、 spin_lock を取らない
	if (!entry.val)
		goto out;
	type = swp_type(entry);
	if (type >= nr_swapfiles)
		goto bad_nofile;
	p = swap_info[type];
	if (!(p->flags & SWP_USED))
		goto bad_device;
	offset = swp_offset(entry);
	if (offset >= p->max)
		goto bad_offset;
	if (!p->swap_map[offset])
		goto bad_free;

    // ★ ここでロック
	spin_lock(&swap_lock);　
	return p;

bad_free:
	printk(KERN_ERR "swap_free: %s%08lx\n", Unused_offset, entry.val);
	goto out;
bad_offset:
	printk(KERN_ERR "swap_free: %s%08lx\n", Bad_offset, entry.val);
	goto out;
bad_device:
	printk(KERN_ERR "swap_free: %s%08lx\n", Unused_file, entry.val);
	goto out;
bad_nofile:
	printk(KERN_ERR "swap_free: %s%08lx\n", Bad_file, entry.val);
out:
	return NULL;
}
```

## スピンロックでストールすると ps や top が詰まるのはなぜか?

 * dup_mmap で down_write(mm->mmap_sem) を取る
 * __swap_duplicate の _spin_lock で競合して、時間がかかる
 * mm->mmap_sem のセマフォがロックされる時間が長くなる
 * proc_pid_cmdline で down_write(mm->mmap_sem) を取ろうとするも TASK_UNINTERRUPTIBLE でブロックする

```
sys_clone                                      | 
 - do_fork                                     | /proc/$pid/cmdline 
 - copy_process                                | 
 - dup_mm                                      | proc_pid_cmdline
 * dup_mmap         # down_write(mm->mmap_sem) | access_remote_vm 
 - copy_page_range                             | __access_remote_vm # down_read(mm->mmap_sem) 
 - copy_pte_range                              |     
 - swap_duplicate                              |        TASK_UNINTERRUPTIBLE でブロック
 - __swap_duplicate                            |       
 * _spin_lock       # ここで競合、ストール        |
```

dup_mmap で down_write(mm->map_sem) を取るソース

```c
#ifdef CONFIG_MMU
static int dup_mmap(struct mm_struct *mm, struct mm_struct *oldmm)
{
	struct vm_area_struct *mpnt, *tmp, *prev, **pprev;
	struct rb_node **rb_link, *rb_parent;
	int retval;
	unsigned long charge;
	struct mempolicy *pol;

    // ★　親? こっち?
	down_write(&oldmm->mmap_sem);
	flush_cache_dup_mm(oldmm);
	/*
	 * Not linked in yet - no deadlock potential:
	 */
    // ★　子? こっち?
	down_write_nested(&mm->mmap_sem, SINGLE_DEPTH_NESTING);

//...

		mm->map_count++;
		retval = copy_page_range(mm, oldmm, mpnt);
```

/proc/$pid/cmdline は

 * proc_pid_cmdline
 * -> access_remote_vm
 * -> __access_remote_vm

と呼び出す。 __access_remote_vm で mm->mmap_sem を down_read しようとする

```c
/*
 * Access another process' address space as given in mm.  If non-NULL, use the
 * given task for page fault accounting.
 */
static int __access_remote_vm(struct task_struct *tsk, struct mm_struct *mm,
		unsigned long addr, void *buf, int len, int write)
{
	struct vm_area_struct *vma;
	void *old_buf = buf;

    // ★ ここでロックをとれず、 TASK_UNINTERRUPTIBLE で待たされる
	down_read(&mm->mmap_sem);
	/* ignore errors, just check how much was successfully transferred */
	while (len) {
		int bytes, ret, offset;
		void *maddr;
		struct page *page = NULL;

		ret = get_user_pages(tsk, mm, addr, 1,
				write, 1, &page, &vma);
		if (ret <= 0) {
```