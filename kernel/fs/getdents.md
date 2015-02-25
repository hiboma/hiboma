# getdents(2)

ディレクトリのファイルデスクリプタから、ディレクトリエントリを指定した個数、読み取る

```c
int getdents(unsigned int fd, struct linux_dirent *dirp,
             unsigned int count);
```

ディレクトリエントリの実態は、下記のとおりに定義されている

```
/*
 * New, all-improved, singing, dancing, iBCS2-compliant getdents()
 * interface. 
 */
struct linux_dirent {
	unsigned long	d_ino;
	unsigned long	d_off;
	unsigned short	d_reclen;
	char		d_name[1];
};
```

システムコールが、struct linux_dirent のメンバを埋めていくかは、 getdents(2) を追う

## getdents システムコール

 * ディレクトリも「ファイル」なので、ファイルデスクリプタで扱っている
 * 詳細は実装は vfs_readdir に続く

```
SYSCALL_DEFINE3(getdents, unsigned int, fd,
		struct linux_dirent __user *, dirent, unsigned int, count)
{
	struct file * file;
	struct linux_dirent __user * lastdirent;
	struct getdents_callback buf;
	int error;

	error = -EFAULT;
	if (!access_ok(VERIFY_WRITE, dirent, count))
		goto out;

	error = -EBADF;
	file = fget(fd); ★
	if (!file)
		goto out;

	buf.current_dir = dirent;
	buf.previous = NULL;
	buf.count = count;
	buf.error = 0;

	error = vfs_readdir(file, filldir, &buf); ★
	if (error >= 0)
		error = buf.error;
	lastdirent = buf.previous;
	if (lastdirent) {
		if (put_user(file->f_pos, &lastdirent->d_off))
			error = -EFAULT;
		else
			error = count - buf.count;
	}
	fput(file);
out:
	return error;
}
```

## vfs_readdir

 * inode->i_muxtex で mutex を取っている
   * mutex_lock_killable => プロセスの状態を TASK_KILLABLE としてロックを取るので、 `STATE D` となるはず
   * vfs_readdir がボトルネックの場合、`STATE D` で、かつ、`/proc/$pid/stack` を眺めて vfs_readdir しているなら、で判定可能そう
 * vfs_readdir している間は、mkdir, open, 等々、ディレクトリエントリを操作が排他されるよね

```
int vfs_readdir(struct file *file, filldir_t filler, void *buf)
{
	struct inode *inode = file->f_path.dentry->d_inode;
	int res = -ENOTDIR;
	if (!file->f_op || !file->f_op->readdir)
		goto out;

	res = security_file_permission(file, MAY_READ);
	if (res)
		goto out;

	res = mutex_lock_killable(&inode->i_mutex);
	if (res)
		goto out;

	res = -ENOENT;
	if (!IS_DEADDIR(inode)) {
		res = file->f_op->readdir(file, buf, filler);
		file_accessed(file);
	}
	mutex_unlock(&inode->i_mutex);
out:
	return res;
}

EXPORT_SYMBOL(vfs_readdir);
```

file->f_op->readdir 以下は、ファイルシステム固有の実装になるので、各ファイルシステムの struct file_operations の .readdir メンバとなる関数を見ていくとよい

## tmpfs の場合

#### simple_dir_operations

ブロックデバイスを使わないファイルシステム(例: tmpfs) の場合は、 dcache_readdir を実装に使う

 * `kmem_cache_free(dentry_cache, ...)` を使ったディレクトリエントリリストの実装
 * もちろん、ページ(オンメモリ) 上にだけ存在

```
const struct file_operations simple_dir_operations = {
	.open		= dcache_dir_open,
	.release	= dcache_dir_close,
	.llseek		= dcache_dir_lseek,
	.read		= generic_read_dir,
	.readdir	= dcache_readdir,
	.fsync		= simple_sync_file,
};
```

dcache_readdir は下記の通り

 * dentry->d_subdirs をイテレートしているのが分かる
 * filp->f_pos を、ディレクトリエントリのオフセットポジションとして利用する
 * filldir でエントリ内容を埋める

```
/*
 * Directory is locked and all positive dentries in it are safe, since
 * for ramfs-type trees they can't go away without unlink() or rmdir(),
 * both impossible due to the lock on directory.
 */

int dcache_readdir(struct file * filp, void * dirent, filldir_t filldir)
{
	struct dentry *dentry = filp->f_path.dentry;
	struct dentry *cursor = filp->private_data;
	struct list_head *p, *q = &cursor->d_u.d_child;
	ino_t ino;
	int i = filp->f_pos;

	switch (i) {
		case 0:
			ino = dentry->d_inode->i_ino;
			if (filldir(dirent, ".", 1, i, ino, DT_DIR) < 0)
				break;
			filp->f_pos++;
			i++;
			/* fallthrough */
		case 1:
			ino = parent_ino(dentry);
			if (filldir(dirent, "..", 2, i, ino, DT_DIR) < 0)
				break;
			filp->f_pos++;
			i++;
			/* fallthrough */
		default:
			spin_lock(&dcache_lock);
			if (filp->f_pos == 2)
				list_move(q, &dentry->d_subdirs);

			for (p=q->next; p != &dentry->d_subdirs; p=p->next) { ★
				struct dentry *next;
				next = list_entry(p, struct dentry, d_u.d_child);
				if (d_unhashed(next) || !next->d_inode)
					continue;

				spin_unlock(&dcache_lock);
				if (filldir(dirent, next->d_name.name,  ★
					    next->d_name.len, filp->f_pos, 
					    next->d_inode->i_ino, 
					    dt_type(next->d_inode)) < 0)
					return 0;
				spin_lock(&dcache_lock);
				/* next is still alive */
				list_move(q, p);
				p = q;
				filp->f_pos++;
			}
			spin_unlock(&dcache_lock);
	}
	return 0;
}
```

