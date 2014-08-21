# fifo の実装

 * pipe と一緒 (= pipefs)
 * open してファイルデスクリプタを確保するまでの違いが「名前付きパイプ」と「パイプ」の差異になる

## fifo

mknod(2) で S_IFIFO なファイルを作る

```c
SYSCALL_DEFINE4(mknodat, int, dfd, const char __user *, filename, int, mode,
		unsigned, dev)
{
	int error, err2;
	struct filename *tmp;
	struct dentry *dentry;
	struct nameidata nd;
	unsigned int lookup_flags = 0;

//...    
	switch (mode & S_IFMT) {
		case 0: case S_IFREG:
			error = vfs_create(nd.path.dentry->d_inode,dentry,mode,&nd);
			break;
		case S_IFCHR: case S_IFBLK:
			error = vfs_mknod(nd.path.dentry->d_inode,dentry,mode,
					new_decode_dev(dev));
			break;
		case S_IFIFO: case S_IFSOCK:
			error = vfs_mknod(nd.path.dentry->d_inode,dentry,mode,0);
			break;
	}
```

S_IFIFO な場合 vfs_mknod でファイルを作る

```c
int vfs_mknod(struct inode *dir, struct dentry *dentry, int mode, dev_t dev)
{
	int error = may_create(dir, dentry);

	if (error)
		return error;

	if ((S_ISCHR(mode) || S_ISBLK(mode)) && !capable(CAP_MKNOD))
		return -EPERM;

	if (!dir->i_op->mknod)
		return -EPERM;

    /* device cgroup でパーミッションの監査 */
	error = devcgroup_inode_mknod(mode, dev);
	if (error)
		return error;

	error = security_inode_mknod(dir, dentry, mode, dev);
	if (error)
		return error;

	vfs_dq_init(dir);
	error = dir->i_op->mknod(dir, dentry, mode, dev);
	if (!error)
		fsnotify_create(dir, dentry);
	return error;
}
```

S_IFIFO なファイルをどう作るかはファイルシステムにお任せになる。ファイルシステム固有の inode 割り当て、dentry の割り当て等々

## FIFO の file_operations

```c
/*
 * Dummy default file-operations: the only thing this does
 * is contain the open that then fills in the correct operations
 * depending on the access mode of the file...
 */
const struct file_operations def_fifo_fops = {
	.open		= fifo_open,	/* will set read_ or write_pipefifo_fops */
};
```

## fifo_open

fifo のファイルを open(2) すると fifo_open が呼ばれる。struct file の file_operations が read_pipefifo_fops or write_pipefifo_fops に置き換えられる

```c
static int fifo_open(struct inode *inode, struct file *filp)
{
	struct pipe_inode_info *pipe;
	int ret;

	mutex_lock(&inode->i_mutex);
	pipe = inode->i_pipe;
	if (!pipe) {
		ret = -ENOMEM;
		pipe = alloc_pipe_info(inode);
		if (!pipe)
			goto err_nocleanup;
		inode->i_pipe = pipe;
	}
	filp->f_version = 0;

	/* We can only do regular read/write on fifos */
	filp->f_mode &= (FMODE_READ | FMODE_WRITE);

	switch (filp->f_mode) {
	case FMODE_READ:
	/*
	 *  O_RDONLY
	 *  POSIX.1 says that O_NONBLOCK means return with the FIFO
	 *  opened, even when there is no process writing the FIFO.
	 */
		filp->f_op = &read_pipefifo_fops;
		pipe->r_counter++;
		if (pipe->readers++ == 0)
			wake_up_partner(inode);

		if (!pipe->writers) {
			if ((filp->f_flags & O_NONBLOCK)) {
				/* suppress POLLHUP until we have
				 * seen a writer */
				filp->f_version = pipe->w_counter;
			} else 
			{
				wait_for_partner(inode, &pipe->w_counter);
				if(signal_pending(current))
					goto err_rd;
			}
		}
		break;
	
	case FMODE_WRITE:
	/*
	 *  O_WRONLY
	 *  POSIX.1 says that O_NONBLOCK means return -1 with
	 *  errno=ENXIO when there is no process reading the FIFO.
	 */
		ret = -ENXIO;
		if ((filp->f_flags & O_NONBLOCK) && !pipe->readers)
			goto err;

		filp->f_op = &write_pipefifo_fops;
		pipe->w_counter++;
		if (!pipe->writers++)
			wake_up_partner(inode);

		if (!pipe->readers) {
			wait_for_partner(inode, &pipe->r_counter);
			if (signal_pending(current))
				goto err_wr;
		}
		break;
	
	case FMODE_READ | FMODE_WRITE:
	/*
	 *  O_RDWR
	 *  POSIX.1 leaves this case "undefined" when O_NONBLOCK is set.
	 *  This implementation will NEVER block on a O_RDWR open, since
	 *  the process can at least talk to itself.
	 */
		filp->f_op = &rdwr_pipefifo_fops;

		pipe->readers++;
		pipe->writers++;
		pipe->r_counter++;
		pipe->w_counter++;
		if (pipe->readers == 1 || pipe->writers == 1)
			wake_up_partner(inode);
		break;

	default:
		ret = -EINVAL;
		goto err;
	}

	/* Ok! */
	mutex_unlock(&inode->i_mutex);
	return 0;

err_rd:
	if (!--pipe->readers)
		wake_up_interruptible(&pipe->wait);
	ret = -ERESTARTSYS;
	goto err;

err_wr:
	if (!--pipe->writers)
		wake_up_interruptible(&pipe->wait);
	ret = -ERESTARTSYS;
	goto err;

err:
	if (!pipe->readers && !pipe->writers)
		free_pipe_info(inode);

err_nocleanup:
	mutex_unlock(&inode->i_mutex);
	return ret;
}
```