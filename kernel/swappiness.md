## swappiness

定義されているのは kernel/sysctl.c

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