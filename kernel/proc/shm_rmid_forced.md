# /proc/sys/kernel/shm_rmid_forced

## man 7 proc

> /proc/sys/kernel/shm_rmid_forced (Linux 3.1 以降)
> 
> If this file is set to 1, all System V shared memory segments will be marked for destruction as soon as the number of attached processes falls to zero; in other words, it is no longer possible to create shared memory segments that exist independently of any attached process.
The effect is as though a shmctl(2) IPC_RMID is performed on all existing segments as well as all segments created in the future (until this file is reset to 0). Note that existing segments that are attached to no process will be immediately destroyed when this file is set to 1. Setting this option will also destroy segments that were created, but never attached, upon termination of the process that created the segment with shmget(2).
Setting this file to 1 provides a way of ensuring that all System V shared memory segments are counted against the resource usage and resource limits (see the description of RLIMIT_AS in getrlimit(2)) of at least one process.
Because setting this file to 1 produces behavior that is nonstandard and could also break existing applications, the default value in this file is 0. Only set this file to 1 if you have a good understanding of the semantics of the applications using System V shared memory on your system.
>
> https://linuxjm.osdn.jp/html/LDP_man-pages/man5/proc.5.html

 * **shmctl(2)** で **IPC_RMID** しているのと同じことをやってくれる
 * `echo 1 > /proc/sys/kernel/shm_rmid_forced` すると `nattach 0` のセグメントを同期的にに消せる
 * システムワイドに作用するので、見知らぬところで既存のアプリに副作用を及ぼす可能性がある

## definition

linux-3.10.0-327.el7.centos.x86_64

```c
static struct ctl_table ipc_kern_table[] = {

/* ... */

	{
		.procname	= "shm_rmid_forced",
		.data		= &init_ipc_ns.shm_rmid_forced,
		.maxlen		= sizeof(init_ipc_ns.shm_rmid_forced),
		.mode		= 0644,
		.proc_handler	= proc_ipc_dointvec_minmax_orphans,
		.extra1		= &zero,
		.extra2		= &one,
	},
```

## proc_handler

 * `0` か `1` のみ write できる
 * `1` を write すると、 `shm_destroy_orphaned` を呼び出す

```c
static int proc_ipc_dointvec_minmax_orphans(ctl_table *table, int write,
	void __user *buffer, size_t *lenp, loff_t *ppos)
{
	struct ipc_namespace *ns = current->nsproxy->ipc_ns;
	int err = proc_ipc_dointvec_minmax(table, write, buffer, lenp, ppos);

	if (err < 0)
		return err;
	if (ns->shm_rmid_forced)
		shm_destroy_orphaned(ns);
	return err;
}
```

## shm_destroy_orphaned

現在の namespace 内の共有メモリセグメントをイテレートして `shm_try_destroy_orphaned` を呼び出す

```c
void shm_destroy_orphaned(struct ipc_namespace *ns)
{
	down_write(&shm_ids(ns).rwsem);
	if (shm_ids(ns).in_use)
		idr_for_each(&shm_ids(ns).ipcs_idr, &shm_try_destroy_orphaned, ns);
	up_write(&shm_ids(ns).rwsem);
}
```

## shm_try_destroy_orphaned

 * shm_may_destroy でセグメントが破棄できるかどうかを評価する

```c
/* Called with ns->shm_ids(ns).rwsem locked */
static int shm_try_destroy_orphaned(int id, void *p, void *data)
{
	struct ipc_namespace *ns = data;
	struct kern_ipc_perm *ipcp = p;
	struct shmid_kernel *shp = container_of(ipcp, struct shmid_kernel, shm_perm);

	/*
	 * We want to destroy segments without users and with already
	 * exit'ed originating process.
	 *
	 * As shp->* are changed under rwsem, it's safe to skip shp locking.
	 */
	if (shp->shm_creator != NULL)
		return 0;

	if (shm_may_destroy(ns, shp)) {
		shm_lock_by_ptr(shp);
		shm_destroy(ns, shp);
	}
	return 0;
}
```

## shm_may_destroy

 * shm_nattch が 0 (タスク? からの参照カウントが0) 
   * shm_rmdi_forced が 1 かどうか
   * shmctl(2) で IPC_RMID を呼び出して、SHM_DEST がたっているかどうか
     * DEST = destroy の略称

```
#define	SHM_DEST	01000	/* segment will be destroyed on last detach */
```

```c
/*
 * shm_may_destroy - identifies whether shm segment should be destroyed now
 *
 * Returns true if and only if there are no active users of the segment and
 * one of the following is true:
 *
 * 1) shmctl(id, IPC_RMID, NULL) was called for this shp
 *
 * 2) sysctl kernel.shm_rmid_forced is set to 1.
 */
static bool shm_may_destroy(struct ipc_namespace *ns, struct shmid_kernel *shp)
{
	return (shp->shm_nattch == 0) &&
	       (ns->shm_rmid_forced ||
		(shp->shm_perm.mode & SHM_DEST));
}
```

`(ns->shm_rmid_forced ||(shp->shm_perm.mode & SHM_DEST));` の条件で、 shmctl(2) + IPC_RMID と同等に扱われるのが確認できる
