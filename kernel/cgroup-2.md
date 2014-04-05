# cgroup

## tasks で ENOSPC

```
Warning: cannot write tid 4185 to /cgroup/cpuset/hetemluser/sandbag//tasks:No space left on device
Warning: cgroup_attach_task_pid failed: 50016
Warning: failed to apply the rule. Error was: 50016
Cgroup change for PID: 4185, UID: 1025, GID: 1000, PROCNAME: /usr/bin/curl FAILED! (Error Code: 50016)
Warning: cannot write tid 4187 to /cgroup/cpuset/hetemluser/sandbag//tasks:No space left on device
```

tasks のエントリポイント

```c
/*
 * for the common functions, 'private' gives the type of file
 */
/* for hysterical raisins, we can't put this on the older files */
#define CGROUP_FILE_GENERIC_PREFIX "cgroup."
static struct cftype files[] = {
	{
		.name = "tasks",
		.open = cgroup_tasks_open,
		.write_u64 = cgroup_tasks_write,
		.release = cgroup_pidlist_release,
		.mode = S_IRUGO | S_IWUSR,
	},
```

cgroup_procs_write で pid を追加する

```c
static int cgroup_procs_write(struct cgroup *cgrp, struct cftype *cft, u64 tgid)
{
	int ret;
	do {
		/*
		 * attach_proc fails with -EAGAIN if threadgroup leadership
		 * changes in the middle of the operation, in which case we need
		 * to find the task_struct for the new leader and start over.
		 */
		ret = attach_task_by_pid(cgrp, tgid, true);
	} while (ret == -EAGAIN);
	return ret;
}
```

attach_task_by_pid

 * vpid
   * Virtual PID ?
   * pid namespace を挟んでいるので PID が実PID かどうか分からない場合に使う

```c
/*
 * Find the task_struct of the task to attach by vpid and pass it along to the
 * function to attach either it or all tasks in its threadgroup. Will take
 * cgroup_mutex; may take task_lock of task.
 */
static int attach_task_by_pid(struct cgroup *cgrp, u64 pid, bool threadgroup)
{
	struct task_struct *tsk;
	const struct cred *cred = current_cred(), *tcred;
	int ret;

	if (!cgroup_lock_live_group(cgrp))
		return -ENODEV;

	if (pid) {
		rcu_read_lock();
		tsk = find_task_by_vpid(pid);
		if (!tsk) {
			rcu_read_unlock();
			cgroup_unlock();
			return -ESRCH;
		}
		if (threadgroup) {
			/*
			 * RCU protects this access, since tsk was found in the
			 * tid map. a race with de_thread may cause group_leader
			 * to stop being the leader, but cgroup_attach_proc will
			 * detect it later.
			 */
			tsk = tsk->group_leader;
		} else if (tsk->flags & PF_EXITING) {
			/* optimization for the single-task-only case */
			rcu_read_unlock();
			cgroup_unlock();
			return -ESRCH;
		}

		/*
		 * even if we're attaching all tasks in the thread group, we
		 * only need to check permissions on one of them.
		 */
		tcred = __task_cred(tsk);
		if (cred->euid &&
		    cred->euid != tcred->uid &&
		    cred->euid != tcred->suid) {
			rcu_read_unlock();
			cgroup_unlock();
			return -EACCES;
		}
		get_task_struct(tsk);
		rcu_read_unlock();
	} else {
		if (threadgroup)
			tsk = current->group_leader;
		else
			tsk = current;
		get_task_struct(tsk);
	}

	if (threadgroup) {
		threadgroup_fork_write_lock(tsk);
		ret = cgroup_attach_proc(cgrp, tsk);
		threadgroup_fork_write_unlock(tsk);
	} else {
		ret = cgroup_attach_task(cgrp, tsk);
	}
	put_task_struct(tsk);
	cgroup_unlock();
	return ret;
}
```