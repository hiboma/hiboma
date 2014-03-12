## fdisk

```
[vagrant@vagrant-centos65 ~]$ fdisk -h

Usage:
 fdisk [options] <disk>    change partition table
 fdisk [options] -l <disk> list partition table(s)
 fdisk -s <partition>      give partition size(s) in blocks

Options:
 -b <size>                 sector size (512, 1024, 2048 or 4096)
 -c                        switch off DOS-compatible mode
 -h                        print help
 -u <size>                 give sizes in sectors instead of cylinders
 -v                        print version
 -C <number>               specify the number of cylinders
 -H <number>               specify the number of heads
 -S <number>               specify the number of sectors per track
```

## Vagrant で HDD をアタッチ

http://momijiame.tumblr.com/post/67058805910/vagrant-vm を参考にして作業した

```ruby
      file_to_disk = "./tmp/disk.vdi"
      unless File.exist?(file_to_disk)
        vb.customize ["createhd", "--filename", file_to_disk, "--size", 1 * 1024]
      end
      vb.customize ['storageattach', :id, '--storagectl', 'SATA', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', file_to_disk]
```

アタッチしたディスクでは dmesg にログでてくる

```
$ sudo cat /var/log/dmesg | grep sdb
sd 1:0:0:0: [sdb] 2097152 512-byte logical blocks: (1.07 GB/1.00 GiB)
sd 1:0:0:0: [sdb] Write Protect is off
sd 1:0:0:0: [sdb] Mode Sense: 00 3a 00 00
sd 1:0:0:0: [sdb] Write cache: enabled, read cache: enabled, doesn't support DPO or FUA
 sdb: sda1 sda2
sd 1:0:0:0: [sdb] Attached SCSI disk
```

## usage

デバイスのデータとパーティション情報が参照できる

```
$ sudo fdisk -l /dev/sda

Disk /dev/sda: 8589 MB, 8589934592 bytes
255 heads, 63 sectors/track, 1044 cylinders
Units = cylinders of 16065 * 512 = 8225280 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x0002e245

   Device Boot      Start         End      Blocks   Id  System
/dev/sda1   *           1         966     7756800   83  Linux
Partition 1 does not end on cylinder boundary.
/dev/sda2             966        1044      627712   82  Linux swap / Solaris
```

アタッチしたばかりのディスクは何もでない

```
$ sudo fdisk -l /dev/sdb

Disk /dev/sdb: 1073 MB, 1073741824 bytes
255 heads, 63 sectors/track, 130 cylinders
Units = cylinders of 16065 * 512 = 8225280 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x00000000
```

パーティションを作ってみる

```
$ sudo fdisk /dev/sdb
Device contains neither a valid DOS partition table, nor Sun, SGI or OSF disklabel
Building a new DOS disklabel with disk identifier 0x1035cf6e.
Changes will remain in memory only, until you decide to write them.
After that, of course, the previous content won't be recoverable.

Warning: invalid flag 0x0000 of partition table 4 will be corrected by w(rite)

WARNING: DOS-compatible mode is deprecated. It's strongly recommended to
         switch off the mode (command 'c') and change display units to
         sectors (command 'u').

Command (m for help): n
Command action
   e   extended
   p   primary partition (1-4)
p
Partition number (1-4): 1
First cylinder (1-130, default 1): 
Using default value 1
Last cylinder, +cylinders or +size{K,M,G} (1-130, default 130): 
Using default value 130

Command (m for help): w
The partition table has been altered!

Calling ioctl() to re-read partition table.
Syncing disks.
```

作られた

```
[vagrant@vagrant-centos65 ~]$ sudo fdisk -l /dev/sdb

Disk /dev/sdb: 1073 MB, 1073741824 bytes
255 heads, 63 sectors/track, 130 cylinders
Units = cylinders of 16065 * 512 = 8225280 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disk identifier: 0x1035cf6e

   Device Boot      Start         End      Blocks   Id  System
/dev/sdb1               1         130     1044193+  83  Linux
```

## how to get partition info ?

fdisk はどうやってデバイスやパーティション情報を取っているのか? ___use strace !___

 * デバイスを直接 open(2) してブロックを読みとっている?
   * ~~SCSI だとか IDE だとかを判定している~~
   * パーティション情報かな? パーティション作ってないディスクだと NULL ばっかり
```
read(3, "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"..., 512) = 512
```

 * ioctl(2) で何か取れるぽい
   * ~~SCSI のドライバを眺めたらよい?~~
