# mount --rbind

--rbind ってどやって実装されてるの?

## /bin/mount ソース

mount は util-linux-ng-2.17.2 に入ってる

```
mount/mount.c:  { "rbind",	0, 0, MS_BIND|MS_REC }, /* Idem, plus mounted subtrees */
```

**MS_BIND|MS_REC** が正解らしい MS_REC は ___recursive___

## カーネル

 * http://wiki.bit-hive.com/north/pg/mount%A5%AA%A5%D7%A5%B7%A5%E7%A5%F3 も参考に

## mount(2) 

```c 
SYSCALL_DEFINE5(mount, char __user *, dev_name, char __user *, dir_name,
		char __user *, type, unsigned long, flags, void __user *, data)
{
	int ret;
	char *kernel_type;
	struct filename *kernel_dir;
	char *kernel_dev;
	unsigned long data_page;

	ret = copy_mount_string(type, &kernel_type);
	if (ret < 0)
		goto out_type;

	kernel_dir = getname(dir_name);
	if (IS_ERR(kernel_dir)) {
		ret = PTR_ERR(kernel_dir);
		goto out_dir;
	}

	ret = copy_mount_string(dev_name, &kernel_dev);
	if (ret < 0)
		goto out_dev;

	ret = copy_mount_options(data, &data_page);
	if (ret < 0)
		goto out_data;

	ret = do_mount(kernel_dev, kernel_dir->name, kernel_type, flags,
		(void *) data_page);

	free_page(data_page);
out_data:
	kfree(kernel_dev);
out_dev:
	putname(kernel_dir);
out_dir:
	kfree(kernel_type);
out_type:
	return ret;
}
``` 

## do_mount

 * MS_REC の有無で **do_loopback** を再帰的にするかどうかを決める
 * MS_BIND は loopback 扱い?

```c
long do_mount(char *dev_name, const char *dir_name, char *type_page,
		  unsigned long flags, void *data_page)
{
	struct path path;
	int retval = 0;
	int mnt_flags = 0;
 
//

 	else if (flags & MS_BIND)
		retval = do_loopback(&path, dev_name, flags & MS_REC);
```        

MS_REC を指定した場合は **copy_tree** に繋がる

```c
/*
 * do loopback mount.
 */
static int do_loopback(struct path *path, char *old_name,
				int recurse)
{

//

	if (recurse)
		mnt = copy_tree(old_path.mnt, old_path.dentry, 0);
```

## copy_tree

強そうなので後で読む

```c
struct vfsmount *copy_tree(struct vfsmount *mnt, struct dentry *dentry,
					int flag)
{
	struct vfsmount *res, *p, *q, *r, *s;
	struct path path;

	if (!(flag & CL_COPY_ALL) && IS_MNT_UNBINDABLE(mnt))
		return NULL;

	res = q = clone_mnt(mnt, dentry, flag);
	if (!q)
		goto Enomem;
	q->mnt_mountpoint = mnt->mnt_mountpoint;

	p = mnt;
	list_for_each_entry(r, &mnt->mnt_mounts, mnt_child) {
		if (!is_subdir(r->mnt_mountpoint, dentry))
			continue;

		for (s = r; s; s = next_mnt(s, r)) {
			if (!(flag & CL_COPY_ALL) && IS_MNT_UNBINDABLE(s)) {
				s = skip_mnt_tree(s);
				continue;
			}
			while (p != s->mnt_parent) {
				p = p->mnt_parent;
				q = q->mnt_parent;
			}
			p = s;
			path.mnt = q;
			path.dentry = p->mnt_mountpoint;
			q = clone_mnt(p, p->mnt_root, flag);
			if (!q)
				goto Enomem;
			spin_lock(&vfsmount_lock);
			list_add_tail(&q->mnt_list, &res->mnt_list);
			attach_mnt(q, &path);
			spin_unlock(&vfsmount_lock);
		}
	}
	return res;
Enomem:
	if (res) {
		LIST_HEAD(umount_list);
		spin_lock(&vfsmount_lock);
		umount_tree(res, 0, &umount_list);
		spin_unlock(&vfsmount_lock);
		release_mounts(&umount_list);
	}
	return NULL;
}
```