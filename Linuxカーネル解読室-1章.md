## 第1章

TODO
 * レジスタの種類を整理
   * 汎用レジスタ
     * eax, ebx, ecx, edx, ... eip, esp
   * EFLAGSレジスタ
     * pushfl, popfl
     * http://en.wikipedia.org/wiki/FLAGS_register
     * http://d.hatena.ne.jp/yamanetoshi/20060608/1149772551
   * FPUレジスタ
   * 特権レジスタ?
   * セグメントセレクタ
   * cr3制御レジスタ
     * ページテーブルの検索を開始するアドレス(ページディレクトリの物理アドレス)をいれとく
     * cr3 を書き変えると TLB はフラッシュされる
 * TLB Translation Lookaside Buffer
   * リニアドレス -> 物理アドレスの変換キャッシュ
   * 各々のCPUローカル
 * [Linux x86インラインアセンブラー](http://www.ibm.com/developerworks/jp/linux/library/l-ia/)

### context_switch

schedule の中で呼ばれるよ

 * mm_struct
   * メモリディスクリプタ
   * vm_area_struct, red-black木, セグメントのアドレス, ...
 * カーネルスレッドでは current->mm が NULL
 

```c
/*
 * context_switch - switch to the new MM and the new
 * thread's register state.
 */
static inline

// 1. アドレス空間の切り替え
//  * カーネルスレッドの場合は active_mm のポインタを切り替えるだけ
//  * 通常プロセスの場合は switch_mm で切り替え
// 2. プロセスの切り替え

// runqueue_t ... CPUごとの実行キュー
task_t * context_switch(runqueue_t *rq, task_t *prev, task_t *next)
{
	struct mm_struct *mm = next->mm;
	struct mm_struct *oldmm = prev->active_mm;

    // unlikely() とは?
    //   http://wiki.bit-hive.com/north/pg/likely%A4%C8unlikely
    //
    // if (!mm) として読んで OK
    // mm == NULL => prevタスクのメモリディスクリプタが NULL => 実行中のタスクがカーネルスレッドの場合を指す
	if (unlikely(!mm)) {
        // カーネルスレッドでは mm_struct を切り替える必要が無い (ページテーブルを変更しない)
        // というか、 mm_struct を共有する
        // カーネルスレッドは active_mm は有るけど、 mm は NULL
		next->active_mm = oldmm;
		atomic_inc(&oldmm->mm_count);

        // 遅延TLBモード
		enter_lazy_tlb(oldmm, next);
	} else
        // 次のタスクが普通のプロセスの場合、アドレス空間の切り替え
		switch_mm(oldmm, mm, next);

	if (unlikely(!prev->mm)) {
		prev->active_mm = NULL;
        // 後述
        // NULL になってない場合を見ているがどういうこと???
		WARN_ON(rq->prev_mm);
        // ?
		rq->prev_mm = oldmm;
	}

	/* Here we just switch the register state and the stack. */
	switch_to(prev, next, prev);

	return prev;
}
```

#### switch_mm

 ```c
static inline void switch_mm(struct mm_struct *prev, struct mm_struct *next, 
			     struct task_struct *tsk)
{
	unsigned cpu = smp_processor_id();
    // 別のプロセスに変わる場合    
	if (likely(prev != next)) {
		/* stop flush ipis for the previous mm */
		clear_bit(cpu, &prev->cpu_vm_mask);
#ifdef CONFIG_SMP
       // pda ... Perprocessor Datastructure Address?
       // mmu_state ???
		write_pda(mmu_state, TLBSTATE_OK);
        // CPU の active_mm を next に切り替え???
		write_pda(active_mm, next);
#endif
		set_bit(cpu, &next->cpu_vm_mask);

        // cr3 レジスタに next->pgd をセット
		load_cr3(next->pgd);

		if (unlikely(next->context.ldt != prev->context.ldt)) 
			load_LDT_nolock(&next->context, cpu);
	}
#ifdef CONFIG_SMP
	else {
		write_pda(mmu_state, TLBSTATE_OK);
		if (read_pda(active_mm) != next)
			out_of_line_bug();
		if(!test_and_set_bit(cpu, &next->cpu_vm_mask)) {
			/* We were in lazy tlb mode and leave_mm disabled 
			 * tlb flush IPI delivery. We must reload CR3
			 * to make sure to use no freed page tables.
			 */
			load_cr3(next->pgd);
			load_LDT_nolock(&next->context, cpu);
		}
	}
#endif
}
```

 ```c
/* Per processor datastructure. %gs points to it while the kernel runs */ 
struct x8664_pda {
	struct task_struct *pcurrent;	/* Current process */
	unsigned long data_offset;	/* Per cpu data offset from linker address */
	unsigned long kernelstack;  /* top of kernel stack for current */ 
	unsigned long oldrsp; 	    /* user rsp for system call */
        int irqcount;		    /* Irq nesting counter. Starts with -1 */  	
	int cpunumber;		    /* Logical CPU number */
	char *irqstackptr;	/* top of irqstack */
	int nodenumber;		    /* number of current node */
	unsigned int __softirq_pending;
	unsigned int __nmi_count;	/* number of NMI on this CPUs */
	struct mm_struct *active_mm;
	int mmu_state;     
	unsigned apic_timer_irqs;
} ____cacheline_aligned_in_smp;
```

 * cr3レジスタをセットすると TLB がフラッシュされるのでコスト高い

 ```c
static inline void load_cr3(pgd_t *pgd)
{
	asm volatile("movq %0,%%cr3" :: "r" (__pa(pgd)) : "memory");
}
```

#### WARN_ON

dump_stack で current のカーネルスタックを dump

 ```c
#ifndef HAVE_ARCH_WARN_ON
#define WARN_ON(condition) do { \
	if (unlikely((condition)!=0)) { \
		printk("Badness in %s at %s:%d\n", __FUNCTION__, __FILE__, __LINE__); \
		dump_stack(); \
	} \
} while (0)
#endif
```

### context_switch -> switch_to

```
// pushfl と popfl が書いてないぞ ...
#define switch_to(prev,next,last) do {					\
	unsigned long esi,edi;						\
              // pushfl                                   // EFLAGSレジスタをスタックに退避
	asm volatile("pushl %%ebp\n\t"					\     // EBPレジスタをカーネルスタックに退避
		     "movl %%esp,%0\n\t"	/* save ESP */		\ // prev->thread.esp = $esp　ESPレジスタを退避
		     "movl %5,%%esp\n\t"	/* restore ESP */	\ // $esp = next->thread.eip　EIPレジスタを復帰
		     "movl $1f,%1\n\t"		/* save EIP */		\ // preh->thread.epi = $1f
		     "pushl %6\n\t"		/* restore EIP */	\     // next->thread.epi ?
		     "jmp __switch_to\n"				\
		     "1:\t"						\
		     "popl %%ebp\n\t"					\         // EBPレジスタをカーネルスタックから復帰
             // popfl                                     // EFLAGSレジスタをカーねるスタックから復帰
		     :"=m" (prev->thread.esp),"=m" (prev->thread.eip),	\
		      "=a" (last),"=S" (esi),"=D" (edi)			\
		     :"m" (next->thread.esp),"m" (next->thread.eip),	\
		      "2" (prev), "d" (next));				\
} while (0)
```

### context_switch -> switch_to -> _switch_to

```c
/*
 *	switch_to(x,yn) should switch tasks from x to y.
 *
 * We fsave/fwait so that an exception goes off at the right time
 * (as a call from the fsave or fwait in effect) rather than to
 * the wrong process. Lazy FP saving no longer makes any sense
 * with modern CPU's, and this simplifies a lot of things (SMP
 * and UP become the same).
 *
 * NOTE! We used to use the x86 hardware context switching. The
 * reason for not using it any more becomes apparent when you
 * try to recover gracefully from saved state that is no longer
 * valid (stale segment register values in particular). With the
 * hardware task-switch, there is no way to fix up bad state in
 * a reasonable manner.
 *
 * The fact that Intel documents the hardware task-switching to
 * be slow is a fairly red herring - this code is not noticeably
 * faster. However, there _is_ some room for improvement here,
 * so the performance issues may eventually be a valid point.
 * More important, however, is the fact that this allows us much
 * more flexibility.
 *
 * The return value (in %eax) will be the "prev" task after
 * the task-switch, and shows up in ret_from_fork in entry.S,
 * for example.
 */
struct task_struct fastcall * __switch_to(struct task_struct *prev_p, struct task_struct *next_p)
{
	struct thread_struct *prev = &prev_p->thread,
				 *next = &next_p->thread;
	int cpu = smp_processor_id();
	struct tss_struct *tss = &per_cpu(init_tss, cpu);

	/* never put a printk in __switch_to... printk() calls wake_up*() indirectly */
	__unlazy_fpu(prev_p);
```

### ___unlazy_fpu

FPU = Floating Point Unit 浮動小数点レジスタ

 * thread_info->status に FPU を使用したかどうかのフラグ TS_USEDFPU を持つ
    * save_init_fpu -> __save_init_fpu で [fnsave, fwait](http://softwaretechnique.jp/OS_Development/Tips/IA32_X87_Instructions/FSAVE.html), [fxsave, fnclex](http://softwaretechnique.jp/OS_Development/Tips/IA32_X87_Instructions/FCLEX.html) とかいう命令呼ぶ
    * FPU, FPUフラグ例外を退避したりクリアしたり

 ```c
#define __unlazy_fpu( tsk ) do { \
	if ((tsk)->thread_info->status & TS_USEDFPU) \
		save_init_fpu( tsk ); \
} while (0)
```

 ```c
/*
 * These must be called with preempt disabled
 */
static inline void __save_init_fpu( struct task_struct *tsk )
{
	alternative_input(
		"fnsave %1 ; fwait ;" GENERIC_NOP2, // NOP ?
		"fxsave %1 ; fnclex",
		X86_FEATURE_FXSR,
		"m" (tsk->thread.i387.fxsave) // FPUレジスタ, FPU例外フラグを保存しとくメモリ
		:"memory");
	tsk->thread_info->status &= ~TS_USEDFPU;
}
```

 ```c
/*
 * Thread-synchronous status.
 *
 * This is different from the flags in that nobody else
 * ever touches our thread-synchronous status, so we don't
 * have to worry about atomic accesses.
 */
#define TS_USEDFPU		0x0001	/* FPU was used by this task this quantum (SMP) */
```

```c

	/*
	 * Reload esp0.
	 */
	load_esp0(tss, next);

	/*
	 * Save away %fs and %gs. No need to save %es and %ds, as
	 * those are always kernel segments while inside the kernel.
	 * Doing this before setting the new TLS descriptors avoids
	 * the situation where we temporarily have non-reloadable
	 * segments in %fs and %gs.  This could be an issue if the
	 * NMI handler ever used %fs or %gs (it does not today), or
	 * if the kernel is running inside of a hypervisor layer.
	 */
	savesegment(fs, prev->fs);
	savesegment(gs, prev->gs);

	/*
	 * Load the per-thread Thread-Local Storage descriptor.
	 */
    // GDT で実装されてる?
	load_TLS(next, cpu);

	/*
	 * Restore %fs and %gs if needed.
	 *
	 * Glibc normally makes %fs be zero, and %gs is one of
	 * the TLS segments.
	 */
	if (unlikely(prev->fs | next->fs))
		loadsegment(fs, next->fs);

	if (prev->gs | next->gs)
		loadsegment(gs, next->gs);
```

### loadsegment

 ```c
/*
 * Load a segment. Fall back on loading the zero
 * segment if something goes wrong..
 */
#define loadsegment(seg,value)			\
	asm volatile("\n"			\
		"1:\t"				\
		"mov %0,%%" #seg "\n"		\
		"2:\n"				\
		".section .fixup,\"ax\"\n"	\
		"3:\t"				\
		"pushl $0\n\t"			\
		"popl %%" #seg "\n\t"		\
		"jmp 2b\n"			\
		".previous\n"			\
		".section __ex_table,\"a\"\n\t"	\
		".align 4\n\t"			\
		".long 1b,3b\n"			\
		".previous"			\
		: :"rm" (value))
```

```
	/*
	 * Restore IOPL if needed.
	 */
	if (unlikely(prev->iopl != next->iopl))
		set_iopl_mask(next->iopl);
```

### set_iopl_mask

 * set I/O Plivilege Level
 * EFLAGS に指定した mask をかけて戻す?

 ```c
/*
 * Set IOPL bits in EFLAGS from given mask
 */
static inline void set_iopl_mask(unsigned mask)
{
	unsigned int reg;
	__asm__ __volatile__ ("pushfl;"
			      "popl %0;"
			      "andl %1, %0;"
			      "orl %2, %0;"
			      "pushl %0;"
			      "popfl"
				: "=&r" (reg)
				: "i" (~X86_EFLAGS_IOPL), "r" (mask));
}
```

```c
	/*
	 * Now maybe reload the debug registers
	 */
	if (unlikely(next->debugreg[7])) {
		set_debugreg(next->debugreg[0], 0);
		set_debugreg(next->debugreg[1], 1);
		set_debugreg(next->debugreg[2], 2);
		set_debugreg(next->debugreg[3], 3);
		/* no 4 and 5 */
		set_debugreg(next->debugreg[6], 6);
		set_debugreg(next->debugreg[7], 7);
	}

	if (unlikely(prev->io_bitmap_ptr || next->io_bitmap_ptr))
		handle_io_bitmap(next, tss);

	disable_tsc(prev_p, next_p);

	return prev_p;
}
```

### task_struct

```c
struct task_struct {
	volatile long state;	/* -1 unrunnable, 0 runnable, >0 stopped */
	struct thread_info *thread_info;
	atomic_t usage;
	unsigned long flags;	/* per process flags, defined below */
	unsigned long ptrace;

	int lock_depth;		/* BKL lock depth */

#if defined(CONFIG_SMP) && defined(__ARCH_WANT_UNLOCKED_CTXSW)
	int oncpu;
#endif
	int prio, static_prio;
	struct list_head run_list;
	prio_array_t *array;

	unsigned short ioprio;

	unsigned long sleep_avg;
	unsigned long long timestamp, last_ran;
	unsigned long long sched_time; /* sched_clock time spent running */
	int activated;

	unsigned long policy;
	cpumask_t cpus_allowed;
	unsigned int time_slice, first_time_slice;

#ifdef CONFIG_SCHEDSTATS
	struct sched_info sched_info;
#endif

	struct list_head tasks;
	/*
	 * ptrace_list/ptrace_children forms the list of my children
	 * that were stolen by a ptracer.
	 */
	struct list_head ptrace_children;
	struct list_head ptrace_list;

	struct mm_struct *mm, *active_mm;

/* task state */
	struct linux_binfmt *binfmt;
	long exit_state;
	int exit_code, exit_signal;
	int pdeath_signal;  /*  The signal sent when the parent dies  */
	/* ??? */
	unsigned long personality;
	unsigned did_exec:1;
	pid_t pid;
	pid_t tgid;
	/* 
	 * pointers to (original) parent process, youngest child, younger sibling,
	 * older sibling, respectively.  (p->father can be replaced with 
	 * p->parent->pid)
	 */
	struct task_struct *real_parent; /* real parent process (when being debugged) */
	struct task_struct *parent;	/* parent process */
	/*
	 * children/sibling forms the list of my children plus the
	 * tasks I'm ptracing.
	 */
	struct list_head children;	/* list of my children */
	struct list_head sibling;	/* linkage in my parent's children list */
	struct task_struct *group_leader;	/* threadgroup leader */

	/* PID/PID hash table linkage. */
	struct pid pids[PIDTYPE_MAX];

	struct completion *vfork_done;		/* for vfork() */
	int __user *set_child_tid;		/* CLONE_CHILD_SETTID */
	int __user *clear_child_tid;		/* CLONE_CHILD_CLEARTID */

	unsigned long rt_priority;
	cputime_t utime, stime;
	unsigned long nvcsw, nivcsw; /* context switch counts */
	struct timespec start_time;
/* mm fault and swap info: this can arguably be seen as either mm-specific or thread-specific */
	unsigned long min_flt, maj_flt;

  	cputime_t it_prof_expires, it_virt_expires;
	unsigned long long it_sched_expires;
	struct list_head cpu_timers[3];

/* process credentials */
	uid_t uid,euid,suid,fsuid;
	gid_t gid,egid,sgid,fsgid;
	struct group_info *group_info;
	kernel_cap_t   cap_effective, cap_inheritable, cap_permitted;
	unsigned keep_capabilities:1;
	struct user_struct *user;
#ifdef CONFIG_KEYS
	struct key *thread_keyring;	/* keyring private to this thread */
	unsigned char jit_keyring;	/* default keyring to attach requested keys to */
#endif
	int oomkilladj; /* OOM kill score adjustment (bit shift). */
	char comm[TASK_COMM_LEN]; /* executable name excluding path
				     - access with [gs]et_task_comm (which lock
				       it with task_lock())
				     - initialized normally by flush_old_exec */
/* file system info */
	int link_count, total_link_count;
/* ipc stuff */
	struct sysv_sem sysvsem;
/* CPU-specific state of this task */
	struct thread_struct thread;
/* filesystem information */
	struct fs_struct *fs;
/* open file information */
	struct files_struct *files;
/* namespace */
	struct namespace *namespace;
/* signal handlers */
	struct signal_struct *signal;
	struct sighand_struct *sighand;

	sigset_t blocked, real_blocked;
	struct sigpending pending;

	unsigned long sas_ss_sp;
	size_t sas_ss_size;
	int (*notifier)(void *priv);
	void *notifier_data;
	sigset_t *notifier_mask;
	
	void *security;
	struct audit_context *audit_context;
	seccomp_t seccomp;

/* Thread group tracking */
   	u32 parent_exec_id;
   	u32 self_exec_id;
/* Protection of (de-)allocation: mm, files, fs, tty, keyrings */
	spinlock_t alloc_lock;
/* Protection of proc_dentry: nesting proc_lock, dcache_lock, write_lock_irq(&tasklist_lock); */
	spinlock_t proc_lock;

/* journalling filesystem info */
	void *journal_info;

/* VM state */
	struct reclaim_state *reclaim_state;

	struct dentry *proc_dentry;
	struct backing_dev_info *backing_dev_info;

	struct io_context *io_context;

	unsigned long ptrace_message;
	siginfo_t *last_siginfo; /* For ptrace use.  */
/*
 * current io wait handle: wait queue entry to use for io waits
 * If this thread is processing aio, this points at the waitqueue
 * inside the currently handled kiocb. It may be NULL (i.e. default
 * to a stack based synchronous wait) if its doing sync IO.
 */
	wait_queue_t *io_wait;
/* i/o counters(bytes read/written, #syscalls */
	u64 rchar, wchar, syscr, syscw;
#if defined(CONFIG_BSD_PROCESS_ACCT)
	u64 acct_rss_mem1;	/* accumulated rss usage */
	u64 acct_vm_mem1;	/* accumulated virtual memory usage */
	clock_t acct_stimexpd;	/* clock_t-converted stime since last update */
#endif
#ifdef CONFIG_NUMA
  	struct mempolicy *mempolicy;
	short il_next;
#endif
#ifdef CONFIG_CPUSETS
	struct cpuset *cpuset;
	nodemask_t mems_allowed;
	int cpuset_mems_generation;
#endif
	atomic_t fs_excl;	/* holding fs exclusive resources */
};
```
