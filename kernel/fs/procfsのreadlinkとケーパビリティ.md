# procfsのreadlinkとケーパビリティ.md

/proc/$pid/exe の symlink を readlink するには、まさかの CAP_SYS_PTACE が必要なのである

## ポイント

 * readlink は、ファイルシステム固有の実装を取る
 * procfs は、 readlink を proc_pid_readlink で実装している
 * proc_pid_readlink は、実行タスクに CAP_SYS_PTACE が無い場合に EPERM を返す

## procfs の readlink

readlink は proc_pid_readlink で実装されている

```c
static const struct inode_operations proc_pid_link_inode_operations = {
	.readlink	= proc_pid_readlink,
	.follow_link	= proc_pid_follow_link,
	.setattr	= proc_setattr,
};
```

```c
static int proc_pid_readlink(struct dentry * dentry, char __user * buffer, int buflen)
{
	int error = -EACCES;
	struct inode *inode = dentry->d_inode;
	struct path path;

	/* Are we allowed to snoop on the tasks file descriptors? */
	if (!proc_fd_access_allowed(inode))
		goto out;

	error = PROC_I(inode)->op.proc_get_link(inode, &path);
	if (error)
		goto out;

	error = do_proc_readlink(&path, buffer, buflen);
	path_put(&path);
out:
	return error;
}
```

```c
/* permission checks */
static int proc_fd_access_allowed(struct inode *inode)
{
	struct task_struct *task;
	int allowed = 0;
	/* Allow access to a task's file descriptors if it is us or we
	 * may use ptrace attach to the process and find out that
	 * information.
	 */
	task = get_proc_task(inode);
	if (task) {
		allowed = ptrace_may_access(task, PTRACE_MODE_READ);
		put_task_struct(task);
	}
	return allowed;
}
```

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

