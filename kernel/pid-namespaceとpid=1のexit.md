# docker/コンテナ というか、pid namespace を pid = 1 なプロセスが exit した際の挙動

 * pid namespace を切っている際に、pid = 1 のプロセスが exit すると、同じ namespace に属するプロセスに SIGKILL が飛ぶ
 * docker の挙動ではなくて、カーネルの仕様

## 再現する

再現用の状況を作るため。 docker で bash 起動した後に、 setsid で、端末を切り離したプロセスを作る

```
# setsid sleep 1000
```

ps で見るとこんな感じ。 

```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.1  18116  2000 ?        Ss   13:57   0:00 bash
root        20  0.0  0.0   4292   564 ?        Ss   13:57   0:00 sleep 10000
```

bash と sleep は親子関係に無い。

次に、外部のコンテナから、 sleep プロセスを strace する。strace が成功したら、コンテナの bash を exit する

```
$ sudo strace -p $( pgrep sleep )
Process 5678 attached - interrupt to quit
restart_syscall(<... resuming interrupted call ...> <unfinished ...>

# docker の bash を exit する と …

+++ killed by SIGKILL +++
```

sleep プロセスに SIGKILL が飛んできていることが確認できる

## SIGKILL はどこから飛んでくるか?

カーネルが飛ばす。exit(2) から追っていくと、たどり着ける

```c
SYSCALL_DEFINE1(exit, int, error_code)
{
	do_exit((error_code&0xff)<<8);
}
```

 * => NORET_TYPE void do_exit(long code)
 * => static void exit_notify(struct task_struct *tsk, int group_dead)
 * => static void forget_original_parent(struct task_struct *father)
 * => static struct task_struct *find_new_reaper(struct task_struct *father)

と潜っていく

#### static struct task_struct *find_new_reaper(struct task_struct *father)

child_reaper = 親プロセスがいなくなった際に、代理の親となるプロセス (namespace を使わない場合は pid = 1 の init )

```c
/*
 * When we die, we re-parent all our children.
 * Try to give them to another thread in our thread
 * group, and if no such member exists, give it to
 * the child reaper process (ie "init") in our pid
 * space.
 */
static struct task_struct *find_new_reaper(struct task_struct *father)
{
	struct pid_namespace *pid_ns = task_active_pid_ns(father);
	struct task_struct *thread;

	thread = father;
	while_each_thread(father, thread) {
		if (thread->flags & PF_EXITING)
			continue;
		if (unlikely(pid_ns->child_reaper == father))
			pid_ns->child_reaper = thread;
		return thread;
	}

	if (unlikely(pid_ns->child_reaper == father)) {
		write_unlock_irq(&tasklist_lock);
		if (unlikely(pid_ns == &init_pid_ns))
			panic("Attempted to kill init!");

		zap_pid_ns_processes(pid_ns);
		write_lock_irq(&tasklist_lock);

//…
```

#### void zap_pid_ns_processes(struct pid_namespace *pid_ns)

pid_namespace に属するタスクに SIGKILL を飛ばして止める

```c
void zap_pid_ns_processes(struct pid_namespace *pid_ns)
{
	int nr;
	int rc;
	struct task_struct *task;

	/*
	 * The last thread in the cgroup-init thread group is terminating.
	 * Find remaining pid_ts in the namespace, signal and wait for them
	 * to exit.
	 *
	 * Note:  This signals each threads in the namespace - even those that
	 * 	  belong to the same thread group, To avoid this, we would have
	 * 	  to walk the entire tasklist looking a processes in this
	 * 	  namespace, but that could be unnecessarily expensive if the
	 * 	  pid namespace has just a few processes. Or we need to
	 * 	  maintain a tasklist for each pid namespace.
	 *
	 */
	read_lock(&tasklist_lock);
	nr = next_pidmap(pid_ns, 1);
	while (nr > 0) {
		rcu_read_lock();

		/*
		 * Use force_sig() since it clears SIGNAL_UNKILLABLE ensuring
		 * any nested-container's init processes don't ignore the
		 * signal
		 */
		task = pid_task(find_vpid(nr), PIDTYPE_PID);
		if (task)
			force_sig(SIGKILL, task);

		rcu_read_unlock();

		nr = next_pidmap(pid_ns, nr);
	}
	read_unlock(&tasklist_lock);

//…
```