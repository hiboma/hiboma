# pipe(2)

 * pipe は疑似ファイルシステムとして実装されている
 * バッファは struct page 

## USAGE

```c
#include <unistd.h>

int pipe(int pipefd[2]);

#define _GNU_SOURCE             /* feature_test_macros(7) 参照 */
#include <fcntl.h>              /* O_* 定数の定義の取得 */
#include <unistd.h>

int pipe2(int pipefd[2], int flags);
```

## fs/pipe.c

```c
/*
 * sys_pipe() is the normal C calling standard for creating
 * a pipe. It's not the way Unix traditionally does this, though.
 */
SYSCALL_DEFINE2(pipe2, int __user *, fildes, int, flags)
{
	int fd[2];
	int error;

	error = do_pipe_flags(fd, flags);
	if (!error) {
		if (copy_to_user(fildes, fd, sizeof(fd))) {
			sys_close(fd[0]);
			sys_close(fd[1]);
			error = -EFAULT;
		}
	}
	return error;
}

SYSCALL_DEFINE1(pipe, int __user *, fildes)
{
	return sys_pipe2(fildes, 0);
}
```

## pipe の実装

pipe のプロセス間通信は **pipefs** (疑似ファイルシステム) をベースとして実装されている

## pipefs の定義と登録

```c
static struct file_system_type pipe_fs_type = {
	.name		= "pipefs",
	.get_sb		= pipefs_get_sb,
	.kill_sb	= kill_anon_super,
};

static int __init init_pipe_fs(void)
{
	int err = register_filesystem(&pipe_fs_type);

	if (!err) {
		pipe_mnt = kern_mount(&pipe_fs_type);
		if (IS_ERR(pipe_mnt)) {
			err = PTR_ERR(pipe_mnt);
			unregister_filesystem(&pipe_fs_type);
		}
	}
	return err;
}
```

ファイルシステムとして実装されているので、通常のファイルシステムと同様に

 * struct dentry
 * struct path
 * struct inode

を動的にアロケートして扱う必要がある。また reader, writer と分けておく必要がある

関係を図示すると

```

[writer] <= create_write_pipe

  struct file
   * write_pipefifo_fops

  struct path
   * dentry 
     * pipefs_dentry_operations
     *  get_pipe_inode 
       * struct pipe_inode_info *pipe;

  struct file
   * read_pipefifo_fops
   * get_pipe_inode

[reader] <= create_read_pipe
```

## パイプの writer 

```c
struct file *create_write_pipe(int flags)
{
	int err;
	struct inode *inode;
	struct file *f;
	struct path path;
	struct qstr name = { .name = "" };

	err = -ENFILE;
	inode = get_pipe_inode();
	if (!inode)
		goto err;

	err = -ENOMEM;
	path.dentry = d_alloc_pseudo(pipe_mnt->mnt_sb, &name);
	if (!path.dentry)
		goto err_inode;
	path.mnt = mntget(pipe_mnt);

	path.dentry->d_op = &pipefs_dentry_operations;
	/*
	 * We dont want to publish this dentry into global dentry hash table.
	 * We pretend dentry is already hashed, by unsetting DCACHE_UNHASHED
	 * This permits a working /proc/$pid/fd/XXX on pipes
	 */
	path.dentry->d_flags &= ~DCACHE_UNHASHED;
	d_instantiate(path.dentry, inode);

	err = -ENFILE;
	f = alloc_file(&path, FMODE_WRITE, &write_pipefifo_fops);
	if (!f)
		goto err_dentry;
	f->f_mapping = inode->i_mapping;

	f->f_flags = O_WRONLY | (flags & O_NONBLOCK);
	f->f_version = 0;

	return f;

 err_dentry:
	free_pipe_info(inode);
	path_put(&path);
	return ERR_PTR(err);

 err_inode:
	free_pipe_info(inode);
	iput(inode);
 err:
	return ERR_PTR(err);
}
```

## パイプの reader


```c
struct file *create_read_pipe(struct file *wrf, int flags)
{
	/* Grab pipe from the writer */
	struct file *f = alloc_file(&wrf->f_path, FMODE_READ,
				    &read_pipefifo_fops);
	if (!f)
		return ERR_PTR(-ENFILE);

	path_get(&wrf->f_path);
	f->f_flags = O_RDONLY | (flags & O_NONBLOCK);

	return f;
}
```


