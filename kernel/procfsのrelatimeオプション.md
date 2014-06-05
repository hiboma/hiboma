# relatime

 * procfs のマウントオプションに relatime ついてるけど必要?

```
proc /proc proc rw,relatime 0 0
```

## MNT_RELATIME

```c
static void show_mnt_opts(struct seq_file *m, struct vfsmount *mnt)
{
        static const struct proc_fs_info mnt_info[] = {
                { MNT_NOSUID, ",nosuid" },
                { MNT_NODEV, ",nodev" },
                { MNT_NOEXEC, ",noexec" },
                { MNT_NOATIME, ",noatime" },
                { MNT_NODIRATIME, ",nodiratime" },
                { MNT_RELATIME, ",relatime" },
                { MNT_STRICTATIME, ",strictatime" },
                { 0, NULL }
        };   
        const struct proc_fs_info *fs_infop;

        for (fs_infop = mnt_info; fs_infop->flag; fs_infop++) {
                if (mnt->mnt_flags & fs_infop->flag)
                        seq_puts(m, fs_infop->str);
        }    
}
```

MNT_RELATIME で relatime_need_update の挙動が変わる

```c
/*
 * With relative atime, only update atime if the previous atime is
 * earlier than either the ctime or mtime or if at least a day has
 * passed since the last atime update.
 */
static int relatime_need_update(struct vfsmount *mnt, struct inode *inode,
			     struct timespec now)
{

	if (!(mnt->mnt_flags & MNT_RELATIME))
		return 1;
	/*
	 * Is mtime younger than atime? If yes, update atime:
	 */
	if (timespec_compare(&inode->i_mtime, &inode->i_atime) >= 0)
		return 1;
	/*
	 * Is ctime younger than atime? If yes, update atime:
	 */
	if (timespec_compare(&inode->i_ctime, &inode->i_atime) >= 0)
		return 1;

	/*
	 * Is the previous atime value older than a day? If yes,
	 * update atime:
	 */
	if ((long)(now.tv_sec - inode->i_atime.tv_sec) >= 24*60*60)
		return 1;
	/*
	 * Good, we can skip the atime update:
	 */
	return 0;
}
```

relatime_need_update は touch_atime 

```c
/**
 *	touch_atime	-	update the access time
 *	@mnt: mount the inode is accessed on
 *	@dentry: dentry accessed
 *
 *	Update the accessed time on an inode and mark it for writeback.
 *	This function automatically handles read only file systems and media,
 *	as well as the "noatime" flag and inode specific "noatime" markers.
 */
void touch_atime(struct vfsmount *mnt, struct dentry *dentry)
{
	struct inode *inode = dentry->d_inode;
	struct timespec now;

	if (inode->i_flags & S_NOATIME)
		return;
	if (IS_NOATIME(inode))
		return;
	if ((inode->i_sb->s_flags & MS_NODIRATIME) && S_ISDIR(inode->i_mode))
		return;

	if (mnt->mnt_flags & MNT_NOATIME)
		return;
	if ((mnt->mnt_flags & MNT_NODIRATIME) && S_ISDIR(inode->i_mode))
		return;

	now = current_fs_time(inode->i_sb);

    /* ここ */
	if (!relatime_need_update(mnt, inode, now))
		return;

	if (timespec_equal(&inode->i_atime, &now))
		return;

	if (!sb_start_write_trylock(inode->i_sb))
		return;

	if (__mnt_want_write(mnt))
		goto skip_update;

    /* i_atime を更新 */
	inode->i_atime = now;
	mark_inode_dirty_sync(inode);
	__mnt_drop_write(mnt);
skip_update:
	sb_end_write(inode->i_sb);
}
EXPORT_SYMBOL(touch_atime);
```