# procfsのreadlinkとケーパビリティ.md

まさかの CAP_SYS_PTACE が必要なのである

```c
bool ptrace_may_access(struct task_struct *task, unsigned int mode)
{
	int err;
	task_lock(task);
	err = __ptrace_may_access(task, mode);
	task_unlock(task);
	return !err;
}
```

```c
int __ptrace_may_access(struct task_struct *task, unsigned int mode)
{
	const struct cred *cred = current_cred(), *tcred;

	/* May we inspect the given task?
	 * This check is used both for attaching with ptrace
	 * and for allowing access to sensitive information in /proc.
	 *
	 * ptrace_attach denies several cases that /proc allows
	 * because setting up the necessary parent/child relationship
	 * or halting the specified task is impossible.
	 */
	int dumpable = 0;
	/* Don't let security modules deny introspection */
	if (same_thread_group(task, current))
		return 0;
	rcu_read_lock();
	tcred = __task_cred(task);
	if ((cred->uid != tcred->euid ||
	     cred->uid != tcred->suid ||
	     cred->uid != tcred->uid  ||
	     cred->gid != tcred->egid ||
	     cred->gid != tcred->sgid ||
	     cred->gid != tcred->gid) &&
	    !capable(CAP_SYS_PTRACE)) {
		rcu_read_unlock();
		return -EPERM;
	}
	rcu_read_unlock();
	smp_rmb();
	if (task->mm)
		dumpable = get_dumpable(task->mm);
	if (!dumpable && !capable(CAP_SYS_PTRACE))
		return -EPERM;

	return security_ptrace_access_check(task, mode);
}
```