## バッファの仕組み

プロセス間でデータをやり取りする際のバッファには pipe_buffer を使う

 * struct page にデータを入れておく
 * page のデータを読み書きする pipe_buf_operations があるぽい (後述)

```c
/**
 *	struct pipe_buffer - a linux kernel pipe buffer
 *	@page: the page containing the data for the pipe buffer
 *	@offset: offset of data inside the @page
 *	@len: length of data inside the @page
 *	@ops: operations associated with this buffer. See @pipe_buf_operations.
 *	@flags: pipe buffer flags. See above.
 *	@private: private data owned by the ops.
 **/
struct pipe_buffer {
	struct page *page;
	unsigned int offset, len;
	const struct pipe_buf_operations *ops;
	unsigned int flags;
	unsigned long private;
};
```

pipe_buffer は struct pipe_inode_info に配列(16個)で保持されている。  inode->i_pipe で参照される

```c
/**
 *	struct pipe_inode_info - a linux kernel pipe
 *	@wait: reader/writer wait point in case of empty/full pipe
 *	@nrbufs: the number of non-empty pipe buffers in this pipe
 *	@curbuf: the current pipe buffer entry
 *	@tmp_page: cached released page
 *	@readers: number of current readers of this pipe
 *	@writers: number of current writers of this pipe
 *	@waiting_writers: number of writers blocked waiting for room
 *	@r_counter: reader counter
 *	@w_counter: writer counter
 *	@fasync_readers: reader side fasync
 *	@fasync_writers: writer side fasync
 *	@inode: inode this pipe is attached to
 *	@bufs: the circular array of pipe buffers
 **/
struct pipe_inode_info {
	wait_queue_head_t wait;
	unsigned int nrbufs, curbuf;
	struct page *tmp_page;
	unsigned int readers;
	unsigned int writers;
	unsigned int waiting_writers;
	unsigned int r_counter;
	unsigned int w_counter;
	struct fasync_struct *fasync_readers;
	struct fasync_struct *fasync_writers;
	struct inode *inode;
	struct pipe_buffer bufs[PIPE_BUFFERS];
};


## pipe_buf_operations

カーネル内部で struct page を隠蔽してバッファとして page を扱えるようにする便利 ops ?

```c
static const struct pipe_buf_operations anon_pipe_buf_ops = {
	.can_merge = 1,
	.map = generic_pipe_buf_map,
	.unmap = generic_pipe_buf_unmap,
	.confirm = generic_pipe_buf_confirm,
	.release = anon_pipe_buf_release,
	.steal = generic_pipe_buf_steal,
	.get = generic_pipe_buf_get,
};
```

## その他


```c
static const struct dentry_operations pipefs_dentry_operations = {
	.d_delete	= pipefs_delete_dentry,
	.d_dname	= pipefs_dname,
};
```


```c
/*
 * The file_operations structs are not static because they
 * are also used in linux/fs/fifo.c to do operations on FIFOs.
 *
 * Pipes reuse fifos' file_operations structs.
 */
const struct file_operations read_pipefifo_fops = {
	.llseek		= no_llseek,
	.read		= do_sync_read,
	.aio_read	= pipe_read,
	.write		= bad_pipe_w,
	.poll		= pipe_poll,
	.unlocked_ioctl	= pipe_ioctl,
	.open		= pipe_read_open,
	.release	= pipe_read_release,
	.fasync		= pipe_read_fasync,
};

const struct file_operations write_pipefifo_fops = {
	.llseek		= no_llseek,
	.read		= bad_pipe_r,
	.write		= do_sync_write,
	.aio_write	= pipe_write,
	.poll		= pipe_poll,
	.unlocked_ioctl	= pipe_ioctl,
	.open		= pipe_write_open,
	.release	= pipe_write_release,
	.fasync		= pipe_write_fasync,
};

const struct file_operations rdwr_pipefifo_fops = {
	.llseek		= no_llseek,
	.read		= do_sync_read,
	.aio_read	= pipe_read,
	.write		= do_sync_write,
	.aio_write	= pipe_write,
	.poll		= pipe_poll,
	.unlocked_ioctl	= pipe_ioctl,
	.open		= pipe_rdwr_open,
	.release	= pipe_rdwr_release,
	.fasync		= pipe_rdwr_fasync,
};
```