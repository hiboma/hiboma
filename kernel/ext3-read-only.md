## とある Remounting filesystem read-only のログ

smartctl -a /dev/sd*

```
SMART Attributes Data Structure revision number: 16
Vendor Specific SMART Attributes with Thresholds:
ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
  1 Raw_Read_Error_Rate     0x002f   200   200   051    Pre-fail  Always       -       278
  3 Spin_Up_Time            0x0027   229   224   021    Pre-fail  Always       -       8550
  4 Start_Stop_Count        0x0032   100   100   000    Old_age   Always       -       24
  5 Reallocated_Sector_Ct   0x0033   200   200   140    Pre-fail  Always       -       0
  7 Seek_Error_Rate         0x002e   200   200   000    Old_age   Always       -       0
  9 Power_On_Hours          0x0032   047   047   000    Old_age   Always       -       39173
 10 Spin_Retry_Count        0x0032   100   253   000    Old_age   Always       -       0
 11 Calibration_Retry_Count 0x0032   100   253   000    Old_age   Always       -       0
 12 Power_Cycle_Count       0x0032   100   100   000    Old_age   Always       -       22
192 Power-Off_Retract_Count 0x0032   200   200   000    Old_age   Always       -       15
193 Load_Cycle_Count        0x0032   200   200   000    Old_age   Always       -       24
194 Temperature_Celsius     0x0022   126   112   000    Old_age   Always       -       24
196 Reallocated_Event_Count 0x0032   200   200   000    Old_age   Always       -       0
197 Current_Pending_Sector  0x0032   200   200   000    Old_age   Always       -       9
198 Offline_Uncorrectable   0x0030   200   200   000    Old_age   Offline      -       0
199 UDMA_CRC_Error_Count    0x0032   200   200   000    Old_age   Always       -       0
200 Multi_Zone_Error_Rate   0x0008   200   200   000    Old_age   Offline      -       0

SMART Error Log Version: 1
No Errors Logged

SMART Self-test log structure revision number 1
Num  Test_Description    Status                  Remaining  LifeTime(hours)  LBA_of_first_error
# 1  Short offline       Completed: read failure       90%     39166         291766746
# 2  Short offline       Completed: read failure       90%     11961         182190570
# 3  Short offline       Completed: read failure       90%     11951         182190570
# 4  Short offline       Completed: read failure       90%     11329         182190570
# 5  Short offline       Completed: read failure       90%     11329         182190570

SMART Selective self-test log data structure revision number 1
 SPAN  MIN_LBA  MAX_LBA  CURRENT_TEST_STATUS
    1        0        0  Not_testing
    2        0        0  Not_testing
    3        0        0  Not_testing
    4        0        0  Not_testing
    5        0        0  Not_testing
Selective self-test flags (0x0):
  After scanning selected spans, do NOT read-scan remainder of disk.
If Selective self-test is pending on power-up, resume after 0 minute delay.
```

## /var/log/messages

```
# read-only になってない。journal 無しだから?

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

# ext3_abort で read-only になった。 ジャナール有りだから?

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
Mar 18 14:34:59 ***** kernel: EXT3-fs error (device dm-0): ext3_get_inode_loc: unable to read inode block - inode=384516154, block=769032195
Mar 18 14:34:59 ***** kernel: Aborting journal on device dm-0.
Mar 18 14:34:59 ***** kernel: unable to read inode block - inode=384516130, block=769032195
Mar 18 14:34:59 ***** kernel: SCSI device sdf: 1953525168 512-byte hdwr sectors (1000205 MB)
Mar 18 14:34:59 ***** kernel: sdf: Write Protect is off
Mar 18 14:34:59 ***** kernel: SCSI device sdf: drive cache: write back
Mar 18 14:34:59 ***** kernel: ext3_abort called.
Mar 18 14:34:59 ***** kernel: EXT3-fs error (device dm-0): ext3_journal_start_sb: Detected aborted journal
Mar 18 14:34:59 ***** kernel: Remounting filesystem read-only
```

## kernel: sdf: Current [descriptor]: sense key: Medium Error

```
Mar 18 14:34:59 ***** kernel:     Add. Sense: Unrecovered read error - auto reallocate failed
```

sense key でググると見つかる

 * http://ossmpedia.org/messages/linux/2.6.9-34.EL/14123.ja

> メディアエラーの場合は、”Medium Error”、ボリュームオーバフローの場合は、”Volume Overflow”が表示される。 メディアエラーが発生している場合は、メディアの交換やSCSIデバイスのクリーニングなどを行う。一方、ボリュームオーバフローの場合は、ハードウェアの故障やデバイスドライバの不良が考えられるため、ハードウェアの交換やパッチの適用を行う。その他該当デバイスのトラブルシューティングに従って対処を行う。

## Add. Sense: Unrecovered read error - auto reallocate failed

