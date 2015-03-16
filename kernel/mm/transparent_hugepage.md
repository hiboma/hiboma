# transparent_hugepage

```c
static struct attribute *khugepaged_attr[] = {
	&khugepaged_defrag_attr.attr,
	&khugepaged_max_ptes_none_attr.attr,
	&pages_to_scan_attr.attr,
	&pages_collapsed_attr.attr,
	&full_scans_attr.attr,
	&scan_sleep_millisecs_attr.attr,
	&alloc_sleep_millisecs_attr.attr,
	NULL,
};

static struct attribute_group khugepaged_attr_group = {
	.attrs = khugepaged_attr,
	.name = "khugepaged",
};
```

sysfs インタフェース

```
$ ls -hal /sys/kernel/mm/transparent_hugepage/khugepaged/*
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/transparent_hugepage/khugepaged/alloc_sleep_millisecs
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/transparent_hugepage/khugepaged/defrag
-r--r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/transparent_hugepage/khugepaged/full_scans
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none
-r--r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/transparent_hugepage/khugepaged/pages_collapsed
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/transparent_hugepage/khugepaged/pages_to_scan
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs

$ ls -hal /sys/kernel/mm/redhat_transparent_hugepage/khugepaged/*
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/redhat_transparent_hugepage/khugepaged/alloc_sleep_millisecs
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/redhat_transparent_hugepage/khugepaged/defrag
-r--r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/redhat_transparent_hugepage/khugepaged/full_scans
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/redhat_transparent_hugepage/khugepaged/max_ptes_none
-r--r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/redhat_transparent_hugepage/khugepaged/pages_collapsed
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/redhat_transparent_hugepage/khugepaged/pages_to_scan
-rw-r--r-- 1 root root 4.0K Mar 11 21:22 /sys/kernel/mm/redhat_transparent_hugepage/khugepaged/scan_sleep_millisecs
```

なにする機能だっけ?

## 2.6.32 実装

```c
#define transparent_hugepage_enabled(__vma)				\
	((transparent_hugepage_flags &					\
	 (1<<TRANSPARENT_HUGEPAGE_FLAG) ||				\
	 (transparent_hugepage_flags &					\
	  (1<<TRANSPARENT_HUGEPAGE_REQ_MADV_FLAG) &&			\
	  ((__vma)->vm_flags & VM_HUGEPAGE))) &&			\
	!((__vma)->vm_flags & VM_NOHUGEPAGE))
#define transparent_hugepage_defrag(__vma)				\
	((transparent_hugepage_flags &					\
	  (1<<TRANSPARENT_HUGEPAGE_DEFRAG_FLAG)) ||			\
	 (transparent_hugepage_flags &					\
	  (1<<TRANSPARENT_HUGEPAGE_DEFRAG_REQ_MADV_FLAG) &&		\
	  (__vma)->vm_flags & VM_HUGEPAGE))
```

```c
/*
 * By the time we get here, we already hold the mm semaphore
 */
int handle_mm_fault(struct mm_struct *mm, struct vm_area_struct *vma,
		unsigned long address, unsigned int flags)

	__set_current_state(TASK_RUNNING);

	count_vm_event(PGFAULT);

	if (unlikely(is_vm_hugetlb_page(vma)))
		return hugetlb_fault(mm, vma, address, flags);

retry:
	pgd = pgd_offset(mm, address);
	pud = pud_alloc(mm, pgd, address);
	if (!pud)
		return VM_FAULT_OOM;
	pmd = pmd_alloc(mm, pud, address);
	if (!pmd)
		return VM_FAULT_OOM;

	if (pmd_none(*pmd) && transparent_hugepage_enabled(vma)) {
		if (!vma->vm_ops)
			return do_huge_pmd_anonymous_page(mm, vma, address,
							  pmd, flags);
```