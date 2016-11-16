# /proc/sys/kernel/shmmni

## man 2 shmget

> SHMMNI
>
> システム全体の共有メモリーセグメント数の上限値。 この上限値のデフォルトは、 Linux 2.2 以降では 128、 Linux 2.4 以降で 4096 である。
> Linux では、この上限値は /proc/sys/kernel/shmmni 経由で参照したり、変更したりできる。
>
> https://linuxjm.osdn.jp/html/LDP_man-pages/man2/shmget.2.html

## man 7 proc

>
> /proc/sys/kernel/shmmni (Linux 2.4 以降)
>   このファイルは、システム全体で作成可能な System V 共有メモリーセグメント数を指定する。
>
> https://linuxjm.osdn.jp/html/LDP_man-pages/man5/proc.5.html

## definition

```c
	{
		.procname	= "shmmni",
		.data		= &init_ipc_ns.shm_ctlmni,
		.maxlen		= sizeof (init_ipc_ns.shm_ctlmni),
		.mode		= 0644,
		.proc_handler	= proc_ipc_dointvec,
	},
```

## default value on CentOS7 

```c
$ sysctl kernel.shmmni
kernel.shmmni = 4096

$ uname -a
Linux *** 3.10.0-327.13.1.el7.x86_64 #1 SMP Thu Mar 31 16:04:38 UTC 2016 x86_64 x86_64 x86_64 GNU/Linux
```

## proc_handler

```c
static int proc_ipc_dointvec(ctl_table *table, int write,
	void __user *buffer, size_t *lenp, loff_t *ppos)
{
	struct ctl_table ipc_table;

	memcpy(&ipc_table, table, sizeof(ipc_table));
	ipc_table.data = get_ipc(table);

	return proc_dointvec(&ipc_table, write, buffer, lenp, ppos);
}
```

```c
void shm_init_ns(struct ipc_namespace *ns)
{
	ns->shm_ctlmax = SHMMAX;
	ns->shm_ctlall = SHMALL;
	ns->shm_ctlmni = SHMMNI;
	ns->shm_rmid_forced = 0;
	ns->shm_tot = 0;
	ipc_init_ids(&shm_ids(ns));
}
```

```c
/*
 * SHMMAX, SHMMNI and SHMALL are upper limits are defaults which can
 * be modified by sysctl.
 */

#define SHMMIN 1			 /* min shared seg size (bytes) */
#define SHMMNI 4096			 /* max num of segs system wide */
#define SHMMAX (ULONG_MAX - (1L<<24))	 /* max shared seg size (bytes) */
#define SHMALL (ULONG_MAX - (1L<<24))	 /* max shm system wide (pages) */
#define SHMSEG SHMMNI			 /* max shared segs per process */
```

## BUG ?

```
[vagrant@lb ~]$ sudo sysctl -w kernel.shmmni=-999
kernel.shmmni = -999

[vagrant@lb ~]$ sudo sysctl kernel.shmmni
kernel.shmmni = -999

[vagrant@lb ~]$ uname -a
Linux *** 3.10.0-123.20.1.el7.x86_64 #1 SMP Thu Jan 29 18:05:33 UTC 2015 x86_64 x86_64 x86_64 GNU/Linux
```