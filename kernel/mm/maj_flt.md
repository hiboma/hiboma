# maj_flt

`/proc/$pid/stat` で吐き出される数値

#### fs/proc/array.c

 * task_struct の maj_flt
 * signal_struct の maj_flt

```c
		/* add up live thread stats at the group level */
		if (whole) {
			struct task_struct *t = task;
			do {
				min_flt += t->min_flt;
				maj_flt += t->maj_flt;
				gtime = cputime_add(gtime, t->gtime);
				t = next_thread(t);
			} while (t != task);

			min_flt += sig->min_flt;
			maj_flt += sig->maj_flt;
			thread_group_times(task, &utime, &stime);
			gtime = cputime_add(gtime, sig->gtime);
		}
```

## task_struct の maj_flt++ しているコード

その1

```c
int __get_user_pages(struct task_struct *tsk, struct mm_struct *mm,
		     unsigned long start, int nr_pages, unsigned int gup_flags,
		     struct page **pages, struct vm_area_struct **vmas)
{
//...
             
		do {
			struct page *page;
			unsigned int foll_flags = gup_flags;

			/*
			 * If we have a pending SIGKILL, don't keep faulting
			 * pages and potentially allocating memory.
			 */
			if (unlikely(fatal_signal_pending(current)))
				return i ? i : -ERESTARTSYS;

			cond_resched();
			while (!(page = follow_page(vma, start, foll_flags))) {
				int ret;

				ret = handle_mm_fault(mm, vma, start,
					(foll_flags & FOLL_WRITE) ?
					FAULT_FLAG_WRITE : 0);

//...
                    
				if (tsk) {
					if (ret & VM_FAULT_MAJOR)
						tsk->maj_flt++;
					else
						tsk->min_flt++;
				}
```

その2

```c
static inline void __do_page_fault(struct pt_regs *regs, unsigned long address, unsigned long error_code)
{
	struct vm_area_struct *vma;
	struct task_struct *tsk;
	struct mm_struct *mm;
	int fault;
	int write = error_code & PF_WRITE;
	unsigned int flags = FAULT_FLAG_ALLOW_RETRY | FAULT_FLAG_KILLABLE |
					(write ? FAULT_FLAG_WRITE : 0);

	tsk = current;
	mm = tsk->mm;

//...    

    /*
	 * Major/minor page fault accounting is only done on the
	 * initial attempt. If we go through a retry, it is extremely
	 * likely that the page will be found in page cache at that point.
	 */
	if (flags & FAULT_FLAG_ALLOW_RETRY) {
		if (fault & VM_FAULT_MAJOR) {
			tsk->maj_flt++;
			perf_sw_event(PERF_COUNT_SW_PAGE_FAULTS_MAJ, 1,
				      regs, address);
		} else {
			tsk->min_flt++;
			perf_sw_event(PERF_COUNT_SW_PAGE_FAULTS_MIN, 1,
				      regs, address);
		}
		if (fault & VM_FAULT_RETRY) {
			/* Clear FAULT_FLAG_ALLOW_RETRY to avoid any risk
			 * of starvation. */
			flags &= ~FAULT_FLAG_ALLOW_RETRY;
			goto retry;
		}
	}
```