```c
       {0x1104, "Unrecovered read error - auto reallocate failed"},
```

drivers/scsi/constants.c にエラーコードとメッセージが書いてある

これが意味するのは下記のフォーラムあたりで確認

 * https://www.centos.org/forums/viewtopic.php?t=7577
 * http://serverfault.com/questions/407007/what-do-these-disk-errors-in-syslog-mean

> Means it found a sector that was bad and went to try to get a different one from its pool of spares and found that the pool was all used up. That shows that the drive is dying and has already used up its entire spare area. Best RMA it.

不良セクタが見つかったが 予備セクタ? を使い切ってるので再配置できかったとか何とか

## Aborting journal on device dm-0.

__journal_abort_hard の中で printk されるメッセージ

```c
/*
 * Quick version for internal journal use (doesn't lock the journal).
 * Aborts hard --- we mark the abort as occurred, but do _nothing_ else,
 * and don't attempt to make any other journal updates.
 */
void __journal_abort_hard(journal_t *journal)
{
        transaction_t *transaction;
        char b[BDEVNAME_SIZE];

        if (journal->j_flags & JFS_ABORT)
                return;

        printk(KERN_ERR "Aborting journal on device %s.\n",
                journal_dev_name(journal, b)); 

        spin_lock(&journal->j_state_lock);
        journal->j_flags |= JFS_ABORT;
        transaction = journal->j_running_transaction;
        if (transaction)
                __log_start_commit(journal, transaction->t_tid);
        spin_unlock(&journal->j_state_lock);
}
```

## EXT3-fs error (device dm-0): ext3_get_inode_loc ...

```
Mar 18 14:34:59 ***** kernel: EXT3-fs error (device dm-0): ext3_get_inode_loc: <2>EXT3-fs error (device dm-0): ext3_get_inode_loc: unable to read inode block - inode=384516154, block=769032195
Mar 18 14:34:59 ***** kernel: Aborting journal on device dm-0.
Mar 18 14:34:59 ***** kernel: unable to read inode block - inode=384516130, block=769032195
```

ext3_get_inode_loc のコード。 __ext3_get_inode_loc のラッパー

```c
int ext3_get_inode_loc(struct inode *inode, struct ext3_iloc *iloc)
{
	/* We have all inode data except xattrs in memory here. */
	return __ext3_get_inode_loc(inode, iloc,
		!(EXT3_I(inode)->i_state & EXT3_STATE_XATTR));
}
```

 __ext3_get_inode_loc のコード

 * ext3_get_inode_loc ... を printk するのは 2カ所
   * sb_getblk の後
   * wait_on_buffer の後
     * submit_bh してディスクから割り込みで復帰後

```c
/*
 * ext3_get_inode_loc returns with an extra refcount against the inode's
 * underlying buffer_head on success. If 'in_mem' is true, we have all
 * data in memory that is needed to recreate the on-disk version of this
 * inode.
 */
static int __ext3_get_inode_loc(struct inode *inode,
				struct ext3_iloc *iloc, int in_mem)
{
	ext3_fsblk_t block;
	struct buffer_head *bh;

	block = ext3_get_inode_block(inode->i_sb, inode->i_ino, iloc);
	if (!block)
		return -EIO;

    // ここ --------------------------------------------------------
	bh = sb_getblk(inode->i_sb, block);
	if (!bh) {
		ext3_error (inode->i_sb, "ext3_get_inode_loc",
				"unable to read inode block - "
				"inode=%lu, block="E3FSBLK,
				 inode->i_ino, block);
        // EIO で死ぬ         
		return -EIO;
	}
   // ここ --------------------------------------------------------

	if (!buffer_uptodate(bh)) {
		lock_buffer(bh);

		/*
		 * If the buffer has the write error flag, we have failed
		 * to write out another inode in the same block.  In this
		 * case, we don't have to read the block because we may
		 * read the old inode data successfully.
		 */
		if (buffer_write_io_error(bh) && !buffer_uptodate(bh))
			set_buffer_uptodate(bh);

		if (buffer_uptodate(bh)) {
			/* someone brought it uptodate while we waited */
			unlock_buffer(bh);
			goto has_buffer;
		}

		/*
		 * If we have all information of the inode in memory and this
		 * is the only valid inode in the block, we need not read the
		 * block.
		 */
		if (in_mem) {
			struct buffer_head *bitmap_bh;
			struct ext3_group_desc *desc;
			int inodes_per_buffer;
			int inode_offset, i;
			int block_group;
			int start;

			block_group = (inode->i_ino - 1) /
					EXT3_INODES_PER_GROUP(inode->i_sb);
			inodes_per_buffer = bh->b_size /
				EXT3_INODE_SIZE(inode->i_sb);
			inode_offset = ((inode->i_ino - 1) %
					EXT3_INODES_PER_GROUP(inode->i_sb));
			start = inode_offset & ~(inodes_per_buffer - 1);

			/* Is the inode bitmap in cache? */
			desc = ext3_get_group_desc(inode->i_sb,
						block_group, NULL);
			if (!desc)
				goto make_io;

			bitmap_bh = sb_getblk(inode->i_sb,
					le32_to_cpu(desc->bg_inode_bitmap));
			if (!bitmap_bh)
				goto make_io;

			/*
			 * If the inode bitmap isn't in cache then the
			 * optimisation may end up performing two reads instead
			 * of one, so skip it.
			 */
			if (!buffer_uptodate(bitmap_bh)) {
				brelse(bitmap_bh);
				goto make_io;
			}
			for (i = start; i < start + inodes_per_buffer; i++) {
				if (i == inode_offset)
					continue;
				if (ext3_test_bit(i, bitmap_bh->b_data))
					break;
			}
			brelse(bitmap_bh);
			if (i == start + inodes_per_buffer) {
				/* all other inodes are free, so skip I/O */
				memset(bh->b_data, 0, bh->b_size);
				set_buffer_uptodate(bh);
				unlock_buffer(bh);
				goto has_buffer;
			}
		}

make_io:
		/*
		 * There are other valid inodes in the buffer, this inode
		 * has in-inode xattrs, or we don't have this inode in memory.
		 * Read the block from disk.
		 */
		trace_ext3_load_inode(inode);
		get_bh(bh);
		bh->b_end_io = end_buffer_read_sync;

        // IO 発行
		submit_bh(READ_META, bh);

        // TASK_UNINTERRUPTIBLE
		wait_on_buffer(bh);

        // ここ --------------------------------------------------------        
		if (!buffer_uptodate(bh)) {
			ext3_error(inode->i_sb, "ext3_get_inode_loc",
					"unable to read inode block - "
					"inode=%lu, block="E3FSBLK,
					inode->i_ino, block);
			brelse(bh);
			return -EIO;
		}
       // ここ --------------------------------------------------------
	}
has_buffer:
	iloc->bh = bh;
	return 0;
}
```

