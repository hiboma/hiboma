# pipe(2)

 * pipe は疑似ファイルシステム( pipefs) として実装されている
 * VFS の仕組みを利用する
 * バッファは struct page を利用して circular buffer で扱っている

## USAGE

```c
#include <unistd.h>

int pipe(int pipefd[2]);

#define _GNU_SOURCE             /* feature_test_macros(7) 参照 */
#include <fcntl.h>              /* O_* 定数の定義の取得 */
#include <unistd.h>

int pipe2(int pipefd[2], int flags);
```

## pipe(2)

fs/pipe.c

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

[reader] <= create_read_pipe
``

## writer と reader の初期化

do_pipe_flags で writer と reader の struct file を割り当てる

```c
int do_pipe_flags(int *fd, int flags)
{
	struct file *fw, *fr;
	int error;
	int fdw, fdr;

	if (flags & ~(O_CLOEXEC | O_NONBLOCK))
		return -EINVAL;

	fw = create_write_pipe(flags);
	if (IS_ERR(fw))
		return PTR_ERR(fw);
	fr = create_read_pipe(fw, flags);
	error = PTR_ERR(fr);
	if (IS_ERR(fr))
		goto err_write_pipe;
````

## writer 側の struct file の割り当て

create_write_pipe で割り当てる。VFS で動くように

 * struct inode
 * struct file
 * struct path
 * struct dentry

 を割り当てて初期化する。いずれもオンメモリのオブジェクトなので揮発性である

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

## reader の struct file の割り当て

writer が用意した struct path を共有して struct file を割り当てている

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

struct path が pipe_inode_info を保持しているので、reader/writer で pipe_inode_info を共有することになる

## バッファの仕組み

プロセス間でデータをやり取りする際のバッファには pipe_buffer を使う

 * pipe_buffer を複数束ねて circular buffer として扱う
   * http://lwn.net/Articles/118750/
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

pipe_buffer は struct pipe_inode_info に配列(16個)で保持されている。

 * inode->i_pipe から参照される
 * nrbufs, curbuf をうまいこと使って、 pipe_buffer を circular buffer にする

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

## pipe_buffer の読み取り

reader は read(2) -> vfs_read -> aio_read で pipe_read を呼び出す

```c
static ssize_t
pipe_read(struct kiocb *iocb, const struct iovec *_iov,
	   unsigned long nr_segs, loff_t pos)
{
	struct file *filp = iocb->ki_filp;
	struct inode *inode = filp->f_path.dentry->d_inode;
	struct pipe_inode_info *pipe;
	int do_wakeup;
	ssize_t ret;
	struct iovec *iov = (struct iovec *)_iov;
	size_t total_len;

	total_len = iov_length(iov, nr_segs);
	/* Null read succeeds. */
	if (unlikely(total_len == 0))
		return 0;

	do_wakeup = 0;
	ret = 0;
    /* write 側をロックする */
	mutex_lock(&inode->i_mutex);
	pipe = inode->i_pipe;
	for (;;) {
		int bufs = pipe->nrbufs;
		if (bufs) {
            /* カレントで扱っているバッファのポジション */
			int curbuf = pipe->curbuf;
			struct pipe_buffer *buf = pipe->bufs + curbuf;
			const struct pipe_buf_operations *ops = buf->ops;
			void *addr;
			size_t chars = buf->len;
			int error, atomic;

			if (chars > total_len)
				chars = total_len;

			error = ops->confirm(pipe, buf);
			if (error) {
				if (!ret)
					error = ret;
				break;
			}

			atomic = !iov_fault_in_pages_write(iov, chars);
redo:
            /* バッファ(struct page) を kmap する */
			addr = ops->map(pipe, buf, atomic);
            /* バッファの中身を iov へコピー
			error = pipe_iov_copy_to_user(iov, addr + buf->offset, chars, atomic);
            /* バッファの kmap を解除 */
			ops->unmap(pipe, buf, addr);
			if (unlikely(error)) {
				/*
				 * Just retry with the slow path if we failed.
				 */
				if (atomic) {
					atomic = 0;
					goto redo;
				}
				if (!ret)
					ret = error;
				break;
			}
			ret += chars;
			buf->offset += chars;
			buf->len -= chars;
			if (!buf->len) {
				buf->ops = NULL;
				ops->release(pipe, buf);
				curbuf = (curbuf + 1) & (PIPE_BUFFERS-1);
				pipe->curbuf = curbuf;
				pipe->nrbufs = --bufs;
				do_wakeup = 1;
			}
			total_len -= chars;
			if (!total_len)
				break;	/* common path: read succeeded */
		}
        /* もういっぺん繰り返し */
		if (bufs)	/* More to do? */
			continue;

        /* バッファを読み切った + writer プロセスがいないので終わり */
		if (!pipe->writers)
			break;
		if (!pipe->waiting_writers) {
			/* syscall merging: Usually we must not sleep
			 * if O_NONBLOCK is set, or if we got some data.
			 * But if a writer sleeps in kernel space, then
			 * we can wait for that data without violating POSIX.
			 */
			if (ret)
				break;
			if (filp->f_flags & O_NONBLOCK) {
				ret = -EAGAIN;
				break;
			}
		}
		if (signal_pending(current)) {
			if (!ret)
				ret = -ERESTARTSYS;
			break;
		}

        /* writer を起床させる? */
		if (do_wakeup) {
			wake_up_interruptible_sync(&pipe->wait);
 			kill_fasync(&pipe->fasync_writers, SIGIO, POLL_OUT);
		}
		pipe_wait(pipe);
	}
	mutex_unlock(&inode->i_mutex);

	/* Signal writers asynchronously that there is more room. */
	if (do_wakeup) {
		wake_up_interruptible_sync(&pipe->wait);
		kill_fasync(&pipe->fasync_writers, SIGIO, POLL_OUT);
	}
	if (ret > 0)
		file_accessed(filp);
	return ret;
}
```

## pipe_buffer の書きこみ

write(2) -> vfs_write -> aio_write で pipe_write を呼び出す

```c
static ssize_t
pipe_write(struct kiocb *iocb, const struct iovec *_iov,
	    unsigned long nr_segs, loff_t ppos)
{
	struct file *filp = iocb->ki_filp;
	struct inode *inode = filp->f_path.dentry->d_inode;
	struct pipe_inode_info *pipe;
	ssize_t ret;
	int do_wakeup;
	struct iovec *iov = (struct iovec *)_iov;
	size_t total_len;
	ssize_t chars;

	total_len = iov_length(iov, nr_segs);
	/* Null write succeeds. */
	if (unlikely(total_len == 0))
		return 0;

	do_wakeup = 0;
	ret = 0;
	sb_start_write(inode->i_sb);
	mutex_lock(&inode->i_mutex);
	pipe = inode->i_pipe;

    /* reader 側がいないので、write が EPIPE を返す */
	if (!pipe->readers) {
		send_sig(SIGPIPE, current, 0);
		ret = -EPIPE;
		goto out;
	}

	/* We try to merge small writes */
    /* ページ内で必要なバイト数 */
	chars = total_len & (PAGE_SIZE-1); /* size of the last buffer */

    /* nrbufs > 0 ... read されてないバッファが残っている */
	if (pipe->nrbufs && chars != 0) {

        /*
         * 空いているバッファを探す。
         * & PIPE_BUFFERS-1 によって位置が循環する
         */
		int lastbuf = (pipe->curbuf + pipe->nrbufs - 1) &
							(PIPE_BUFFERS-1);
		struct pipe_buffer *buf = pipe->bufs + lastbuf;
		const struct pipe_buf_operations *ops = buf->ops;

        /* バッファ(page) 内の書き込みオフセット */
		int offset = buf->offset + buf->len;

        /* 書き込むデータがバッファ1ページに収まる場合 */
		if (ops->can_merge && offset + chars <= PAGE_SIZE) {
			int error, atomic = 1;
			void *addr;

			error = ops->confirm(pipe, buf);
			if (error)
				goto out;

            // Pre-fault in the user memory, so we can use atomic copies.
            // とのことらしい
			iov_fault_in_pages_read(iov, chars);
redo1:
            /* kmap */
			addr = ops->map(pipe, buf, atomic);
            /* ユーザ空間のiov の中身をバッファにコピー */
			error = pipe_iov_copy_from_user(offset + addr, iov,
							chars, atomic);
            /* kmap 解除 */
			ops->unmap(pipe, buf, addr);
			ret = error;
			do_wakeup = 1;
			if (error) {
				if (atomic) {
					atomic = 0;
					goto redo1;
				}
				goto out;
			}
			buf->len += chars;
			total_len -= chars;
			ret = chars;
			if (!total_len)
				goto out;
		}
	}

	for (;;) {
		int bufs;

        /* reader がいなくなってたら EPIPE で死ぬ */
		if (!pipe->readers) {
			send_sig(SIGPIPE, current, 0);
			if (!ret)
				ret = -EPIPE;
			break;
		}

		bufs = pipe->nrbufs;
		if (bufs < PIPE_BUFFERS) {
			int newbuf = (pipe->curbuf + bufs) & (PIPE_BUFFERS-1);
			struct pipe_buffer *buf = pipe->bufs + newbuf;
			struct page *page = pipe->tmp_page;
			char *src;
			int error, atomic = 1;

            /* ??? */
			if (!page) {
				page = alloc_page(GFP_HIGHUSER);
				if (unlikely(!page)) {
					ret = ret ? : -ENOMEM;
					break;
				}
				pipe->tmp_page = page;
			}
			/* Always wake up, even if the copy fails. Otherwise
			 * we lock up (O_NONBLOCK-)readers that sleep due to
			 * syscall merging.
			 * FIXME! Is this really true?
			 */
			do_wakeup = 1;
			chars = PAGE_SIZE;
			if (chars > total_len)
				chars = total_len;

			iov_fault_in_pages_read(iov, chars);
redo2:
			if (atomic)
				src = kmap_atomic(page, KM_USER0);
			else
				src = kmap(page);

            /* ユーザ空間の iov から バッファへコピー */
            /* error は EFAULT ? */
			error = pipe_iov_copy_from_user(src, iov, chars,
							atomic);
			if (atomic)
				kunmap_atomic(src, KM_USER0);
			else
				kunmap(page);

			if (unlikely(error)) {
				if (atomic) {
					atomic = 0;
					goto redo2;
				}
				if (!ret)
					ret = error;
				break;
			}
			ret += chars;

			/* Insert it into the buffer array */
			buf->page = page;
			buf->ops = &anon_pipe_buf_ops;
			buf->offset = 0;
			buf->len = chars;
			pipe->nrbufs = ++bufs;
			pipe->tmp_page = NULL;

			total_len -= chars;
			if (!total_len)
				break;
		}
		if (bufs < PIPE_BUFFERS)
			continue;

        /* bufs > PIPE_BUFFERS の場合は、 reader がバッファを消費してくれるまで待つ必要があるのかな? */

        /* ノンブロッキングなら EAGAIN 返す */
		if (filp->f_flags & O_NONBLOCK) {
			if (!ret)
				ret = -EAGAIN;
			break;
		}
		if (signal_pending(current)) {
			if (!ret)
				ret = -ERESTARTSYS;
			break;
		}
		if (do_wakeup) {
			wake_up_interruptible_sync(&pipe->wait);
			kill_fasync(&pipe->fasync_readers, SIGIO, POLL_IN);
			do_wakeup = 0;
		}
        /* reader 側を TASK_INTERRUPTIBLE で待つ */
		pipe->waiting_writers++;
		pipe_wait(pipe);
		pipe->waiting_writers--;
	}
out:
	mutex_unlock(&inode->i_mutex);
	if (do_wakeup) {
		wake_up_interruptible_sync(&pipe->wait);
		kill_fasync(&pipe->fasync_readers, SIGIO, POLL_IN);
	}
	if (ret > 0)
		file_update_time(filp);
	sb_end_write(inode->i_sb);
	return ret;
}
```

## 検証コード

#### バッファが溢れた際に writer がブロックする様子を strace する

```
$ strace perl -e 'print 1 while 1' | perl -e 'sleep 1'
```

上記のワンライナーを走らせると、writer が丁度 `PAGE_SIZE (= 4096) * PIPE_BUFFERS (= 16)` でブロックする

```
# 本筋と関係無いけど、4096バイト = PAGE_SIZE でバッファリングされている
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 1
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 2
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 3
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 4
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 5
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 6
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 7
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 8
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 9
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 10
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 11
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 12
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 13
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 14
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 15
write(1, "11111111111111111111111111111111"..., 4096) = 4096 # 16
write(1, "11111111111111111111111111111111"..., 4096) = -1 EPIPE (Broken pipe)
--- SIGPIPE (Broken pipe) @ 0 (0) --- # reader が exit するので EPIPE を返す
+++ killed by SIGPIPE +++
```

ブロックしているときの writer のコールスタックは下記の通り。 pipe_wait で待ち

```
$ cat /proc/22543/stack
[<ffffffff8117862b>] pipe_wait+0x5b/0x80
[<ffffffff81178b70>] pipe_write+0x2e0/0x6b0
[<ffffffff8116e752>] do_sync_write+0xe2/0x120
[<ffffffff8116ed13>] vfs_write+0xf3/0x1f0
[<ffffffff8116ef11>] sys_write+0x51/0x90
[<ffffffff81527a7d>] system_call_fastpath+0x18/0x1d
[<ffffffffffffffff>] 0xffffffffffffffff
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

## pipe_buf_operations とは?

カーネル内部で struct page を kmap して page を扱えるようにする便利 ops ?

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