ブロックデバイスベースのファイルシステムでも、同様のパターンで実装がされているとして、読めそう

## ext2 の場合

#### ext2_readdir

 * 実装が簡単そうなので、 ext2 で眺めてみます。
 * さすがに dcache_readdir よりは複雑だけど、イテレートしてエントリを求めているのはソースの構造的に分かる

```c
static int
ext2_readdir (struct file * filp, void * dirent, filldir_t filldir)
{
	loff_t pos = filp->f_pos;
	struct inode *inode = filp->f_path.dentry->d_inode;
	struct super_block *sb = inode->i_sb;
	unsigned int offset = pos & ~PAGE_CACHE_MASK;
	unsigned long n = pos >> PAGE_CACHE_SHIFT;
	unsigned long npages = dir_pages(inode);
	unsigned chunk_mask = ~(ext2_chunk_size(inode)-1);
	unsigned char *types = NULL;
	int need_revalidate = filp->f_version != inode->i_version;

	if (pos > inode->i_size - EXT2_DIR_REC_LEN(1))
		return 0;

	if (EXT2_HAS_INCOMPAT_FEATURE(sb, EXT2_FEATURE_INCOMPAT_FILETYPE))
		types = ext2_filetype_table;

	for ( ; n < npages; n++, offset = 0) {
		char *kaddr, *limit;
		ext2_dirent *de;
		struct page *page = ext2_get_page(inode, n, 0);

		if (IS_ERR(page)) {
			ext2_error(sb, __func__,
				   "bad page in #%lu",
				   inode->i_ino);
			filp->f_pos += PAGE_CACHE_SIZE - offset;
			return PTR_ERR(page);
		}
		kaddr = page_address(page);
		if (unlikely(need_revalidate)) {
			if (offset) {
				offset = ext2_validate_entry(kaddr, offset, chunk_mask);
				filp->f_pos = (n<<PAGE_CACHE_SHIFT) + offset;
			}
			filp->f_version = inode->i_version;
			need_revalidate = 0;
		}
		de = (ext2_dirent *)(kaddr+offset);
		limit = kaddr + ext2_last_byte(inode, n) - EXT2_DIR_REC_LEN(1);
		for ( ;(char*)de <= limit; de = ext2_next_entry(de)) {
			if (de->rec_len == 0) {
				ext2_error(sb, __func__,
					"zero-length directory entry");
				ext2_put_page(page);
				return -EIO;
			}
			if (de->inode) {
				int over;
				unsigned char d_type = DT_UNKNOWN;

				if (types && de->file_type < EXT2_FT_MAX)
					d_type = types[de->file_type];

				offset = (char *)de - kaddr;
				over = filldir(dirent, de->name, de->name_len,
						(n<<PAGE_CACHE_SHIFT) | offset,
						le32_to_cpu(de->inode), d_type);
				if (over) {
					ext2_put_page(page);
					return 0;
				}
			}
			filp->f_pos += ext2_rec_len_from_disk(de->rec_len);
		}
		ext2_put_page(page);
	}
	return 0;
}
```

```c
static struct page * ext2_get_page(struct inode *dir, unsigned long n,
				   int quiet)
{
	struct address_space *mapping = dir->i_mapping;
	struct page *page = read_mapping_page(mapping, n, NULL);
	if (!IS_ERR(page)) {
		kmap(page);
		if (!PageChecked(page))
			ext2_check_page(page, quiet);
		if (PageError(page))
			goto fail;
	}
	return page;

fail:
	ext2_put_page(page);
	return ERR_PTR(-EIO);
}
```

## ext3, ext4

ext3, ext4 の場合は、 htree ? かどうかでイテレートの方法が異なる

```c
/**
 * Check if the given dir-inode refers to an htree-indexed directory
 * (or a directory which chould potentially get coverted to use htree
 * indexing).
 *
 * Return 1 if it is a dx dir, 0 if not
 */
static int is_dx_dir(struct inode *inode)
{
	struct super_block *sb = inode->i_sb;

	if (EXT4_HAS_COMPAT_FEATURE(inode->i_sb,
		     EXT4_FEATURE_COMPAT_DIR_INDEX) &&
	    ((ext4_test_inode_flag(inode, EXT4_INODE_INDEX)) ||
	     ((inode->i_size >> sb->s_blocksize_bits) == 1)))
		return 1;

	return 0;
}
```

----

 * buffer /page cahce どっち?
 * buffer の内訳

```
tmpfs <---> swap_cache <---> swap デバイス
```

swap_cache は、tmpfs と swap デバイスの中間状態に位置するデータ

 * swap デバイスへ swapout して I/O待ち状態
 * swap デバイスから swapin して I/O待ち状態
 
つまり、swap デバイスとの I/O が発生している場合に、現れるはず
