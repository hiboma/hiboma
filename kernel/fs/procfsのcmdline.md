# procfs の /proc/$pid/cmdline

```c
static const struct pid_entry tgid_base_stuff[] = {
//...
	INF("cmdline",    S_IRUGO, proc_pid_cmdline),
```

proc_pid_cmdline がハンドラとして動く

```c
static int proc_pid_cmdline(struct task_struct *task, char * buffer)
{
	int res = 0;
	unsigned int len;
    /* get_task_mm は spinlock 取る */
	struct mm_struct *mm = get_task_mm(task);
	if (!mm)
		goto out;
	if (!mm->arg_end)
		goto out_mm;	/* Shh! No looking before we're done */

 	len = mm->arg_end - mm->arg_start;
 
	if (len > PAGE_SIZE)
		len = PAGE_SIZE;

    /* spinlock, down_read */
	res = access_process_vm(task, mm->arg_start, buffer, len, 0);

	// If the nul at the end of args has been overwritten, then
	// assume application is using setproctitle(3).
	if (res > 0 && buffer[res-1] != '\0' && len < PAGE_SIZE) {
		len = strnlen(buffer, res);
		if (len < res) {
		    res = len;
		} else {
			len = mm->env_end - mm->env_start;
			if (len > PAGE_SIZE - res)
				len = PAGE_SIZE - res;
			res += access_process_vm(task, mm->env_start, buffer+res, len, 0);
			res = strnlen(buffer, res);
		}
	}
out_mm:
	mmput(mm);
out:
	return res;
}
```

cmdline のページは、以下の範囲に収まっている. pmap / smaps で見た場合の stack に収まっているはず

 * argv[] の始端アドレス 〜 argv[] の終端アドレス

```
 	len = mm->arg_end - mm->arg_start;
```

