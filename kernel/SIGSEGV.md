# SIGSEGV

```
$ ./owata 
＼(^o^)／
＼(^o^)／
＼(^o^)／
Segmentation fault
```

```
static noinline void
bad_area_nosemaphore(struct pt_regs *regs, unsigned long error_code,
		     unsigned long address)
{
	__bad_area_nosemaphore(regs, error_code, address, SEGV_MAPERR);
}
```

```
static noinline void
bad_area(struct pt_regs *regs, unsigned long error_code, unsigned long address)
{
	__bad_area(regs, error_code, address, SEGV_MAPERR);
}
```

```
static noinline void
bad_area_access_error(struct pt_regs *regs, unsigned long error_code,
		      unsigned long address)
{
	__bad_area(regs, error_code, address, SEGV_ACCERR);
}
```

## __do_page_fault

x86_64 では bad_area, bad_area_access_error 共に __do_page_fault でのみ使われている

```
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

	/*
	 * Detect and handle instructions that would cause a page fault for
	 * both a tracked kernel page and a userspace page.
	 */
	if (kmemcheck_active(regs))
		kmemcheck_hide(regs);
	prefetchw(&mm->mmap_sem);

	if (unlikely(kmmio_fault(regs, address)))
		return;

	/*
	 * We fault-in kernel-space virtual memory on-demand. The
	 * 'reference' page table is init_mm.pgd.
	 *
	 * NOTE! We MUST NOT take any locks for this case. We may
	 * be in an interrupt or a critical region, and should
	 * only copy the information from the master page table,
	 * nothing more.
	 *
	 * This verifies that the fault happens in kernel space
	 * (error_code & 4) == 0, and that the fault was not a
	 * protection error (error_code & 9) == 0.
	 */
	if (unlikely(fault_in_kernel_space(address))) {
		if (!(error_code & (PF_RSVD | PF_USER | PF_PROT))) {
			if (vmalloc_fault(address) >= 0)
				return;

			if (kmemcheck_fault(regs, address, error_code))
				return;
		}

		/* Can handle a stale RO->RW TLB: */
		if (spurious_fault(error_code, address))
			return;

		/* kprobes don't want to hook the spurious faults: */
		if (notify_page_fault(regs))
			return;
		/*
		 * Don't take the mm semaphore here. If we fixup a prefetch
		 * fault we could otherwise deadlock:
		 */
		bad_area_nosemaphore(regs, error_code, address);

		return;
	}

	/* kprobes don't want to hook the spurious faults: */
	if (unlikely(notify_page_fault(regs)))
		return;
	/*
	 * It's safe to allow irq's after cr2 has been saved and the
	 * vmalloc fault has been handled.
	 *
	 * User-mode registers count as a user access even for any
	 * potential system fault or CPU buglet:
	 */
	if (user_mode_vm(regs)) {
		local_irq_enable();
		error_code |= PF_USER;
	} else {
		if (regs->flags & X86_EFLAGS_IF)
			local_irq_enable();
	}

	if (unlikely(error_code & PF_RSVD))
		pgtable_bad(regs, error_code, address);

	perf_sw_event(PERF_COUNT_SW_PAGE_FAULTS, 1, regs, address);

	/*
	 * If we're in an interrupt, have no user context or are running
	 * in an atomic region then we must not take the fault:
	 */
	if (unlikely(in_atomic() || !mm)) {
		bad_area_nosemaphore(regs, error_code, address);
		return;
	}

	/*
	 * When running in the kernel we expect faults to occur only to
	 * addresses in user space.  All other faults represent errors in
	 * the kernel and should generate an OOPS.  Unfortunately, in the
	 * case of an erroneous fault occurring in a code path which already
	 * holds mmap_sem we will deadlock attempting to validate the fault
	 * against the address space.  Luckily the kernel only validly
	 * references user space from well defined areas of code, which are
	 * listed in the exceptions table.
	 *
	 * As the vast majority of faults will be valid we will only perform
	 * the source reference check when there is a possibility of a
	 * deadlock. Attempt to lock the address space, if we cannot we then
	 * validate the source. If this is invalid we can skip the address
	 * space check, thus avoiding the deadlock:
	 */
	if (unlikely(!down_read_trylock(&mm->mmap_sem))) {
		if ((error_code & PF_USER) == 0 &&
		    !search_exception_tables(regs->ip)) {
			bad_area_nosemaphore(regs, error_code, address);
			return;
		}
retry:
		down_read(&mm->mmap_sem);
	} else {
		/*
		 * The above down_read_trylock() might have succeeded in
		 * which case we'll have missed the might_sleep() from
		 * down_read():
		 */
		might_sleep();
	}

	vma = find_vma(mm, address);
	if (unlikely(!vma)) {
		bad_area(regs, error_code, address);
		return;
	}
	if (likely(vma->vm_start <= address))
		goto good_area;
	if (unlikely(!(vma->vm_flags & VM_GROWSDOWN))) {
		bad_area(regs, error_code, address);
		return;
	}
	if (error_code & PF_USER) {
		/*
		 * Accessing the stack below %sp is always a bug.
		 * The large cushion allows instructions like enter
		 * and pusha to work. ("enter $65535, $31" pushes
		 * 32 pointers and then decrements %sp by 65535.)
		 */
		if (unlikely(address + 65536 + 32 * sizeof(unsigned long) < regs->sp)) {
			bad_area(regs, error_code, address);
			return;
		}
	}
	if (unlikely(expand_stack(vma, address))) {
		bad_area(regs, error_code, address);
		return;
	}

	/*
	 * Ok, we have a good vm_area for this memory access, so
	 * we can handle it..
	 */
good_area:
	if (unlikely(access_error(error_code, write, vma))) {
		bad_area_access_error(regs, error_code, address);
		return;
	}

	/*
	 * If for any reason at all we couldn't handle the fault,
	 * make sure we exit gracefully rather than endlessly redo
	 * the fault:
	 */
	fault = handle_mm_fault(mm, vma, address, flags);

	if (unlikely(fault & (VM_FAULT_RETRY|VM_FAULT_ERROR))) {
		if (mm_fault_error(regs, error_code, address, fault))
			return;
	}

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

	check_v8086_mode(regs, address, tsk);

	up_read(&mm->mmap_sem);
}
```