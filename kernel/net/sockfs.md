# sockfs

ファイルインタフェースとソケットインタフェースを繋ぐ sockfs を読む

## sockfs ファイルシステムの登録

```c
satic struct file_system_type sock_fs_type = {
	.name =		"sockfs",
	.get_sb =	sockfs_get_sb,
	.kill_sb =	kill_anon_super,
};
```

## スーパーブロックの初期化

get_sb_pseudo で疑似スーパーブロックとして返す ( get_sb_nodev と何が違うんだっけ? )

```c
static int sockfs_get_sb(struct file_system_type *fs_type,
			 int flags, const char *dev_name, void *data,
			 struct vfsmount *mnt)
{
	return get_sb_pseudo(fs_type, "socket:", &sockfs_ops, SOCKFS_MAGIC,
			     mnt);
}
```

ファイルシステムとして「パス」を提供しなくていい = マウントできない場合は、 pseudo を使うっぽい感。 pipefs も get_sb_pseudo 使っている

sockfs_ops は下記の通り

```c
static const struct super_operations sockfs_ops = {
	.alloc_inode =	sock_alloc_inode,
	.destroy_inode =sock_destroy_inode,
	.statfs =	simple_statfs,
};
```

## sock_alloc_inode, sock_destroy_inode

kmem_cache で sock_alloc をキャッシュして扱う

```c
struct socket_alloc {
	struct socket socket;
	struct inode vfs_inode;
};
```

```c
static struct inode *sock_alloc_inode(struct super_block *sb)
{
	struct socket_alloc *ei;

	ei = kmem_cache_alloc(sock_inode_cachep, GFP_KERNEL);
	if (!ei)
		return NULL;
	init_waitqueue_head(&ei->socket.wait);

	ei->socket.fasync_list = NULL;
	ei->socket.state = SS_UNCONNECTED;
	ei->socket.flags = 0;
	ei->socket.ops = NULL;
	ei->socket.sk = NULL;
	ei->socket.file = NULL;

	return &ei->vfs_inode;
}

static void sock_destroy_inode(struct inode *inode)
{
	kmem_cache_free(sock_inode_cachep,
			container_of(inode, struct socket_alloc, vfs_inode));
}
```

## struct socket <=> struct file の変換

sock_from_file で成される

 * file->private_data に struct socket を保持している
 * `file->f_op == &socket_file_ops` でソケットかどうか判定するというなかなか荒技

```c
static struct socket *sock_from_file(struct file *file, int *err)
{
	if (file->f_op == &socket_file_ops)
		return file->private_data;	/* set in sock_map_fd */

	*err = -ENOTSOCK;
	return NULL;
}
```

# sockfs の struct file

ソケットインタフェースとファイルインタフェースを結びつけていく部分。 socket -> sock_map_fd -> sock_alloc_file を見て行くとよい

```c
SYSCALL_DEFINE3(socket, int, family, int, type, int, protocol)
{
	int retval;
	struct socket *sock;
	int flags;

	/* Check the SOCK_* constants for consistency.  */
	BUILD_BUG_ON(SOCK_CLOEXEC != O_CLOEXEC);
	BUILD_BUG_ON((SOCK_MAX | SOCK_TYPE_MASK) != SOCK_TYPE_MASK);
	BUILD_BUG_ON(SOCK_CLOEXEC & SOCK_TYPE_MASK);
	BUILD_BUG_ON(SOCK_NONBLOCK & SOCK_TYPE_MASK);

	flags = type & ~SOCK_TYPE_MASK;
	if (flags & ~(SOCK_CLOEXEC | SOCK_NONBLOCK))
		return -EINVAL;
	type &= SOCK_TYPE_MASK;

	if (SOCK_NONBLOCK != O_NONBLOCK && (flags & SOCK_NONBLOCK))
		flags = (flags & ~SOCK_NONBLOCK) | O_NONBLOCK;

	retval = sock_create(family, type, protocol, &sock);
	if (retval < 0)
		goto out;

	retval = sock_map_fd(sock, flags & (O_CLOEXEC | O_NONBLOCK));
	if (retval < 0)
		goto out_release;

out:
	/* It may be already another descriptor 8) Not kernel problem. */
	return retval;

out_release:
	sock_release(sock);
	return retval;
}
```

sock_map_fd で ファイルデスクリプタと socket をポインタで繋ぐ

```c
int sock_map_fd(struct socket *sock, int flags)
{
	struct file *newfile;
	int fd = sock_alloc_file(sock, &newfile, flags);

    // ファイルデスクリプタと struct sock がマップされた
	if (likely(fd >= 0))
		fd_install(fd, newfile);

	return fd;
}
```

sock_alloc_file が最大の肝

