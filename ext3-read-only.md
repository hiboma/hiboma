## とある Remounting filesystem read-only のログ

``` 
 Mar 18 13:27:44 ***** kernel: ata6.00: exception Emask 0x0 SAct 0x3f SErr 0x0 action 0x0
Mar 18 13:27:44 ***** kernel: ata6.00: irq_stat 0x40000008
Mar 18 13:27:44 ***** kernel: ata6.00: cmd 60/08:00:d7:01:64/00:00:11:00:00/40 tag 0 ncq 4096 in
Mar 18 13:27:44 ***** kernel:          res 41/40:00:da:01:64/00:00:11:00:00/40 Emask 0x409 (media error) <F>
Mar 18 13:27:44 ***** kernel: ata6.00: status: { DRDY ERR }
Mar 18 13:27:44 ***** kernel: ata6.00: error: { UNC }
Mar 18 13:27:44 ***** kernel: ata6.00: configured for UDMA/133
Mar 18 13:27:44 ***** kernel: ata6: EH complete
Mar 18 13:27:44 ***** kernel: SCSI device sdf: 1953525168 512-byte hdwr sectors (1000205 MB)
Mar 18 13:27:44 ***** kernel: sdf: Write Protect is off
Mar 18 13:27:44 ***** kernel: SCSI device sdf: drive cache: write back

----

Mar 18 14:01:31 ***** kernel: ata6.00: exception Emask 0x0 SAct 0x7 SErr 0x0 action 0x0
Mar 18 14:01:31 ***** kernel: ata6.00: irq_stat 0x40000008
Mar 18 14:01:31 ***** kernel: ata6.00: cmd 60/08:00:d7:01:64/00:00:11:00:00/40 tag 0 ncq 4096 in
Mar 18 14:01:31 ***** kernel:          res 41/40:00:da:01:64/00:00:11:00:00/40 Emask 0x409 (media error) <F>
Mar 18 14:01:31 ***** kernel: ata6.00: status: { DRDY ERR }
Mar 18 14:01:31 ***** kernel: ata6.00: error: { UNC }
Mar 18 14:01:31 ***** kernel: ata6.00: configured for UDMA/133
Mar 18 14:01:31 ***** kernel: sd 5:0:0:0: Unhandled sense code
Mar 18 14:01:31 ***** kernel: sd 5:0:0:0: SCSI error: return code = 0x08000002
Mar 18 14:01:31 ***** kernel: Result: hostbyte=DID_OK driverbyte=DRIVER_SENSE,SUGGEST_OK
Mar 18 14:01:31 ***** kernel: sdf: Current [descriptor]: sense key: Medium Error
Mar 18 14:01:31 ***** kernel:     Add. Sense: Unrecovered read error - auto reallocate failed
Mar 18 14:01:31 ***** kernel: 
Mar 18 14:01:31 ***** kernel: Descriptor sense data with sense descriptors (in hex):
Mar 18 14:01:31 ***** kernel:         72 03 11 04 00 00 00 0c 00 0a 80 00 00 00 00 00 
Mar 18 14:01:31 ***** kernel:         11 64 01 da 
Mar 18 14:01:31 ***** kernel: EXT3-fs error (device dm-0): ext3_get_inode_loc: <6>ata6: EH complete
Mar 18 14:01:31 ***** kernel: SCSI device sdf: 1953525168 512-byte hdwr sectors (1000205 MB)
Mar 18 14:01:31 ***** kernel: sdf: Write Protect is off
Mar 18 14:01:31 ***** kernel: SCSI device sdf: drive cache: write back
Mar 18 14:01:31 ***** kernel: unable to read inode block - inode=384516154, block=769032195
Mar 18 14:01:31 ***** kernel: EXT3-fs error (device dm-0): ext3_get_inode_loc: unable to read inode block - inode=384516130, block=769032195

——

Mar 18 14:34:59 ***** kernel: ata6.00: cmd 60/08:00:d7:01:64/00:00:11:00:00/40 tag 0 ncq 4096 in
Mar 18 14:34:59 ***** kernel:          res 41/40:00:da:01:64/00:00:11:00:00/40 Emask 0x409 (media error) <F>
Mar 18 14:34:59 ***** kernel: ata6.00: status: { DRDY ERR }
Mar 18 14:34:59 ***** kernel: ata6.00: error: { UNC }
Mar 18 14:34:59 ***** kernel: ata6.00: configured for UDMA/133
Mar 18 14:34:59 ***** kernel: sd 5:0:0:0: Unhandled sense code
Mar 18 14:34:59 ***** kernel: sd 5:0:0:0: SCSI error: return code = 0x08000002
Mar 18 14:34:59 ***** kernel: Result: hostbyte=DID_OK driverbyte=DRIVER_SENSE,SUGGEST_OK
Mar 18 14:34:59 ***** kernel: sdf: Current [descriptor]: sense key: Medium Error
Mar 18 14:34:59 ***** kernel:     Add. Sense: Unrecovered read error - auto reallocate failed
Mar 18 14:34:59 ***** kernel: 
Mar 18 14:34:59 ***** kernel: Descriptor sense data with sense descriptors (in hex):
Mar 18 14:34:59 ***** kernel:         72 03 11 04 00 00 00 0c 00 0a 80 00 00 00 00 00 
Mar 18 14:34:59 ***** kernel:         11 64 01 da 
Mar 18 14:34:59 ***** kernel: ata6: EH complete
Mar 18 14:34:59 ***** kernel: EXT3-fs error (device dm-0): ext3_get_inode_loc: <2>EXT3-fs error (device dm-0): ext3_get_inode_loc: unable to read inode block - inode=384516154, block=769032195
Mar 18 14:34:59 ***** kernel: Aborting journal on device dm-0.
Mar 18 14:34:59 ***** kernel: unable to read inode block - inode=384516130, block=769032195
Mar 18 14:34:59 ***** kernel: SCSI device sdf: 1953525168 512-byte hdwr sectors (1000205 MB)
Mar 18 14:34:59 ***** kernel: sdf: Write Protect is off
Mar 18 14:34:59 ***** kernel: SCSI device sdf: drive cache: write back
Mar 18 14:34:59 ***** kernel: ext3_abort called.
Mar 18 14:34:59 ***** kernel: EXT3-fs error (device dm-0): ext3_journal_start_sb: Detected aborted journal
Mar 18 14:34:59 ***** kernel: Remounting filesystem read-only
```

