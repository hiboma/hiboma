# SIGSEGV

```
$ ./owata 
＼(^o^)／
＼(^o^)／
＼(^o^)／
Segmentation fault
```

## sysctl debug.exception-trace

```
static struct ctl_table debug_table[] = {
#if defined(CONFIG_X86) || defined(CONFIG_PPC)
	{
		.ctl_name	= CTL_UNNUMBERED,
		.procname	= "exception-trace",
		.data		= &show_unhandled_signals,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec_minmax,
		.extra1		= &zero,
	},
```

## kernel.print-fatal-signals

```
sudo sysctl -w kernel.print-fatal-signals=1
```

```
Jul  6 04:01:43 vagrant-centos65 kernel: a.out[25311]: segfault at 0 ip 0000000000400546 sp 00007fff2fb08610 error 4 in a.out[400000+1000]
Jul  6 04:01:43 vagrant-centos65 kernel: a.out/25311: potentially unexpected fatal signal 11.
Jul  6 04:01:43 vagrant-centos65 kernel: 
Jul  6 04:01:43 vagrant-centos65 kernel: CPU 0 
Jul  6 04:01:43 vagrant-centos65 kernel: Modules linked in: ipt_addrtype xt_conntrack iptable_filter ipt_MASQUERADE iptable_nat nf_nat nf_conntrack_ipv4 nf_conntrack nf_defrag_ipv4 ip_tables bridge stp llc dm_thin_pool dm_bio_prison dm_persistent_data dm_bufio libcrc32c vboxsf(U) ipv6 ppdev parport_pc parport sg i2c_piix4 i2c_core vboxguest(U) virtio_net ext4 jbd2 mbcache sd_mod crc_t10dif ahci virtio_pci virtio_ring virtio dm_mirror dm_region_hash dm_log dm_mod [last unloaded: scsi_wait_scan]
Jul  6 04:01:43 vagrant-centos65 kernel: 
Jul  6 04:01:43 vagrant-centos65 kernel: Pid: 25311, comm: a.out Tainted: G           --------------- H  2.6.32-431.el6.x86_64 #1 innotek GmbH VirtualBox/VirtualBox
Jul  6 04:01:43 vagrant-centos65 kernel: RIP: 0033:[<0000000000400546>]  [<0000000000400546>] 0x400546
Jul  6 04:01:43 vagrant-centos65 kernel: RSP: 002b:00007fff2fb08610  EFLAGS: 00010202
Jul  6 04:01:43 vagrant-centos65 kernel: RAX: 0000000000000000 RBX: 0000000000000000 RCX: 00007ff900c7ecc0
Jul  6 04:01:43 vagrant-centos65 kernel: RDX: 0000000000000000 RSI: 0000000000000000 RDI: 00007fff2fb085f0
Jul  6 04:01:43 vagrant-centos65 kernel: RBP: 00007fff2fb08620 R08: 000000000000000b R09: 00007ff90117b700
Jul  6 04:01:43 vagrant-centos65 kernel: R10: 00007fff2fb08390 R11: 0000000000000246 R12: 0000000000400420
Jul  6 04:01:43 vagrant-centos65 kernel: R13: 00007fff2fb08720 R14: 0000000000000000 R15: 0000000000000000
Jul  6 04:01:43 vagrant-centos65 kernel: FS:  00007ff90117b700(0000) GS:ffff880002200000(0000) knlGS:0000000000000000
Jul  6 04:01:43 vagrant-centos65 kernel: CS:  0010 DS: 0000 ES: 0000 CR0: 000000008005003b
Jul  6 04:01:43 vagrant-centos65 kernel: CR2: 0000000000000000 CR3: 000000003bdab000 CR4: 00000000000006f0
Jul  6 04:01:43 vagrant-centos65 kernel: DR0: 0000000000000000 DR1: 0000000000000000 DR2: 0000000000000000
Jul  6 04:01:43 vagrant-centos65 kernel: DR3: 0000000000000000 DR6: 00000000ffff4ff0 DR7: 0000000000000400
Jul  6 04:01:43 vagrant-centos65 kernel: Process a.out (pid: 25311, threadinfo ffff88003bd56000, task ffff88003c7d8aa0)
Jul  6 04:01:43 vagrant-centos65 kernel: 
Jul  6 04:01:43 vagrant-centos65 kernel: Call Trace:
```

## bad_area

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

##

```c
static void
__bad_area_nosemaphore(struct pt_regs *regs, unsigned long error_code,
		       unsigned long address, int si_code)
{
	struct task_struct *tsk = current;

	/* User mode accesses just cause a SIGSEGV */
	if (error_code & PF_USER) {
		/*
		 * It's possible to have interrupts off here:
		 */
		local_irq_enable();

		/*
		 * Valid to do another page fault here because this one came
		 * from user space:
		 */
		if (is_prefetch(regs, error_code, address))
			return;

		if (is_errata100(regs, address))
			return;

		if (unlikely(show_unhandled_signals))
			show_signal_msg(regs, error_code, address, tsk);

		/* Kernel addresses are always protection faults: */
		tsk->thread.cr2		= address;
		tsk->thread.error_code	= error_code | (address >= TASK_SIZE);
		tsk->thread.trap_no	= 14;

		force_sig_info_fault(SIGSEGV, si_code, address, tsk, 0);

		return;
	}

	if (is_f00f_bug(regs, address))
		return;

	no_context(regs, error_code, address);
}
```

## force_sig_info_fault

```c
static void
force_sig_info_fault(int si_signo, int si_code, unsigned long address,
		     struct task_struct *tsk, int fault)
{
	unsigned lsb = 0;
	siginfo_t info;

	info.si_signo	= si_signo;
	info.si_errno	= 0;
	info.si_code	= si_code;
	info.si_addr	= (void __user *)address;
	if (fault & VM_FAULT_HWPOISON_LARGE)
		lsb = hstate_index_to_shift(VM_FAULT_GET_HINDEX(fault)); 
	if (fault & VM_FAULT_HWPOISON)
		lsb = PAGE_SHIFT;
	info.si_addr_lsb = lsb;

	force_sig_info(si_signo, &info, tsk);
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