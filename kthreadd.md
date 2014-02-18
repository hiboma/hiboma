# kthreadd

カーネルスレッド作る君

```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         2  0.0  0.0      0     0 ?        S    Feb14   0:00 [kthreadd]
root         3  0.0  0.0      0     0 ?        S    Feb14   0:00  \_ [migration/0]
root         4  0.0  0.0      0     0 ?        S    Feb14   0:12  \_ [ksoftirqd/0]
root         5  0.0  0.0      0     0 ?        S    Feb14   0:00  \_ [migration/0]
root         6  0.0  0.0      0     0 ?        S    Feb14   0:00  \_ [watchdog/0]
root         7  0.0  0.0      0     0 ?        S    Feb14   0:00  \_ [migration/1]
root         8  0.0  0.0      0     0 ?        S    Feb14   0:00  \_ [migration/1]
root         9  0.0  0.0      0     0 ?        S    Feb14   0:01  \_ [ksoftirqd/1]
root        10  0.0  0.0      0     0 ?        S    Feb14   0:00  \_ [watchdog/1]
root        11  0.0  0.0      0     0 ?        S    Feb14   0:00  \_ [migration/2]
```

## APIs

 * set_task_comm
 * wake_up_process(kthreadd_task);
 * wait_for_completion(&create.done) => complete(&create->done);
 * set_cpus_allowed_ptr
 * set_mems_allowed
 * set_task_comm
 * ignore_signals

## kthreadd - kthread を作る側

```c
int kthreadd(void *unused)
{
	struct task_struct *tsk = current;

	/* Setup a clean context for our children to inherit. */
    // スピンロックとって comm に strlcpy するだけ
	set_task_comm(tsk, "kthreadd");
    
    // シグナルハンドラを全て SIG_IGN にする
    // 受信したシグナルも全て flush_signal 
	ignore_signals(tsk);

    // cpu_all_mask なので全CPUでスケジューリング可能
	set_cpus_allowed_ptr(tsk, cpu_all_mask);
    // HIGE_MEMORY ? 
	set_mems_allowed(node_states[N_HIGH_MEMORY]);

	current->flags |= PF_NOFREEZE | PF_FREEZER_NOSIG;

	for (;;) {
		set_current_state(TASK_INTERRUPTIBLE);

        // kthread_create_list が空なら何もせずスケジューラ呼ぶ
        // kthread_create_list は kthread_run -> kthread_create が追加するリスト
		if (list_empty(&kthread_create_list))
			schedule();
		__set_current_state(TASK_RUNNING);

		spin_lock(&kthread_create_lock);
		while (!list_empty(&kthread_create_list)) {
			struct kthread_create_info *create;

            // 作成要求のリストから取り出し
			create = list_entry(kthread_create_list.next,
					    struct kthread_create_info, list);
			list_del_init(&create->list);
			spin_unlock(&kthread_create_lock);

            // スレッド作る君
			create_kthread(create);

			spin_lock(&kthread_create_lock);
		}
		spin_unlock(&kthread_create_lock);
	}

	return 0;
}
```

```c
static void create_kthread(struct kthread_create_info *create)
{
	int pid;

	/* We want our own signal handler (we take no signals by default). */
	pid = kernel_thread(kthread, create, CLONE_FS | CLONE_FILES | SIGCHLD);
	if (pid < 0) {
		create->result = ERR_PTR(pid);
        // スレッド作成をリクエストした側を起こす
		complete(&create->done);
	}
}
```

 * 32bit用

```c
/*
 * Create a kernel thread
 */
int kernel_thread(int (*fn)(void *), void *arg, unsigned long flags)
{
	struct pt_regs regs;

	memset(&regs, 0, sizeof(regs));

	regs.bx = (unsigned long) fn;
	regs.dx = (unsigned long) arg;

	regs.ds = __USER_DS;
	regs.es = __USER_DS;
	regs.fs = __KERNEL_PERCPU;
	regs.gs = __KERNEL_STACK_CANARY;
	regs.orig_ax = -1;
    // eip をセットしている
	regs.ip = (unsigned long) kernel_thread_helper;
	regs.cs = __KERNEL_CS | get_kernel_rpl();
	regs.flags = X86_EFLAGS_IF | X86_EFLAGS_SF | X86_EFLAGS_PF | 0x2;

	/* Ok, create the new process.. */
    // カーネルスレッドも do_fork で生成するのかー!    
	return do_fork(flags | CLONE_VM | CLONE_UNTRACED, 0, &regs, 0, NULL, NULL);
}
EXPORT_SYMBOL(kernel_thread);
```

## kthread_create - スレッド作成の要求を出す側

```c
/**
 * kthread_create - create a kthread.
 * @threadfn: the function to run until signal_pending(current).
 * @data: data ptr for @threadfn.
 * @namefmt: printf-style name for the thread.
 *
 * Description: This helper function creates and names a kernel
 * thread.  The thread will be stopped: use wake_up_process() to start
 * it.  See also kthread_run(), kthread_create_on_cpu().
 *
 * When woken, the thread will run @threadfn() with @data as its
 * argument. @threadfn() can either call do_exit() directly if it is a
 * standalone thread for which noone will call kthread_stop(), or
 * return when 'kthread_should_stop()' is true (which means
 * kthread_stop() has been called).  The return value should be zero
 * or a negative error number; it will be passed to kthread_stop().
 *
 * Returns a task_struct or ERR_PTR(-ENOMEM).
 */
struct task_struct *kthread_create(int (*threadfn)(void *data),
				   void *data,
				   const char namefmt[],
				   ...)
{
	struct kthread_create_info create;

	create.threadfn = threadfn;
	create.data = data;
	init_completion(&create.done);

	spin_lock(&kthread_create_lock);
	list_add_tail(&create.list, &kthread_create_list);
	spin_unlock(&kthread_create_lock);

    // kthreadd を起こす
	wake_up_process(kthreadd_task);
    // リストに追加したスレッドを kthreadd が作るのを待つ
    // create.done の wait はどこで解除される?
	wait_for_completion(&create.done);

	if (!IS_ERR(create.result)) {
		struct sched_param param = { .sched_priority = 0 };
		va_list args;

		va_start(args, namefmt);
		vsnprintf(create.result->comm, sizeof(create.result->comm),
			  namefmt, args);
		va_end(args);
		/*
		 * root may have changed our (kthreadd's) priority or CPU mask.
		 * The kernel thread should not inherit these properties.
		 */
		sched_setscheduler_nocheck(create.result, SCHED_NORMAL, &param);
		set_cpus_allowed_ptr(create.result, cpu_all_mask);
	}
	return create.result;
}
EXPORT_SYMBOL(kthread_create);
```