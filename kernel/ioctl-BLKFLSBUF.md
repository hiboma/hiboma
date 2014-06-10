# ioctl + BLKFLSBUF

```c
int blkdev_ioctl(struct block_device *bdev, fmode_t mode, unsigned cmd,
			unsigned long arg)
{
	struct gendisk *disk = bdev->bd_disk;
	struct backing_dev_info *bdi;
	loff_t size;
	int ret, n;

	switch(cmd) {
	case BLKFLSBUF:
		if (!capable(CAP_SYS_ADMIN))
			return -EACCES;

		ret = __blkdev_driver_ioctl(bdev, mode, cmd, arg);
		/* -EINVAL to handle old uncorrected drivers */
		if (ret != -EINVAL && ret != -ENOTTY)
			return ret;

		lock_kernel();
		fsync_bdev(bdev);
		invalidate_bdev(bdev);
		unlock_kernel();
		return 0;

// ...
```