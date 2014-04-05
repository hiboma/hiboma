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