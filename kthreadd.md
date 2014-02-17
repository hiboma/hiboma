# kthreadd

qカーネルスレッド作る君

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

```c
int kthreadd(void *unused)
{
	struct task_struct *tsk = current;

	/* Setup a clean context for our children to inherit. */
	set_task_comm(tsk, "kthreadd");
	ignore_signals(tsk);
	set_cpus_allowed_ptr(tsk, cpu_all_mask);
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

			create = list_entry(kthread_create_list.next,
					    struct kthread_create_info, list);
			list_del_init(&create->list);
			spin_unlock(&kthread_create_lock);

			create_kthread(create);

			spin_lock(&kthread_create_lock);
		}
		spin_unlock(&kthread_create_lock);
	}

	return 0;
}
```