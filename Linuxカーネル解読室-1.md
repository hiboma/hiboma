## 第1章

http://sourceforge.jp/projects/linux-kernel-docs/wiki/1.1%E3%80%80マルチタスク

## 1.1 マルチタスク

>Linuxカーネル2.6におけるプロセススケジューリングの方針は、Linuxカーネル2.4のそれとは大きな違いはありません。しかし、その実装は、Linuxカーネル2.4のものから全面的に書き直されました

 * ___プロセススケジューラ___
   * O(1) ってあるけど 2.4 のスケジューラってどんなんだったの?

## 1.2 プロセスとは?

>そのプロセス固有のコンテキストを持ちます。コンテキストとは、そのプロセスが動作するためのプロセス空間、そのプロセスが動作するときのレジスタ値などです。

 * ___コンテキスト___ とは?
   * task_struct *task が管理する 
     * プロセス空間 mm_struct *task->mm 
       * スレッドでプロセス空間の共有
       * 「共有」 => mm_struct の切り替えをする必要がない
       * カーネルスレッドは mm_struct が NULL
     * 各種レジスタ
       * レジスタがCPUごとにあるのを図示がよさそ

## 1.3 プロセス切り替え

TODO: x86アーキテクチャ依存の図であることを確認取る
TODO: 別のアーキテクチャだとどんなんか? 

 * ___プロセスディスパッチ、プロセスディスパッチャー___
   * プログラムカウンタレジスタ = EIP, RIP
   * スタックポインタ = ESP, EBP
   * 特殊レジスタ = CR3 Page Directory Base Registe

OpenBSDのページだけど http://caspar.hazymoon.jp/OpenBSD/annex/intel_arc.html にレジスタ一覧。
32bitでシンプルな方がとっつきは楽そう

> これらコンテキストをtask_struct構造体やカーネルスタックに退避しておき

 * 退避 => メモリに書き込む (movl, pushl)

## 1.4 プロセスディスパッチャの実装

### 1.4.1 context_switch

 * ハードウェアの機能 TSS(タスク状態セグメント x86) を使用しない)

### context_switch

schedule の中で呼ばれるよ

 * mm_struct
   * メモリディスクリプタ
   * vm_area_struct, red-black木, セグメントのアドレス, ...
 * カーネルスレッドは current->mm が NULL

```c
/*
 * context_switch - switch to the new MM and the new
 * thread's register state.
 */
static inline

// 1. アドレス空間の切り替え
//  * カーネルスレッドの場合は active_mm のポインタを切り替えるだけ
//    * `borrowed`
//    * 必要ないけど、 active_mm を擬似的に埋めておくのかな?
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

#### context_switch -> switch_mm

 * プロセス空間 (アドレス空間?) の切り替え
   * 別プロセスの場合と、同一プロセスのスレッドの場合とが考えられる

 ```c
static inline void switch_mm(struct mm_struct *prev, struct mm_struct *next, 
			     struct task_struct *tsk)
{
	unsigned cpu = smp_processor_id();
    // 別のプロセスに変わる場合 ( スレッドの切り替えでない場合 )
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

        // cr3 レジスタに next->pgd を読み込む
        // この時点で TLB がフラッシュされる 
		load_cr3(next->pgd);

        // local descriptor table 
		if (unlikely(next->context.ldt != prev->context.ldt)) 
			load_LDT_nolock(&next->context, cpu);
	}
