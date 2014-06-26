# NFS と flock(2)

ソースは神妙な理由で 2.6.18

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

## nfs_flock

flock の場合は FL_FLOCK が立っている。 FL_POSIX と区別するため?

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