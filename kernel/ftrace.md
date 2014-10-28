# sysctl kernel.ftrace_enabled 

## sysctl インタフェース

```c
#ifdef CONFIG_FUNCTION_TRACER
	{
		.ctl_name	= CTL_UNNUMBERED,
		.procname	= "ftrace_enabled",
		.data		= &ftrace_enabled,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= &ftrace_enable_sysctl,
	},
#endif
```

ftrace_enable_sysctl

```c
int
ftrace_enable_sysctl(struct ctl_table *table, int write,
		     void __user *buffer, size_t *lenp,
		     loff_t *ppos)
{
	int ret = -ENODEV;

	mutex_lock(&ftrace_lock);

	if (unlikely(ftrace_disabled))
		goto out;

	ret = proc_dointvec(table, write, buffer, lenp, ppos);

	if (ret || !write || (last_ftrace_enabled == !!ftrace_enabled))
		goto out;

	last_ftrace_enabled = !!ftrace_enabled;

	if (ftrace_enabled) {

		ftrace_startup_sysctl();

		/* we are starting ftrace again */
		if (ftrace_ops_list != &ftrace_list_end) {
			if (ftrace_ops_list->next == &ftrace_list_end)
				ftrace_trace_function = ftrace_ops_list->func;
			else
				ftrace_trace_function = ftrace_ops_list_func;
		}

	} else {
		/* stopping ftrace calls (just send to ftrace_stub) */
		ftrace_trace_function = ftrace_stub;

		ftrace_shutdown_sysctl();
	}

 out:
	mutex_unlock(&ftrace_lock);
	return ret;
}

#ifdef CONFIG_FUNCTION_GRAPH_TRACER
```