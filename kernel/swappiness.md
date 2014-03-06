## swappiness

定義されているのは kernel/sysctl.c。デフォルトは 60 よ

```
/*
 * From 0 .. 100.  Higher means more swappy.
 */
int vm_swappiness = 60;
```

```c
	{
		.ctl_name	= VM_SWAPPINESS,
		.procname	= "swappiness",
		.data		= &vm_swappiness,
		.maxlen		= sizeof(vm_swappiness),
		.mode		= 0644,
		.proc_handler	= &proc_dointvec_minmax,
		.strategy	= &sysctl_intvec,
		.extra1		= &zero,        // min = 0 
		.extra2		= &one_hundred, // max = 100
	},
```

[sysctl](https://github.com/hiboma/hiboma/tree/master/kernel_module_scratch/sysctl/)

cgroup ごとに swappiness を持つ

```c
static unsigned int get_swappiness(struct mem_cgroup *memcg)
{
	struct cgroup *cgrp = memcg->css.cgroup;
	unsigned int swappiness;

	/* root ? */
	if (cgrp->parent == NULL)
		return vm_swappiness;

	spin_lock(&memcg->reclaim_param_lock);
	swappiness = memcg->swappiness;
	spin_unlock(&memcg->reclaim_param_lock);

	return swappiness;
}
```