## Remounting filesystem read-only を出しているコード

ext3_abort の中だった

 * ext3_error より強い
 * ログ操作してて journal IO エラー、ENOMEM などリカバリ不可能な場合に呼び出される

```c
/*
 * ext3_abort is a much stronger failure handler than ext3_error.  The
 * abort function may be used to deal with unrecoverable failures such
 * as journal IO errors or ENOMEM at a critical moment in log management.
 *
 * We unconditionally force the filesystem into an ABORT|READONLY state,
 * unless the error response on the fs has been set to panic in which
 * case we take the easy way out and panic immediately.
 */

void ext3_abort (struct super_block * sb, const char * function,
		 const char * fmt, ...)
{
	va_list args;

	printk (KERN_CRIT "ext3_abort called.\n");

	va_start(args, fmt);
	printk(KERN_CRIT "EXT3-fs error (device %s): %s: ",sb->s_id, function);
	vprintk(fmt, args);
	printk("\n");
	va_end(args);

	if (test_opt(sb, ERRORS_PANIC))
		panic("EXT3-fs panic from previous error\n");

	if (sb->s_flags & MS_RDONLY)
		return;

	printk(KERN_CRIT "Remounting filesystem read-only\n");
	EXT3_SB(sb)->s_mount_state |= EXT3_ERROR_FS;
	sb->s_flags |= MS_RDONLY;
	EXT3_SB(sb)->s_mount_opt |= EXT3_MOUNT_ABORT;
	journal_abort(EXT3_SB(sb)->s_journal, -EIO);
}
```