# vfork(2)

fork との違いを確認しよう

## sys_vfork

arch/x86/kernel/process.c で定義されているよ

```c
/*
 * This is trivial, and on the face of it looks like it
 * could equally well be done in user mode.
 *
 * Not so, for quite unobvious reasons - register pressure.
 * In user mode vfork() cannot have a stack frame, and if
 * done by calling the "clone()" system call directly, you
 * do not have enough call-clobbered registers to hold all
 * the information you need.
 */
int sys_vfork(struct pt_regs *regs)
{
	return do_fork(CLONE_VFORK | CLONE_VM | SIGCHLD, regs->sp, regs, 0,
		       NULL, NULL);
}
```

sys_fork も arch/x86/kernel/process.c で定義されているよ

```c
/* arch/x86/kernel/process.c */
int sys_fork(struct pt_regs *regs)
{
	return do_fork(SIGCHLD, regs->sp, regs, 0, NULL, NULL);
}
```

## vfork(2) と fork(2) の clone(2) フラグの違い

clone を呼び出しているのは fork(2) と同じになるが

 * CLONE_VFORK
 * CLONE_VM

フラグをたてっているのが違う

## CLONE_VFORK の参照可所

```c
/*
 * This creates a new process as a copy of the old one,
 * but does not actually start it yet.
 *
 * It copies the registers, and all the appropriate
 * parts of the process environment (as per the clone
 * flags). The actual kick-off is left to the caller.
 */
static struct task_struct *copy_process(unsigned long clone_flags,
					unsigned long stack_start,
					struct pt_regs *regs,
					unsigned long stack_size,
					int __user *child_tidptr,
					struct pid *pid,
					int trace)
{

//...
                    
	/*
	 * sigaltstack should be cleared when sharing the same VM
	 */
	if ((clone_flags & (CLONE_VM|CLONE_VFORK)) == CLONE_VM)
		p->sas_ss_sp = p->sas_ss_size = 0;

//...
		if (clone_flags & CLONE_VFORK) {
			p->vfork_done = &vfork;
			init_completion(&vfork);
		}

//...
		if (clone_flags & CLONE_VFORK) {
			freezer_do_not_count();
			wait_for_completion(&vfork);
			freezer_count();
			tracehook_report_vfork_done(p, nr);
		}
```

## CLONE_VM の参照可所

CLONE_VM が立っていると mm_struct を親と共有したままにする

 * dup_mm を省略する。コストが省かれるのはこれか?
 * 仮想アドレスの構成によってコストの変動率が左右されてそう

```c
static int copy_mm(unsigned long clone_flags, struct task_struct * tsk)
{
	struct mm_struct * mm, *oldmm;
	int retval;

//...

	if (clone_flags & CLONE_VM) {
		atomic_inc(&oldmm->mm_users);
		mm = oldmm;
		goto good_mm;
	}

	retval = -ENOMEM;
	mm = dup_mm(tsk);
	if (!mm)
		goto fail_nomem;

good_mm:
	/* Initializing for Swap token stuff */
	mm->token_priority = 0;
	mm->last_interval = 0;
	if (tsk->signal->oom_score_adj == OOM_SCORE_ADJ_MIN)
		atomic_inc(&mm->oom_disable_count);

	tsk->mm = mm;
	tsk->active_mm = mm;
	return 0;

fail_nomem:
	return retval;
}
```

## dup_mm

```c
/*
 * Allocate a new mm structure and copy contents from the
 * mm structure of the passed in task structure.
 */
struct mm_struct *dup_mm(struct task_struct *tsk)
{
	struct mm_struct *mm, *oldmm = current->mm;
	int err;

	if (!oldmm)
		return NULL;

	mm = allocate_mm();
	if (!mm)
		goto fail_nomem;

	memcpy(mm, oldmm, sizeof(*mm));

	/* Initializing for Swap token stuff */
	mm->token_priority = 0;
	mm->last_interval = 0;

#ifdef CONFIG_TRANSPARENT_HUGEPAGE
	mm->pmd_huge_pte = NULL;
#endif

	if (!mm_init(mm, tsk))
		goto fail_nomem;

	if (init_new_context(tsk, mm))
		goto fail_nocontext;

	dup_mm_exe_file(oldmm, mm);

	err = dup_mmap(mm, oldmm);
	if (err)
		goto free_pt;

	mm->hiwater_rss = get_mm_rss(mm);
	mm->hiwater_vm = mm->total_vm;

	if (mm->binfmt && !try_module_get(mm->binfmt->module))
		goto free_pt;

	return mm;

free_pt:
	/* don't put binfmt in mmput, we haven't got module yet */
	mm->binfmt = NULL;
	mmput(mm);

fail_nomem:
	return NULL;

fail_nocontext:
	/*
	 * If init_new_context() failed, we cannot use mmput() to free the mm
	 * because it calls destroy_context()
	 */
	mm_free_pgd(mm);
	free_mm(mm);
	return NULL;
}
```