## kernel: Remounting filesystem read-only

```
Mar 18 14:34:59 ***** kernel: Remounting filesystem read-only
```

ext3_abort の中で printk されて出力されているメッセージ

 * ext3_error より強い
 * ログ操作してて journal IO エラー、ENOMEM などリカバリ不可能な場合に呼び出される
 * ファイるシステムを強制的に READONLY にする
   * ERRORS_PANIC をたててると panic() する

ext3_abort が呼ばれないと READONLY にならんと見ていいのかな

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

    // ERRORS_PANIC がたっていると panic() して終わり
	if (test_opt(sb, ERRORS_PANIC))
		panic("EXT3-fs panic from previous error\n");

    // 既に MS_RDONLY なら何もしない
	if (sb->s_flags & MS_RDONLY)
		return;

    // EXT3_ERROR_FS フラグと MS_RDONLY を立てる
	printk(KERN_CRIT "Remounting filesystem read-only\n");
	EXT3_SB(sb)->s_mount_state |= EXT3_ERROR_FS;
	sb->s_flags |= MS_RDONLY;
	EXT3_SB(sb)->s_mount_opt |= EXT3_MOUNT_ABORT;
	journal_abort(EXT3_SB(sb)->s_journal, -EIO);
}
```

ext3_abort は ext3_journal_start_sb で呼び出されいる

 * ジャーナルが EIO などでコケてたら ext3_abort を呼んで Readonly にしてしまう
   * journal_t .j_flags で JFS_ABORT の有無で ジャーナルの成否を見ている
   * ジャーナルがコケた時点でそれ以降の書き込みを正しく保証出来ないから ???

```c
/*
 * Wrappers for journal_start/end.
 *
 * The only special thing we need to do here is to make sure that all
 * journal_end calls result in the superblock being marked dirty, so
 * that sync() will call the filesystem's write_super callback if
 * appropriate.
 */
handle_t *ext3_journal_start_sb(struct super_block *sb, int nblocks)
{
	journal_t *journal;

    // EROFS = Readonly Filesystem
    // superblock のフラグの有無でエラーを返される
	if (sb->s_flags & MS_RDONLY)
		return ERR_PTR(-EROFS);

	/* Special case here: if the journal has aborted behind our
	 * backs (eg. EIO in the commit thread), then we still need to
	 * take the FS itself readonly cleanly. */

     // "裏でこっそりコミットスレッドが EIO を返していた場合
     // ファイルシステムを readonly にする必要がある"
	journal = EXT3_SB(sb)->s_journal;

    // journal->j_flags & JFS_ABORT で判定している
    // jdb, jdb2 どっちか分からん
	if (is_journal_aborted(journal)) {
		ext3_abort(sb, __func__,
			   "Detected aborted journal");
		return ERR_PTR(-EROFS);
	}

	return journal_start(journal, nblocks);
}
```

