# 5.6 実例編

ptrace_notify でデバッガにイベントを通知する

 * SIGTRAP を siginfo_t にのせて飛ばす

```c
void ptrace_notify(int exit_code)
{
	siginfo_t info;

	BUG_ON((exit_code & (0x7f | ~0xffff)) != SIGTRAP);

	memset(&info, 0, sizeof info);
	info.si_signo = SIGTRAP;
	info.si_code = exit_code;
	info.si_pid = task_pid_vnr(current);
	info.si_uid = current_uid();

	/* Let the debugger run.  */
	spin_lock_irq(&current->sighand->siglock);
	ptrace_stop(exit_code, 1, &info);
	spin_unlock_irq(&current->sighand->siglock);
}
```