```
open("/dev/sdb", O_RDONLY)              = 3
uname({sys="Linux", node="vagrant-centos65.vagrantup.com", ...}) = 0
ioctl(3, BLKSSZGET, 0x7fff63cdd40c)     = 0
lseek(3, 512, SEEK_SET)                 = 512
read(3, "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"..., 512) = 512
fstat(3, {st_mode=S_IFBLK|0660, st_rdev=makedev(8, 16), ...}) = 0
ioctl(3, BLKGETSIZE64, 0x7fff63cdd4d0)  = 0
ioctl(3, BLKSSZGET, 0x7fff63cdd4dc)     = 0
ioctl(3, BLKSSZGET, 0x7fff63cdd40c)     = 0
lseek(3, 1073741312, SEEK_SET)          = 1073741312
read(3, "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"..., 512) = 512
close(3)                                = 0

/…/

read(4, "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"..., 512) = 512
fadvise64(4, 0, 0, POSIX_FADV_RANDOM)   = 0
fstat(4, {st_mode=S_IFBLK|0660, st_rdev=makedev(8, 16), ...}) = 0
uname({sys="Linux", node="vagrant-centos65.vagrantup.com", ...}) = 0
ioctl(4, BLKGETSIZE64, 0x2603850)       = 0
ioctl(4, CDROM_GET_CAPABILITY or SNDRV_SEQ_IOCTL_UNSUBSCRIBE_PORT, 0) = -1 ENOTTY (Inappropriate ioctl for device)
ioctl(4, 0x127a, 0x7fff63cdd3b8)        = 0
ioctl(4, 0x1278, 0x7fff63cdd3bc)        = 0
ioctl(4, 0x1279, 0x7fff63cdd3bc)        = 0
ioctl(4, 0x127b, 0x7fff63cdd3bc)        = 0
ioctl(4, BLKSSZGET, 0x2603868)          = 0
ioctl(4, BLKSSZGET, 0x7fff63cdd47c)     = 0
fstat(4, {st_mode=S_IFBLK|0660, st_rdev=makedev(8, 16), ...}) = 0
ioctl(4, 0x301, 0x7fff63cdd460)         = 0
ioctl(4, BLKGETSIZE64, 0x7fff63cdd448)  = 0
lseek(4, 0, SEEK_SET)                   = 0
read(4, "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"..., 8192) = 8192
```

## struct block_device

カーネルのソースを追う。block デバイス用に file_operations が登録されている

```c
const struct file_operations def_blk_fops = {
	.open		= blkdev_open,
	.release	= blkdev_close,
	.llseek		= block_llseek,
	.read		= do_sync_read,
	.write		= do_sync_write,
	.aio_read	= blkdev_aio_read,
	.aio_write	= blkdev_aio_write,
	.mmap		= generic_file_mmap,
	.fsync		= blkdev_fsync,
	.unlocked_ioctl	= block_ioctl,
#ifdef CONFIG_COMPAT
	.compat_ioctl	= compat_blkdev_ioctl,
#endif
	.splice_read	= generic_file_splice_read,
	.splice_write	= generic_file_splice_write,
};
```

.unlocked_ioctl で ioctl 用のメソッドが定義されている

## blkdev_ioctl

 * BLKGETSIZE64, BLKSSZGET などは 下記で取れる。 struct block_device bdev に格納されてる情報読んでるだけだった
 * default: で __blkdev_driver_ioctl 読んでるので、デバイスドライバの ioctl も呼び出してるな
   * struct gendisk の disk->fops->ioctl, disk->fops->locked_ioctl を呼ぶ
   * locked_ioctl は BKL = locked_kernel() 付の ioctl
