# ext4 の i_crtime

ext4_inode には i_crtime なるフィールドがある。ファイルの **作成時刻** らしい

```c
/*
 * Structure of an inode on the disk
 */
struct ext4_inode {
	__le16	i_mode;		/* File mode */
	__le16	i_uid;		/* Low 16 bits of Owner Uid */
	__le32	i_size_lo;	/* Size in bytes */
	__le32	i_atime;	/* Access time */
	__le32	i_ctime;	/* Inode Change time */
	__le32	i_mtime;	/* Modification time */
	__le32	i_dtime;	/* Deletion Time */

//...

	__le32  i_crtime;       /* File Creation time */
	__le32  i_crtime_extra; /* extra FileCreationtime (nsec << 2 | epoch) */
```

stat(2) では確認できないので、 debugfs を使う

```
$ sudo debugfs -R 'stat /tmp' /dev/mapper/VolGroup-lv_root
debugfs 1.41.12 (17-May-2010)
Inode: 2490369   Type: directory    Mode:  0777   Flags: 0x80000
Generation: 4290620196    Version: 0x00000000:00000936
User:     0   Group:     0   Size: 4096
File ACL: 0    Directory ACL: 0
Links: 6   Blockcount: 8
Fragment:  Address: 0    Number: 0    Size: 0
 ctime: 0x53f4acff:16ab6d50 -- Wed Aug 20 23:13:19 2014
 atime: 0x53f4acf4:3670b348 -- Wed Aug 20 23:13:08 2014
 mtime: 0x53f4acff:16ab6d50 -- Wed Aug 20 23:13:19 2014
crtime: 0x529d6b90:6b59f21c -- Tue Dec  3 14:26:40 2013 # <= これ
Size of extra inode fields: 28
Extended attributes stored in inode body: 
  selinux = "system_u:object_r:tmp_t:s0\000" (27)
EXTENTS:
(0): 9969696
```