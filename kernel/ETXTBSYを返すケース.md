# ETXTBSY

ETXTBSY を返すケースをまとめる

## ETXTBSY を返すケース

#### 実行中のバイナリを O_WRONLY つけて open しようとすると返す

.sleep バイナリが他のプロセスによって実行中。この時 cp で上書きを試みると ETXTBSY を返す

```
$ strace cp /dev/null .sleep

open(".sleep", O_WRONLY|O_TRUNC)        = -1 ETXTBSY (Text file busy)
```

最初の予想と違って O_TRUNC 有無は関係なかった

```
$ strace ./.open 
open(".sleep", O_WRONLY)                = -1 ETXTBSY (Text file busy)
```

#### O_WRONLY で open(2) 中のバイナリを execve(2) しようとすると返す

.sleep バイナリを open + O_WRONLY していり状態を作っておく

```c
	if (open(".sleep", O_WRONLY) == -1)
		perror("open");

    sleep(100);
```

他のシェルで .sleep バイナリを実行しようとすると execve(2) が ETXTBSY を返す

```
[vagrant@vagrant-centos65 vagrant]$ strace ./.sleep 
execve("./.sleep", ["./.sleep"], [/* 22 vars */]) = -1 ETXTBSY (Text file busy)
dup(2)                                  = 3
fcntl(3, F_GETFL)                       = 0x8002 (flags O_RDWR|O_LARGEFILE)
fstat(3, {st_mode=S_IFCHR|0620, st_rdev=makedev(136, 0), ...}) = 0
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fdd7cb8e000
lseek(3, 0, SEEK_CUR)                   = -1 ESPIPE (Illegal seek)
write(3, "strace: exec: Text file busy\n", 29strace: exec: Text file busy
) = 29
close(3)                                = 0
munmap(0x7fdd7cb8e000, 4096)            = 0
exit_group(1)                           = ?
```

バイナリを open(2)/write(2) で更新するのでなくて、rename(2) で置き換えるのが正解 (rsync)

## ETXTBSY を返すカーネル内のコード

いろいろあるけど、汎用っぽいのは fs/namei.c の次の二つ

 * get_write_access
   * file への write 権を得る
 * deny_write_access
   * file の write 権をリリースする

inode の i_writecount の取りうる値と状態

 * 0   書き込みが無い、VM_DENYWRITE されてない
 * < 0 vm_area_structs に VM_DENYWRITE がセットされている
 * > 0 file に書き込み中

```c
/*
 * get_write_access() gets write permission for a file.
 * put_write_access() releases this write permission.
 * This is used for regular files.
 * We cannot support write (and maybe mmap read-write shared) accesses and
 * MAP_DENYWRITE mmappings simultaneously. The i_writecount field of an inode
 * can have the following values:
 * 0: no writers, no VM_DENYWRITE mappings
 * < 0: (-i_writecount) vm_area_structs with VM_DENYWRITE set exist
 * > 0: (i_writecount) users are writing to the file.
 *
 * Normally we operate on that counter with atomic_{inc,dec} and it's safe
 * except for the cases where we don't hold i_writecount yet. Then we need to
 * use {get,deny}_write_access() - these functions check the sign and refuse
 * to do the change if sign is wrong. Exclusion between them is provided by
 * the inode->i_lock spinlock.
 */

int get_write_access(struct inode * inode)
{
	spin_lock(&inode->i_lock);
	if (atomic_read(&inode->i_writecount) < 0) {
		spin_unlock(&inode->i_lock);
		return -ETXTBSY;
	}
	atomic_inc(&inode->i_writecount);
	spin_unlock(&inode->i_lock);

	return 0;
}

int deny_write_access(struct file * file)
{
	struct inode *inode = file->f_path.dentry->d_inode;

	spin_lock(&inode->i_lock);
    // 対象の file が write で開かれているなら ETXTBSY になる
	if (atomic_read(&inode->i_writecount) > 0) {
		spin_unlock(&inode->i_lock);
		return -ETXTBSY;
	}
	atomic_dec(&inode->i_writecount);
	spin_unlock(&inode->i_lock);

	return 0;
}
```

#### get_write_access が使われているコード

 * do_filp_open + O_TRUNC で  handle_truncate 呼び出すパス

```c
static int handle_truncate(struct file *filp)
{
	struct path *path = &filp->f_path;
	struct inode *inode = path->dentry->d_inode;
	int error = get_write_access(inode);
	if (error)
		return error;
	/*
	 * Refuse to truncate files with mandatory locks held on them.
	 */
	error = locks_verify_locked(inode);
	if (!error)
		error = security_path_truncate(path, 0,
				       ATTR_MTIME|ATTR_CTIME|ATTR_OPEN);
	if (!error) {
		error = do_truncate(path->dentry, 0,
				    ATTR_MTIME|ATTR_CTIME|ATTR_OPEN,
				    filp);
	}
	put_write_access(inode);
	return error;
}
```

 * do_filp_open
 * -> nameidata_to_filp
 * -> __dentry_open

```c
static struct file *__dentry_open(struct dentry *dentry, struct vfsmount *mnt,
					struct file *f,
					int (*open)(struct inode *, struct file *),
					const struct cred *cred)
{
	struct inode *inode;
	int error;

	f->f_mode = (__force fmode_t)((f->f_flags+1) & O_ACCMODE) | FMODE_LSEEK |
				FMODE_PREAD | FMODE_PWRITE;
	inode = dentry->d_inode;
	if (f->f_mode & FMODE_WRITE) {
                // ->
		error = __get_file_write_access(inode, mnt);
		if (error)
			goto cleanup_file;
		if (!special_file(inode->i_mode))
			file_take_write(f);
	}

/*
 * You have to be very careful that these write
 * counts get cleaned up in error cases and
 * upon __fput().  This should probably never
 * be called outside of __dentry_open().
 */
static inline int __get_file_write_access(struct inode *inode,
					  struct vfsmount *mnt)
{
	int error;
	error = get_write_access(inode);
	if (error)
		return error;
	/*
	 * Do not take mount writer counts on
	 * special files since no writes to
	 * the mount itself will occur.
	 */
	if (!special_file(inode->i_mode)) {
		/*
		 * Balanced in __fput()
		 */
		error = __mnt_want_write(mnt);
		if (error)
			put_write_access(inode);
	}
	return error;
}
```

## execve(2)

do_execve -> open_exec で deny_write_access

 * execve したいバイナリが O_WRONLY で open(2) されていたら ETXTBSY が返る

```c
struct file *open_exec(const char *name)
{
	struct file *file;
	int err;
	struct filename filename = { .name = name };

	file = do_filp_open(AT_FDCWD, &filename,
				O_LARGEFILE | O_RDONLY | FMODE_EXEC, 0,
				MAY_EXEC | MAY_OPEN);
	if (IS_ERR(file))
		goto out;

	err = -EACCES;
	if (!S_ISREG(file->f_path.dentry->d_inode->i_mode))
		goto exit;

	if (file->f_path.mnt->mnt_flags & MNT_NOEXEC)
		goto exit;

	fsnotify_open(file->f_path.dentry);

	err = deny_write_access(file);
	if (err)
		goto exit;
```

## VM_DENYWRITE とは?