```c
/*
 * always keep this in sync with compat_blkdev_ioctl() and
 * compat_blkdev_locked_ioctl()
 */
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

	case BLKROSET:
		ret = __blkdev_driver_ioctl(bdev, mode, cmd, arg);
		/* -EINVAL to handle old uncorrected drivers */
		if (ret != -EINVAL && ret != -ENOTTY)
			return ret;
		if (!capable(CAP_SYS_ADMIN))
			return -EACCES;
		if (get_user(n, (int __user *)(arg)))
			return -EFAULT;
		lock_kernel();
		set_device_ro(bdev, n);
		unlock_kernel();
		return 0;

	case BLKDISCARD: {
		uint64_t range[2];

		if (!(mode & FMODE_WRITE))
			return -EBADF;

		if (copy_from_user(range, (void __user *)arg, sizeof(range)))
			return -EFAULT;

		return blk_ioctl_discard(bdev, range[0], range[1]);
	}

	case HDIO_GETGEO: {
		struct hd_geometry geo;

		if (!arg)
			return -EINVAL;
		if (!disk->fops->getgeo)
			return -ENOTTY;

		/*
		 * We need to set the startsect first, the driver may
		 * want to override it.
		 */
		geo.start = get_start_sect(bdev);
		ret = disk->fops->getgeo(bdev, &geo);
		if (ret)
			return ret;
		if (copy_to_user((struct hd_geometry __user *)arg, &geo,
					sizeof(geo)))
			return -EFAULT;
		return 0;
	}
	case BLKRAGET:
	case BLKFRAGET:
		if (!arg)
			return -EINVAL;
		bdi = blk_get_backing_dev_info(bdev);
		if (bdi == NULL)
			return -ENOTTY;
		return put_long(arg, (bdi->ra_pages * PAGE_CACHE_SIZE) / 512);
	case BLKROGET:
		return put_int(arg, bdev_read_only(bdev) != 0);
	case BLKBSZGET: /* get block device soft block size (cf. BLKSSZGET) */
		return put_int(arg, block_size(bdev));
	case BLKSSZGET: /* get block device logical block size */
		return put_int(arg, bdev_logical_block_size(bdev));
	case BLKPBSZGET: /* get block device physical block size */
		return put_uint(arg, bdev_physical_block_size(bdev));
	case BLKIOMIN:
		return put_uint(arg, bdev_io_min(bdev));
	case BLKIOOPT:
		return put_uint(arg, bdev_io_opt(bdev));
	case BLKALIGNOFF:
		return put_int(arg, bdev_alignment_offset(bdev));
	case BLKDISCARDZEROES:
		return put_uint(arg, bdev_discard_zeroes_data(bdev));
	case BLKSECTGET:
		return put_ushort(arg, queue_max_sectors(bdev_get_queue(bdev)));
	case BLKRASET:
	case BLKFRASET:
		if(!capable(CAP_SYS_ADMIN))
			return -EACCES;
		bdi = blk_get_backing_dev_info(bdev);
		if (bdi == NULL)
			return -ENOTTY;
		bdi->ra_pages = (arg * 512) / PAGE_CACHE_SIZE;
		return 0;
	case BLKBSZSET:
		/* set the logical block size */
		if (!capable(CAP_SYS_ADMIN))
			return -EACCES;
		if (!arg)
			return -EINVAL;
		if (get_user(n, (int __user *) arg))
			return -EFAULT;
		if (!(mode & FMODE_EXCL) && bd_claim(bdev, &bdev) < 0)
			return -EBUSY;
		ret = set_blocksize(bdev, n);
		if (!(mode & FMODE_EXCL))
			bd_release(bdev);
		return ret;
	case BLKPG:
		lock_kernel();
		ret = blkpg_ioctl(bdev, (struct blkpg_ioctl_arg __user *) arg);
		unlock_kernel();
		break;
	case BLKRRPART:
		lock_kernel();
		ret = blkdev_reread_part(bdev);
		unlock_kernel();
		break;
	case BLKGETSIZE:
		size = i_size_read(bdev->bd_inode);
		if ((size >> 9) > ~0UL)
			return -EFBIG;
		return put_ulong(arg, size >> 9);
	case BLKGETSIZE64:
		return put_u64(arg, i_size_read(bdev->bd_inode));
	case BLKTRACESTART:
	case BLKTRACESTOP:
	case BLKTRACESETUP:
	case BLKTRACETEARDOWN:
		lock_kernel();
		ret = blk_trace_ioctl(bdev, cmd, (char __user *) arg);
		unlock_kernel();
		break;
	default:
		ret = __blkdev_driver_ioctl(bdev, mode, cmd, arg);
	}
	return ret;
}
EXPORT_SYMBOL_GPL(blkdev_ioctl);
```

## mkfs しておしまい

```
$ sudo mkfs -t ext4 /dev/sdb1
mke2fs 1.41.12 (17-May-2010)
Filesystem label=
OS type: Linux
Block size=4096 (log=2)
Fragment size=4096 (log=2)
Stride=0 blocks, Stripe width=0 blocks
65280 inodes, 261048 blocks
13052 blocks (5.00%) reserved for the super user
First data block=0
Maximum filesystem blocks=268435456
8 block groups
32768 blocks per group, 32768 fragments per group
8160 inodes per group
Superblock backups stored on blocks: 
	32768, 98304, 163840, 229376

Writing inode tables: done                            
Creating journal (4096 blocks): done
Writing superblocks and filesystem accounting information: done

This filesystem will be automatically checked every 25 mounts or
180 days, whichever comes first.  Use tune2fs -c or -i to override.
```