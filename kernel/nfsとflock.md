# NFS と flock(2)

ソースは神妙な理由で 2.6.18

## TODO

 * statd, lockd

## strct file_operations

nfs_file_operations の .flock が flock(2) の concrete method

```
const struct file_operations nfs_file_operations = {
	.llseek		= nfs_file_llseek,
	.read		= do_sync_read,
	.write		= do_sync_write,
	.aio_read		= nfs_file_read,
	.aio_write		= nfs_file_write,
	.mmap		= nfs_file_mmap,
	.open		= nfs_file_open,
	.flush		= nfs_file_flush,
	.release	= nfs_file_release,
	.fsync		= nfs_fsync,
	.lock		= nfs_lock,
	.flock		= nfs_flock,
	.sendfile	= nfs_file_sendfile,
	.check_flags	= nfs_check_flags,
};
```

## LOCK_* => FL_*

LOCK_SH, LOCK_EX, LOCK_UN は flock_translate_cmd でカーネル内部の定数に変換される

```
static inline int flock_translate_cmd(int cmd) {
	if (cmd & LOCK_MAND)
		return cmd & (LOCK_MAND | LOCK_RW);
	switch (cmd) {
	case LOCK_SH:
		return F_RDLCK;
	case LOCK_EX:
		return F_WRLCK;
	case LOCK_UN:
		return F_UNLCK;
	}
	return -EINVAL;
}
```

flock_translate_cmd は flock_make_lock で呼び出しする

```c
/* Fill in a file_lock structure with an appropriate FLOCK lock. */
static int flock_make_lock(struct file *filp, struct file_lock **lock,
		unsigned int cmd)
{
	struct file_lock *fl;
	int type = flock_translate_cmd(cmd);
	if (type < 0)
		return type;
	
	fl = locks_alloc_lock();
	if (fl == NULL)
		return -ENOMEM;

	fl->fl_file = filp;
	fl->fl_pid = current->tgid;
	fl->fl_flags = FL_FLOCK;
	fl->fl_type = type;
	fl->fl_end = OFFSET_MAX;
	
	*lock = fl;
	return 0;
}
```

## nfs_flock

sys_flock は file->f_op->flock でファイルシステムごとの flock 実装を呼び出す

flock の場合は FL_FLOCK が立っている。FL_POSIX と区別するため?

```c
/**
 *	sys_flock: - flock() system call.
 *	@fd: the file descriptor to lock.
 *	@cmd: the type of lock to apply.
 *
 *	Apply a %FL_FLOCK style lock to an open file descriptor.
 *	The @cmd can be one of
 *
 *	%LOCK_SH -- a shared lock.
 *
 *	%LOCK_EX -- an exclusive lock.
 *
 *	%LOCK_UN -- remove an existing lock.
 *
 *	%LOCK_MAND -- a `mandatory' flock.  This exists to emulate Windows Share Modes.
 *
 *	%LOCK_MAND can be combined with %LOCK_READ or %LOCK_WRITE to allow other
 *	processes read and write access respectively.
 */
asmlinkage long sys_flock(unsigned int fd, unsigned int cmd)
{
//...

	if (filp->f_op && filp->f_op->flock)
		error = filp->f_op->flock(filp,
					  (can_sleep) ? F_SETLKW : F_SETLK,
					  lock);
	else
		error = flock_lock_file_wait(filp, lock);
```

NFS は nfs_flock が実装

 * LOCK_UN => do_unlk
 * LOCK_EX => do_setlk

の呼び出しになる 

```c
/*
 * Lock a (portion of) a file
 */
static int nfs_flock(struct file *filp, int cmd, struct file_lock *fl)
{
	dprintk("NFS: nfs_flock(f=%s/%ld, t=%x, fl=%x)\n",
			filp->f_dentry->d_inode->i_sb->s_id,
			filp->f_dentry->d_inode->i_ino,
			fl->fl_type, fl->fl_flags);

	/*
	 * No BSD flocks over NFS allowed.
	 * Note: we could try to fake a POSIX lock request here by
	 * using ((u32) filp | 0x80000000) or some such as the pid.
	 * Not sure whether that would be unique, though, or whether
	 * that would break in other places.
	 */
	if (!(fl->fl_flags & FL_FLOCK))
		return -ENOLCK;

	/* We're simulating flock() locks using posix locks on the server */
	fl->fl_owner = (fl_owner_t)filp;
	fl->fl_start = 0;
	fl->fl_end = OFFSET_MAX;

	if (fl->fl_type == F_UNLCK)
		return do_unlk(filp, cmd, fl);
	return do_setlk(filp, cmd, fl);
}
```

## do_setlk

```c
static int do_setlk(struct file *filp, int cmd, struct file_lock *fl)
{
	struct inode *inode = filp->f_mapping->host;
	int status;

	/*
	 * Flush all pending writes before doing anything
	 * with locks..
	 */
	status = nfs_sync_mapping(filp->f_mapping);
	if (status != 0)
		goto out;

	lock_kernel();
	/* Use local locking if mounted with "-onolock" */
	if (!(NFS_SERVER(inode)->flags & NFS_MOUNT_NONLM)) {
		status = NFS_PROTO(inode)->lock(filp, cmd, fl);
		/* If we were signalled we still need to ensure that
		 * we clean up any state on the server. We therefore
		 * record the lock call as having succeeded in order to
		 * ensure that locks_remove_posix() cleans it out when
		 * the process exits.
		 */
		if (status == -EINTR || status == -ERESTARTSYS)
			do_vfs_lock(filp, fl);
	} else
		status = do_vfs_lock(filp, fl);
	unlock_kernel();
	if (status < 0)
		goto out;
	/*
	 * Make sure we clear the cache whenever we try to get the lock.
	 * This makes locking act as a cache coherency point.
	 */
	nfs_sync_mapping(filp->f_mapping);
	nfs_zap_caches(inode);
out:
	return status;
}
```