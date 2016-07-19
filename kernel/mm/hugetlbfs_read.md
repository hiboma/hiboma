## hugetlbfs_read

hugetlbfs_read is set to a `.read` method of hugetlbfs_file_operations

```
const struct file_operations hugetlbfs_file_operations = {
	.read			= hugetlbfs_read,
	.mmap			= hugetlbfs_file_mmap,
	.fsync			= noop_fsync,
	.get_unmapped_area	= hugetlb_get_unmapped_area,
	.llseek		= default_llseek,
};
```

When some process do read(2) a file on hugetlbfs, vfs_read call hugetlbfs_read.

```c
/*
 * Support for read() - Find the page attached to f_mapping and copy out the
 * data. Its *very* similar to do_generic_mapping_read(), we can't use that
 * since it has PAGE_CACHE_SIZE assumptions.
 */
static ssize_t hugetlbfs_read(struct file *filp, char __user *buf,
			      size_t len, loff_t *ppos)
{
	struct hstate *h = hstate_file(filp);
	struct address_space *mapping = filp->f_mapping;
	struct inode *inode = mapping->host;
	unsigned long index = *ppos >> huge_page_shift(h);
	unsigned long offset = *ppos & ~huge_page_mask(h);
	unsigned long end_index;
	loff_t isize;
	ssize_t retval = 0;

	/* validate length */
	if (len == 0)
		goto out;

	for (;;) {
		struct page *page;
		unsigned long nr, ret;
		int ra;

		/* nr is the maximum number of bytes to copy from this page */
		nr = huge_page_size(h);
		isize = i_size_read(inode);
		if (!isize)
			goto out;
		end_index = (isize - 1) >> huge_page_shift(h);
		if (index >= end_index) {
			if (index > end_index)
				goto out;
			nr = ((isize - 1) & ~huge_page_mask(h)) + 1;
			if (nr <= offset)
				goto out;
		}
		nr = nr - offset;

		/* Find the page */
		page = find_lock_page(mapping, index);
		if (unlikely(page == NULL)) {
			/*
			 * We have a HOLE, zero out the user-buffer for the
			 * length of the hole or request.
			 */
			ret = len < nr ? len : nr;
			if (clear_user(buf, ret))
				ra = -EFAULT;
			else
				ra = 0;
		} else {
			unlock_page(page);

			/*
			 * We have the page, copy it to user space buffer.
			 */
			ra = hugetlbfs_read_actor(page, offset, buf, len, nr);
			ret = ra;
			page_cache_release(page);
		}
		if (ra < 0) {
			if (retval == 0)
				retval = ra;
			goto out;
		}

		offset += ret;
		retval += ret;
		len -= ret;
		index += offset >> huge_page_shift(h);
		offset &= ~huge_page_mask(h);

		/* short read or no more work */
		if ((ret != nr) || (len == 0))
			break;
	}
out:
	*ppos = ((loff_t)index << huge_page_shift(h)) + offset;
	return retval;
}
```

## hugetlbfs_read_actor

```
static int
hugetlbfs_read_actor(struct page *page, unsigned long offset,
			char __user *buf, unsigned long count,
			unsigned long size)
{
	char *kaddr;
	unsigned long left, copied = 0;
	int i, chunksize;

	if (size > count)
		size = count;

	/* Find which 4k chunk and offset with in that chunk */
	i = offset >> PAGE_CACHE_SHIFT;
	offset = offset & ~PAGE_CACHE_MASK;

	while (size) {
		chunksize = PAGE_CACHE_SIZE;
		if (offset)
			chunksize -= offset;
		if (chunksize > size)
			chunksize = size;
		kaddr = kmap(&page[i]);
		left = __copy_to_user(buf, kaddr + offset, chunksize);
		kunmap(&page[i]);
		if (left) {
			copied += (chunksize - left);
			break;
		}
		offset = 0;
		size -= chunksize;
		buf += chunksize;
		copied += chunksize;
		i++;
	}
	return copied ? copied : -EFAULT;
}
```

## memo

 * HugePages への write(2), read(2), mmap(2) インタフェース
 * システムコールのサイズ、オフセットを HugePages を探す際のオフセットに置き換える