```c
/*
 *	Obtains the first available file descriptor and sets it up for use.
 *
 *	These functions create file structures and maps them to fd space
 *	of the current process. On success it returns file descriptor
 *	and file struct implicitly stored in sock->file.
 *	Note that another thread may close file descriptor before we return
 *	from this function. We use the fact that now we do not refer
 *	to socket after mapping. If one day we will need it, this
 *	function will increment ref. count on file by 1.
 *
 *	In any case returned fd MAY BE not valid!
 *	This race condition is unavoidable
 *	with shared fd spaces, we cannot solve it inside kernel,
 *	but we take care of internal coherence yet.
 */

static int sock_alloc_file(struct socket *sock, struct file **f, int flags)
{
	struct qstr name = { .name = "" };
	struct path path;
	struct file *file;
	int fd;

	fd = get_unused_fd_flags(flags);
	if (unlikely(fd < 0))
		return fd;

    // mount できない = 「パス」を提供する必要のないファイルシステムでは pseudo suffix な関数群を呼んだらよいのか?
	path.dentry = d_alloc_pseudo(sock_mnt->mnt_sb, &name);
	if (unlikely(!path.dentry)) {
		put_unused_fd(fd);
		return -ENOMEM;
	}
	path.mnt = mntget(sock_mnt);

    // 疑似dentry 用のメソッド
	path.dentry->d_op = &sockfs_dentry_operations;
	/*
	 * We dont want to push this dentry into global dentry hash table.
	 * We pretend dentry is already hashed, by unsetting DCACHE_UNHASHED
	 * This permits a working /proc/$pid/fd/XXX on sockets
	 */
	path.dentry->d_flags &= ~DCACHE_UNHASHED;

    // socket -> socket_alloc を経由してから vfs_inode を取り出す
	d_instantiate(path.dentry, SOCK_INODE(sock));

    // 「ファイル」インタフェースのメソッドを inode_operations に当てておく
	SOCK_INODE(sock)->i_fop = &socket_file_ops;

    // struct file の割り当て。 R/W なパーミッションになっている
    // file_operations も割り当てる
	file = alloc_file(&path, FMODE_READ | FMODE_WRITE,
		  &socket_file_ops);
	if (unlikely(!file)) {
		/* drop dentry, keep inode */
		atomic_inc(&path.dentry->d_inode->i_count);
		path_put(&path);
		put_unused_fd(fd);
		return -ENFILE;
	}

	sock->file = file;
	file->f_flags = O_RDWR | (flags & O_NONBLOCK);

    // ソケットなのでポジションは 0 のまんま
	file->f_pos = 0;

    // struct file <=> struct socket が交換できる
	file->private_data = sock;

	*f = file;
	return fd;
}
```

# sockfs の dentry_operations

```
static int sockfs_delete_dentry(struct dentry *dentry)
{
	/*
	 * At creation time, we pretended this dentry was hashed
	 * (by clearing DCACHE_UNHASHED bit in d_flags)
	 * At delete time, we restore the truth : not hashed.
	 * (so that dput() can proceed correctly)
	 */
	dentry->d_flags |= DCACHE_UNHASHED;
	return 0;
}

/*
 * sockfs_dname() is called from d_path().
 */
static char *sockfs_dname(struct dentry *dentry, char *buffer, int buflen)
{
    // /proc/<pid>/fd で見える文字列
	return dynamic_dname(dentry, buffer, buflen, "socket:[%lu]",
				dentry->d_inode->i_ino);
}

static const struct dentry_operations sockfs_dentry_operations = {
	.d_delete = sockfs_delete_dentry,
	.d_dname  = sockfs_dname,
};
```

# write, read が socket のファイルデスクリプタにも使えるのは何故か?

file_operations に socket_file_ops が使われている

 * sock_aio_read, sock_aio_write ... が read(2)/write(2) のインタフェースをソケットインタフェースに合わせてアダプタする
   * sock_aio_write -> do_sock_write -> __sock_sendmsg
   * sock_aio_read  -> do_sock_read  -> __sock_recvmsg

```c
static const struct file_operations socket_file_ops = {
	.owner =	THIS_MODULE,
	.llseek =	no_llseek,
	.aio_read =	sock_aio_read,
	.aio_write =	sock_aio_write,
	.poll =		sock_poll,
	.unlocked_ioctl = sock_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl = compat_sock_ioctl,
#endif
	.mmap =		sock_mmap,
	.open =		sock_no_open,	/* special open code to disallow open via /proc */
	.release =	sock_close,
	.fasync =	sock_fasync,
	.sendpage =	sock_sendpage,
	.splice_write = generic_splice_sendpage,
	.splice_read =	sock_splice_read,
};
```

## sock_aio_write -> do_sock_write -> __sock_sendmsg

```c
static ssize_t sock_aio_write(struct kiocb *iocb, const struct iovec *iov,
			  unsigned long nr_segs, loff_t pos)
{
	struct sock_iocb siocb, *x;

    /* ソケットなので position 指定できない */
	if (pos != 0)
		return -ESPIPE;

    /* ソケットで非同期処理するためのなんとか */
	x = alloc_sock_iocb(iocb, &siocb);
	if (!x)
		return -ENOMEM;

	return do_sock_write(&x->async_msg, iocb, iocb->ki_filp, iov, nr_segs);
}
```

sturct iovec を struct msghdr に載せ変えて __sock_sendmsg を呼び出す

```c
static ssize_t do_sock_write(struct msghdr *msg, struct kiocb *iocb,
			struct file *file, const struct iovec *iov,
			unsigned long nr_segs)
{
	struct socket *sock = file->private_data;
	size_t size = 0;
	int i;

	for (i = 0; i < nr_segs; i++)
		size += iov[i].iov_len;

	msg->msg_name = NULL;
	msg->msg_namelen = 0;
	msg->msg_control = NULL;
	msg->msg_controllen = 0;
	msg->msg_iov = (struct iovec *)iov;
	msg->msg_iovlen = nr_segs;
	msg->msg_flags = (file->f_flags & O_NONBLOCK) ? MSG_DONTWAIT : 0;
	if (sock->type == SOCK_SEQPACKET)
		msg->msg_flags |= MSG_EOR;

	return __sock_sendmsg(iocb, sock, msg, size);
}
```

以降は sendto(2) や sendmsg(2) と同じ呼び出しパスになる