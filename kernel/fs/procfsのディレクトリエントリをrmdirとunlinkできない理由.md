# procfs のディレクトリエントリを rmdir と unlink できない理由.md

inode->i_flags に S_IMMUTABLE が立っているので EPERM を返す

```c
static struct dentry *proc_pid_instantiate(struct inode *dir,
					   struct dentry * dentry,
					   struct task_struct *task, const void *ptr)
{
	struct dentry *error = ERR_PTR(-ENOENT);
	struct inode *inode;

	inode = proc_pid_make_inode(dir->i_sb, task);
	if (!inode)
		goto out;

	inode->i_mode = S_IFDIR|S_IRUGO|S_IXUGO;
	inode->i_op = &proc_tgid_base_inode_operations;
	inode->i_fop = &proc_tgid_base_operations;
    /* これ */
	inode->i_flags|=S_IMMUTABLE;
```

```c
static struct dentry *proc_task_instantiate(struct inode *dir,
	struct dentry *dentry, struct task_struct *task, const void *ptr)
{
	struct dentry *error = ERR_PTR(-ENOENT);
	struct inode *inode;
	inode = proc_pid_make_inode(dir->i_sb, task);

	if (!inode)
		goto out;
	inode->i_mode = S_IFDIR|S_IRUGO|S_IXUGO;
	inode->i_op = &proc_tid_base_inode_operations;
	inode->i_fop = &proc_tid_base_operations;
    /* これ */
	inode->i_flags|=S_IMMUTABLE;
```

S_IMMUTABLE ビットがたっているかどうかは IS_IMMUTABLE で検査する

```
#define IS_IMMUTABLE(inode)	((inode)->i_flags & S_IMMUTABLE)
```

may_delete では IS_IMMUTABLE の場合に EPERM が返る

```c
static int may_delete(struct inode *dir,struct dentry *victim,int isdir)
{
	int error;

	if (!victim->d_inode)
		return -ENOENT;

	BUG_ON(victim->d_parent->d_inode != dir);
	audit_inode_child(dir, victim, AUDIT_TYPE_CHILD_DELETE);

	error = inode_permission(dir, MAY_WRITE | MAY_EXEC);
	if (error)
		return error;
	if (IS_APPEND(dir))
		return -EPERM;
	if (check_sticky(dir, victim->d_inode)||IS_APPEND(victim->d_inode)||
        /* ここ。スワップの場合も削除できないぞー */
	    IS_IMMUTABLE(victim->d_inode) || IS_SWAPFILE(victim->d_inode))
		return -EPERM;
```