#ifdef CONFIG_SMP
	else {
    // prev == next で同じ mm_struct を差している場合
    // 同一プロセスのスレッドの場合だと mm_struct が一緒になりうる
		write_pda(mmu_state, TLBSTATE_OK);

		if (read_pda(active_mm) != next)
            // BUG() で死ぬ
			out_of_line_bug();

         // ???
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

 * プロセッサごとになんか構造体が用意されている
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

### context_switch -> switch_to マクロ

 * prev,next,last と三つあるのが難しい

```c
// pushfl と popfl が書いてないぞ ...
define switch_to(prev,next,last) do {					\
	unsigned long esi,edi;						\
              // EFLAGSレジスタをスタックに退避
              // pushfl
	asm volatile("pushl %%ebp\n\t"					\     // EBPレジスタを現在の prev の task_struct のカーネルスタックにpush
		     "movl %%esp,%0\n\t"	/* save ESP */		\ // prev->thread.esp = $esp prev プロセスのESPレジスタを退避
             
		     "movl %5,%%esp\n\t"	/* restore ESP */	\ // $esp = next->thread.esp next プロセスのESPレジスタを復帰
                                                          // この時点でカーネルスタックが next を差している => プロセスが切り替わり
		     "movl $1f,%1\n\t"		/* save EIP */		\ // preh->thread.eip = $1f
		     "pushl %6\n\t"		/* restore EIP */	\     // next のカーネルスタックに next->thread.eip を push
                                                          // next->thread.eip は $1f ラベルが指すアドレス
		     "jmp __switch_to\n"				\

		     "1:\t"						        \         // $1f が指すラベル
		     "popl %%ebp\n\t"					\         // EBPレジスタをカーネルスタックから復帰
             // popfl                                     // EFLAGSレジスタをカーねるスタックから復帰
		     :"=m" (prev->thread.esp),"=m" (prev->thread.eip),	\
		      "=a" (last),"=S" (esi),"=D" (edi)			\
		     :"m" (next->thread.esp),"m" (next->thread.eip),	\
		      "2" (prev), "d" (next));				\
} while (0)
```

#### 寄り道 fork(2)

> forkシステムコールによって生まれたばかりの子プロセスは、forkシステムコールの後半処理から動作を始めます。この子プロセスの__switch_to関数からの戻り番地として、forkシステムコールの後半処理を開始アドレスとしてEIPレジスタの退避域（thread.eip）に登録しておきます。

 * fork の場合 sys_fork -> do_fork -> copy_thread で子プロセスの EIP を別にセットする
   * copy_thread で thread.eip には `asmlinkage void ret_from_fork(void) __asm__("ret_from_fork");` をセットしている 
   * これによって親プロセスと子プロセスが再会する EIP が分離する

```c
int copy_thread(int nr, unsigned long clone_flags, unsigned long esp,
	unsigned long unused,
	struct task_struct * p, struct pt_regs * regs)
{
    // 子プロセスのEIPレジスタをセット
	p->thread.eip = (unsigned long) ret_from_fork;

```

p->thread.eip にセットされる ret_from_fork はアセンブラ

```asm
/*
 * A newly forked process directly context switches into this.
 */ 	
/* rdi:	prev */	
ENTRY(ret_from_fork)
	CFI_DEFAULT_STACK
	call schedule_tail
	GET_THREAD_INFO(%rcx)
	testl $(_TIF_SYSCALL_TRACE|_TIF_SYSCALL_AUDIT),threadinfo_flags(%rcx)
	jnz rff_trace
rff_action:	
	RESTORE_REST
	testl $3,CS-ARGOFFSET(%rsp)	# from kernel_thread?
	je   int_ret_from_sys_call
	testl $_TIF_IA32,threadinfo_flags(%rcx)
	jnz  int_ret_from_sys_call
	RESTORE_TOP_OF_STACK %rdi,ARGOFFSET
	jmp ret_from_sys_call
rff_trace:
	movq %rsp,%rdi
	call syscall_trace_leave
	GET_THREAD_INFO(%rcx)	
	jmp rff_action
	CFI_ENDPROC
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

    // task statement segment
	struct tss_struct *tss = &per_cpu(init_tss, cpu);

	/* never put a printk in __switch_to... printk() calls wake_up*() indirectly */
	__unlazy_fpu(prev_p);

```

### ___unlazy_fpu

>__unlazy_fpu関数は、呼び出された瞬間にはFPUレジスタを切り替えません。FPUレジスタには大きなレジスタが複数存在し、レジスタ値の退避/復帰にかかるコストが大きいため、少々トリッキーな手段を使って性能劣化を緩和しています。

FPU = Floating Point Unit 浮動小数点レジスタ

 * thread_info->status に FPU を使用したかどうかのフラグ TS_USEDFPU を持つ
    * save_init_fpu -> __save_init_fpu で [fnsave, fwait](http://softwaretechnique.jp/OS_Development/Tips/IA32_X87_Instructions/FSAVE.html), [fxsave, fnclex](http://softwaretechnique.jp/OS_Development/Tips/IA32_X87_Instructions/FCLEX.html) とかいう命令呼ぶ
    * FPU, FPUフラグ例外を退避したりクリアしたり
    * 遅延させた場合にどんな例外がでる?
      * EFLAGS の EMビットが 1 の際に浮動小数命令を実行するとデバイス使用不可能例外(#NM) が出る

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

扶桑小数点命令を実行したに出るデバイス使用不可能例外のハンドラ

 ```asm
ENTRY(device_not_available)
	RING0_INT_FRAME
	pushl $-1			# mark this as an int
	CFI_ADJUST_CFA_OFFSET 4
	SAVE_ALL
    # CR0 レジスタを取る
	movl %cr0, %eax
    # EMビット
	testl $0x4, %eax		# EM (math emulation bit)
	jne device_not_available_emulate
	preempt_stop
    # ここで浮動小数点の復帰
	call math_state_restore
	jmp ret_from_exception
device_not_available_emulate:
	pushl $0			# temporary storage for ORIG_EIP
	CFI_ADJUST_CFA_OFFSET 4
	call math_emulate
	addl $4, %esp
	CFI_ADJUST_CFA_OFFSET -4
	jmp ret_from_exception
	CFI_ENDPROC
```

```c
	/*
	 * Reload esp0.
	 */
     // カーネルスタックのアドレスを tss->esp0 に保持
	load_esp0(tss, next);
```

 ```c
static inline void load_esp0(struct tss_struct *tss, struct thread_struct *thread)
{
    // task statement segment に esp0 を退避?
	tss->esp0 = thread->esp0;
	/* This can only happen when SEP is enabled, no need to test "SEP"arately */
	if (unlikely(tss->ss1 != thread->sysenter_cs)) {
		tss->ss1 = thread->sysenter_cs;
        // MSR = Model Specfic Register モデル固有レジスタ 
        // http://mcn.oops.jp/wiki/index.php?CPU%2FMSR
        // wrmsr はモデル固有レジスタに書き込む命令
		wrmsr(MSR_IA32_SYSENTER_CS, thread->sysenter_cs, 0);
	}
}
```

```c
	/*
	 * Save away %fs and %gs. No need to save %es and %ds, as
	 * those are always kernel segments while inside the kernel.
	 * Doing this before setting the new TLS descriptors avoids
	 * the situation where we temporarily have non-reloadable
	 * segments in %fs and %gs.  This could be an issue if the
	 * NMI handler ever used %fs or %gs (it does not today), or
	 * if the kernel is running inside of a hypervisor layer.
	 */
	savesegment(fs, prev->fs);  // mov %%fs,  prev->fs してるだけ
	savesegment(gs, prev->gs);  // mov %%gfs, prev->gs してるだけ

	/*
	 * Load the per-thread Thread-Local Storage descriptor.
	 */
    // GDT で実装されてる?
	load_TLS(next, cpu);
```    

 * TLS は GDT を使って実装されている
 * per_cpu がついてるので GDT って CPU ごとに保持されてる?

 ```c
static inline void load_TLS(struct thread_struct *t, unsigned int cpu)
{
#define C(i) get_cpu_gdt_table(cpu)[GDT_ENTRY_TLS_MIN + i] = t->tls_array[i]
	C(0); C(1); C(2);
#undef C
}
```

次のプロセスの fs と gs を復帰。

 ```c
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

IOPL = I/O特権レベル

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
    // http://en.wikipedia.org/wiki/Debug_register
    // デバッグレジスタを使うことでハードウェアブレークポイントが使える
    // デバッガ用のレジスタ
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
 
#### context switch の回数はどこで見れる?

 * sar -W で見れるよ
```
[vagrant@vagrant-centos65 ~]$ sar -w 1 1000
Linux 2.6.32-431.el6.x86_64 (vagrant-centos65.vagrantup.com)    02/06/14        _x86_64_        (1 CPU)

23:17:21       proc/s   cswch/s
23:17:22         0.00     70.41
23:17:23         0.00     72.00
23:17:24         0.00     71.72
23:17:25         1.03    170.10
23:17:26         0.00    122.11
23:17:27         1.18   1571.76  # find / したら一気に数値上がる, read/write, ...
23:17:28         0.00   3633.80  # 割り込みコンテキストから復帰の際にスイッチ?
23:17:29         0.00   2367.90  # ttyへの書き込みの際にもスイッチ?
23:17:30         0.00   2840.74
```

 * /proc/stat で取れる
   * ctxt が全CPUを加算した数値
```
cpu  19504 274 37370 6426181 14123 3191 9799 0 0
cpu0 19504 274 37370 6426181 14123 3191 9799 0 0
intr 1536233 516 159 0 0 0 0 0 0 0 0 0 0 116 0 0 0 0 0 0 69287 14881 20253 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
ctxt 8162633
btime 1391661893
processes 3707
procs_running 1
procs_blocked 0
softirq 11516172 0 999181 13159 9016972 19519 0 162 0 50333 1416846
```

 * `proc_misc.c:407:		"\nctxt %llu\n"`, context_switches で数値取っている
   * schedule(void) の中で context_switch する前に 	`rq->nr_switches++;` してインクリメントしている
   * cpu_rq(i) => runqueue_t の数値なので CPUごとに増えてく数値 (CPU単位でコンテキストスイッチするからそらそうだ)

```c
unsigned long long nr_context_switches(void)
{
	unsigned long long i, sum = 0;

	for_each_cpu(i)
		sum += cpu_rq(i)->nr_switches;

	return sum;
}
```

### 1.4.2 switch_to マクロ

 * GCCインラインアセンブラは下記を読んで理解しよう
   * http://caspar.hazymoon.jp/OpenBSD/annex/gcc_inline_asm.html
 * thread_struct
   * アーキテクチャ依存なので、ジェネリックなコードでは thread.eip など出てこんよ
   *  thread.eip, thread.esp 以外のメンバ
```c
struct thread_struct {
/* cached TLS descriptors. */ // スレッドローカルストレージ?
	struct desc_struct tls_array[GDT_ENTRY_TLS_ENTRIES];
    // カーネルスタックのベースポインタ???
	unsigned long	esp0;
	unsigned long	sysenter_cs;
	unsigned long	eip;
	unsigned long	esp;
    // ???
	unsigned long	fs;
	unsigned long	gs;
/* Hardware debugging registers */
	unsigned long	debugreg[8];  /* %%db0-7 debug registers */
/* fault info */
    // cr2 ... ページフォルト例外を検出した際のアドレス
	unsigned long	cr2, trap_no, error_code;
/* floating point info */
    // 浮動小数点レジスタを退避
	union i387_union	i387;
/* virtual 86 mode info */
	struct vm86_struct __user * vm86_info;
	unsigned long		screen_bitmap;
	unsigned long		v86flags, v86mask, saved_esp0;
	unsigned int		saved_fs, saved_gs;
/* IO permissions */
	unsigned long	*io_bitmap_ptr;
 	unsigned long	iopl;
/* max allowed port in the bitmap, in bytes: */
	unsigned long	io_bitmap_max;
};
```

### 1.4.3 switch_to 関数

 * FPUCレジスタの遅延きりかえ
   * 例外の内容は?

>ところで、一見FPUレジスタの退避処理も遅延させられそうに思えますが、なぜ遅延させていないのでしょうか？

 * 「マルチプロセッサの場合退避処理の遅延が難しい」
   * CPUごとにFPUレジスタがあり、他のCPUでスケジューリングされる場合、どうやって FPUレジスタを壊さず移動させるのか?問題
   * どっかに退避しておかないと無理そう
 * ___TLS___ [スレッドローカルストレージ](http://ja.wikipedia.org/wiki/スレッド局所記憶#Pthreads_.E3.81.A7.E3.81.AE.E5.AE.9F.E8.A3.85)
   * Pthread実装 pthread_key_create, pthread_setspecific, pthread_key_delete
   * `C言語では C11 からキーワード _Thread_local を用いて TLS を使用できる`
   * __thread

プロセス空間を共有している => スタック以外スレッド間でメモリ共有している => 破壊しうる ってのを確認してから
どうやって スレッド固有のデータを管理したらいいか? で TLS を引き合いに出す

### 1.4.3 汎用レジスタの退避

>ここまで見てきて気が付いた人もいると思いますが、汎用レジスタはいつ切り替えたのでしょうか？　実は、Intel x86ではこのタイミングで切り替えることは不要です。必要な情報はすでにスタック上に退避されています。

 * eax, ebx, ...
 * タイマ割り込みが発生した時点で退避されてるんだっけ?
   * schdule() を呼び出すまでのカーネルパスを逆に辿って割り込みや例外になった時点で退避されてるはず
 * arch/i386/kernel/entry.S に割り込み/例外ハンドラが定義されてる
 * x86系の場合 ハンドラが自前で汎用レジスタを退避する SAVE_ALL を見ると分かる

#### SAVE_ALL の中身

i386の実装を見てみる

``` asm
#define SAVE_ALL \
	cld; \          // EFLAGSレジスタのDFフラグをクリアします
                    // DFフラグが0にセットされいる間は、文字列（バイト配列）操作を行うと、
                    // インデックスレジスタ（ESIまたはEDI、あるいは両方）がインクリメントされます
                    // via http://softwaretechnique.jp/OS_Development/Tips/IA32_Instructions/CLD.html
	pushl %es; \
	pushl %ds; \
	pushl %eax; \
	pushl %ebp; \
	pushl %edi; \
	pushl %esi; \
	pushl %edx; \
	pushl %ecx; \
	pushl %ebx; \
	movl $(__USER_DS), %edx; \
	movl %edx, %ds; \
	movl %edx, %es;
```

割り込みハンドラ(ハードウェア割り込みかソフトウェア割り込みかは区別されていない)) での使われかた

```asm 
common_interrupt:
	SAVE_ALL
	movl %esp,%eax
	call do_IRQ
	jmp ret_from_intr
```

システムコールの例外ハンドラでの使われかた

```asm
	# system call handler stub
ENTRY(system_call)
	pushl %eax			# save orig_eax
	SAVE_ALL
	GET_THREAD_INFO(%ebp)
					# system call tracing in operation / emulation
	/* Note, _TIF_SECCOMP is bit number 8, and so it needs testw and not testb */
	testw $(_TIF_SYSCALL_EMU|_TIF_SYSCALL_TRACE|_TIF_SECCOMP|_TIF_SYSCALL_AUDIT),TI_flags(%ebp)
	jnz syscall_trace_entry
	cmpl $(nr_syscalls), %eax
	jae syscall_badsys
syscall_call:
	call *sys_call_table(,%eax,4)
	movl %eax,EAX(%esp)		# store the return value
syscall_exit:
	cli				# make sure we don't miss an interrupt
					# setting need_resched or sigpending
					# between sampling and the iret
	movl TI_flags(%ebp), %ecx
	testw $_TIF_ALLWORK_MASK, %cx	# current->work
	jne syscall_exit_work
```

ついでにページフォルトの例外ハンドラを見る

```asm
KPROBE_ENTRY(page_fault)
	pushl $do_page_fault
	jmp error_code
	.previous .text
```

## まとめ

 * レジスタの種類を整理
   * 汎用レジスタ
     * eax, ebx, ecx, edx, ... eip, esp
   * ___EFLAGSレジスタ___
     * pushfl, popfl
     * http://en.wikipedia.org/wiki/FLAGS_register
     * http://d.hatena.ne.jp/yamanetoshi/20060608/1149772551
   * ___FPUレジスタ___
   * ___特権レジスタ___
   * ___セグメントセレクタ___
   * ___CR3制御レジスタ___
     * ページテーブルの検索を開始するアドレス(ページディレクトリの物理アドレス)をいれとく
     * CR3 を書き変えると TLB はフラッシュされる (コスト高い) => MMUの情報を更新
       * 逆に遅延させるのを lazy TLB と呼ぶ
     * ところで CR2 レジスタは 例外発生時のアドレスを保持するらしい
 * ___TSS___ Task Statement Segment
 * ___TLB___ Translation Lookaside Buffer
   * リニアドレス -> 物理アドレスの変換キャッシュ
   * 各々のCPUローカル
 * mm_struct -> pgd
   * ページグローバルディレクトリ
   * http://www.xml.com/ldd/chapter/book/figs/ldr2_1302.gif の図
 * [Linux x86インラインアセンブラー](http://www.ibm.com/developerworks/jp/linux/library/l-ia/)
 * tss_struct の使われかたがよく分からん
 * gs, fs セグメント何?

## 寄り道

 * mm_struct の pgd 

```
pgd_t *pgd_alloc(struct mm_struct *mm)
{
	pgd_t *pgd;
	pmd_t *pmds[PREALLOCATED_PMDS];

    // ページグローバルディレクトリは page そのもの
	pgd = (pgd_t *)__get_free_page(PGALLOC_GFP);

	if (pgd == NULL)
		goto out;

	mm->pgd = pgd;

	if (preallocate_pmds(pmds) != 0)
		goto out_free_pgd;

	if (paravirt_pgd_alloc(mm) != 0)
		goto out_free_pmds;

	/*
	 * Make sure that pre-populating the pmds is atomic with
	 * respect to anything walking the pgd_list, so that they
	 * never see a partially populated pgd.
	 */
	spin_lock(&pgd_lock);

	pgd_ctor(mm, pgd);
	pgd_prepopulate_pmd(mm, pgd, pmds);

	spin_unlock(&pgd_lock);

	return pgd;

out_free_pmds:
	free_pmds(pmds);
out_free_pgd:
	free_page((unsigned long)pgd);
out:
	return NULL;
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
