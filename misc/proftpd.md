# proftpd

## fadvise ???

 * サーバからクライアントにファイルを転送するのは RETRコマンド
 * modules/mod_xfer.c の `MODRET xfer_retr(cmd_rec *cmd)` で実装されている
 * fadvise(2) できる?

### [posix_fadvise(2)](http://kazmax.zpp.jp/cmd/p/posix_fadvise.2.html)

 * POSIX_FADV_NORMAL, POSIX_FADV_RANDOM, POSIX_FADV_SEQUENTIAL
   * backing_dev_info の ra_pages (readahed) の数値をいじってる
 * POSIX_FADV_DONTNEED
   * [filemap_flush](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L256])
   * [invalidate_mapping_pages](http://lxr.free-electrons.com/source/mm/truncate.c?v=2.6.32#L319)
   * read(2) -> ページキャッシュ埋まる -> POSIX_FADV_DONTNEED でページキャッシュを破棄

 * POSIX_FADV_NOREUSE はどう動くのかが分からん

 ```c
/*
 * POSIX_FADV_WILLNEED could set PG_Referenced, and POSIX_FADV_NOREUSE could
 * deactivate the pages and clear PG_Referenced.
 */
SYSCALL_DEFINE(fadvise64_64)(int fd, loff_t offset, loff_t len, int advice)
{
	struct file *file = fget(fd);
	struct address_space *mapping;
	struct backing_dev_info *bdi;
	loff_t endbyte;			/* inclusive */
	pgoff_t start_index;
	pgoff_t end_index;
	unsigned long nrpages;
	int ret = 0;

	if (!file)
		return -EBADF;

	if (S_ISFIFO(file->f_path.dentry->d_inode->i_mode)) {
		ret = -ESPIPE;
		goto out;
	}

	mapping = file->f_mapping;
	if (!mapping || len < 0) {
		ret = -EINVAL;
		goto out;
	}

	if (mapping->a_ops->get_xip_mem) {
		switch (advice) {
		case POSIX_FADV_NORMAL:
		case POSIX_FADV_RANDOM:
		case POSIX_FADV_SEQUENTIAL:
		case POSIX_FADV_WILLNEED:
		case POSIX_FADV_NOREUSE:
		case POSIX_FADV_DONTNEED:
			/* no bad return value, but ignore advice */
			break;
		default:
			ret = -EINVAL;
		}
		goto out;
	}

	/* Careful about overflows. Len == 0 means "as much as possible" */
	endbyte = offset + len;
	if (!len || endbyte < len)
		endbyte = -1;
	else
		endbyte--;		/* inclusive */

	bdi = mapping->backing_dev_info;

	switch (advice) {
	case POSIX_FADV_NORMAL:
		file->f_ra.ra_pages = bdi->ra_pages;
		spin_lock(&file->f_lock);
		file->f_mode &= ~FMODE_RANDOM;
		spin_unlock(&file->f_lock);
		break;
	case POSIX_FADV_RANDOM:
		spin_lock(&file->f_lock);
		file->f_mode |= FMODE_RANDOM;
		spin_unlock(&file->f_lock);
		break;
	case POSIX_FADV_SEQUENTIAL:
		file->f_ra.ra_pages = bdi->ra_pages * 2;
		spin_lock(&file->f_lock);
		file->f_mode &= ~FMODE_RANDOM;
		spin_unlock(&file->f_lock);
		break;
	case POSIX_FADV_WILLNEED:
		if (!mapping->a_ops->readpage) {
			ret = -EINVAL;
			break;
		}

		/* First and last PARTIAL page! */
		start_index = offset >> PAGE_CACHE_SHIFT;
		end_index = endbyte >> PAGE_CACHE_SHIFT;

		/* Careful about overflow on the "+1" */
		nrpages = end_index - start_index + 1;
		if (!nrpages)
			nrpages = ~0UL;
		
		ret = force_page_cache_readahead(mapping, file,
				start_index,
				nrpages);
		if (ret > 0)
			ret = 0;
		break;
	case POSIX_FADV_NOREUSE:
		break;
	case POSIX_FADV_DONTNEED:
		if (!bdi_write_congested(mapping->backing_dev_info))
			filemap_flush(mapping);

		/* First and last FULL page! */
		start_index = (offset+(PAGE_CACHE_SIZE-1)) >> PAGE_CACHE_SHIFT;
		end_index = (endbyte >> PAGE_CACHE_SHIFT);

		if (end_index >= start_index)
			invalidate_mapping_pages(mapping, start_index,
						end_index);
		break;
	default:
		ret = -EINVAL;
	}
out:
	fput(file);
	return ret;
}
``` 

## APIメモ

 * `pr_fh_t *pr_fsio_open(const char *name, int flags)`
   * open(2) のラッパー
   * fh_fd がファイルデスクリプタかな?

```c
typedef struct fh_rec pr_fh_t;
struct fh_rec {

  /* Pool for this object's use */
  pool *fh_pool;

  int fh_fd;
  char *fh_path;

  /* Arbitrary data associated with this file. */
  void *fh_data;

  /* Pointer to the filesystem in which this file is located. */
  pr_fs_t *fh_fs;

  /* For buffer I/O on this file, should anything choose to use it. */
  pr_buffer_t *fh_buf;

  /* Hint of the optimal buffer size for IO on this file. */
  size_t fh_iosz;
};
```

