# relatime

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