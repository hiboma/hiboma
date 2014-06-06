# /proc/<pid>clear_refs

## Documantion/filesystems/proc.txt の説明

```
 clear_refs	Clears page referenced bits shown in smaps output

// ... snip 

The /proc/PID/clear_refs is used to reset the PG_Referenced and ACCESSED/YOUNG
bits on both physical and virtual pages associated with a process.
To clear the bits for all the pages associated with the process
    > echo 1 > /proc/PID/clear_refs

To clear the bits for the anonymous pages associated with the process
    > echo 2 > /proc/PID/clear_refs

To clear the bits for the file mapped pages associated with the process
    > echo 3 > /proc/PID/clear_refs
Any other value written to /proc/PID/clear_refs will have no effect.
```

smaps の `Referenced` のサイズが 0 になる。 対象を anon か file かを選べる

shrink_active_list での relcaim に作用する

 *  PageReferenced なページ => Active リストの先頭に繋
 * !PageReferenced なページ => Inactive リストに繋ぐ

この機能を使うと、pageout させたいプロセスを選択的にできる?

### 説明

http://kernelnewbies.org/Linux_2_6_22

```
Process footprint measurement facility
2.6.22 adds a "Referenced" line to each VMA in /proc/pid/smaps, which indicates how many pages within it are currently marked as referenced or accessed. There's also a new /proc/pid/clear_refs file. When any non-zero number is written to this clear_refs file, the Reference fiel is cleared-

With those mechanism it is now possible to measure approximately how much memory a task is using by clearing the reference bits with "echo 1 > /proc/pid/clear_refs" and checking the reference count for each VMA from the /proc/pid/smaps output at a measured time interval (fe. 1 second). This is a valuable tool to get an approximate measurement of the memory footprint for a task.

Code: (commit), (commit)
```

clear_refs で referenced 落とす => smaps で見る => 参照の度合いを計測できる

 * http://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/commit/?id=f79f177c25016647cc92ffac8afa7cb96ce47011
 * http://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/commit/?id=b813e931b4c8235bb42e301096ea97dbdee3e8fe

## ソース

proc/base.c で次の通りに定義されている 

```c
#ifdef CONFIG_PROC_PAGE_MONITOR
                               // ->
	REG("clear_refs", S_IWUSR, proc_clear_refs_operations),
	REG("smaps",      S_IRUGO, proc_smaps_operations),
	REG("pagemap",    S_IRUGO, proc_pagemap_operations),
#endif
```

proc_clear_refs_operations は file_operations

file_operations のメンバを見た所 write(2) だけサポートしている

```c
const struct file_operations proc_clear_refs_operations = {
	.write		= clear_refs_write,
};
```

clear_refs_write では以下の三つのオペレーションを実行できる様子

```c
#define CLEAR_REFS_ALL 1
#define CLEAR_REFS_ANON 2
#define CLEAR_REFS_MAPPED 3
```

clear_refs_write の中身

 * write された文字列を long 型に変換
 * 対象プロセスの mm_struct を取って vm_area_struct を走査

```c
static ssize_t clear_refs_write(struct file *file, const char __user *buf,
				size_t count, loff_t *ppos)
{
	struct task_struct *task;

   /* Worst case buffer size needed for holding an integer. */
   // #define PROC_NUMBUF 13
   // 12文字+1 で INT を格納するバッファ
	char buffer[PROC_NUMBUF];
	struct mm_struct *mm;
	struct vm_area_struct *vma;
	long type;

	memset(buffer, 0, sizeof(buffer));
	if (count > sizeof(buffer) - 1)
		count = sizeof(buffer) - 1;
	if (copy_from_user(buffer, buf, count))
    	return -EFAULT;

    //文字列を long に型変換
	if (strict_strtol(strstrip(buffer), 10, &type))
		return -EINVAL;
	if (type < CLEAR_REFS_ALL || type > CLEAR_REFS_MAPPED)
		return -EINVAL;
	task = get_proc_task(file->f_path.dentry->d_inode);
	if (!task)
		return -ESRCH;
        
	mm = get_task_mm(task);
	if (mm) {
		struct mm_walk clear_refs_walk = {
			.pmd_entry = clear_refs_pte_range,
			.mm = mm,
		};
		down_read(&mm->mmap_sem);
		for (vma = mm->mmap; vma; vma = vma->vm_next) {
			clear_refs_walk.private = vma;
			if (is_vm_hugetlb_page(vma))
				continue;
			/*
			 * Writing 1 to /proc/pid/clear_refs affects all pages.
			 *
			 * Writing 2 to /proc/pid/clear_refs only affects
			 * Anonymous pages.
			 *
			 * Writing 3 to /proc/pid/clear_refs only affects file
			 * mapped pages.
			 */
			if (type == CLEAR_REFS_ANON && vma->vm_file)
				continue;
			if (type == CLEAR_REFS_MAPPED && !vma->vm_file)
				continue;
			walk_page_range(vma->vm_start, vma->vm_end,
					&clear_refs_walk);
		}
		flush_tlb_mm(mm);
		up_read(&mm->mmap_sem);
		mmput(mm);
	}
	put_task_struct(task);

	return count;
}
```

vm_area_struct を走査して clear_refs_pte_range を実行していく

 * ptep_test_and_clear_young
   * ページフレームの YOUNG フラグを落とす
 * ClearPageReferenced
   * ページの Referenced ビットを落とす?

```c
static int clear_refs_pte_range(pmd_t *pmd, unsigned long addr,
				unsigned long end, struct mm_walk *walk)
{
	struct vm_area_struct *vma = walk->private;
	pte_t *pte, ptent;
	spinlock_t *ptl;
	struct page *page;

	split_huge_page_pmd(walk->mm, pmd);
	if (pmd_trans_unstable(pmd))
		return 0;

	pte = pte_offset_map_lock(vma->vm_mm, pmd, addr, &ptl);
	for (; addr != end; pte++, addr += PAGE_SIZE) {
		ptent = *pte;
		if (!pte_present(ptent))
			continue;

		page = vm_normal_page(vma, addr, ptent);
		if (!page)
			continue;

		/* Clear accessed and referenced bits. */
        // PTE のビットを落とす ?
		ptep_test_and_clear_young(vma, addr, pte);
		ClearPageReferenced(page);
	}

	pte_unmap_unlock(pte - 1, ptl);
	cond_resched();
	return 0;
}
```