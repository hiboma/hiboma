
journal モードは下記の定数で定義される

``c
/*
 * Ext4 inode journal modes
 */
#define EXT4_INODE_JOURNAL_DATA_MODE	0x01 /* journal data mode */
#define EXT4_INODE_ORDERED_DATA_MODE	0x02 /* ordered data mode */
#define EXT4_INODE_WRITEBACK_DATA_MODE	0x04 /* writeback data mode */
```

journal モードは `struct superblock -> struct ext4_sb_info` に保持する

```c
static inline int ext4_inode_journal_mode(struct inode *inode)
{
	if (EXT4_JOURNAL(inode) == NULL)
		return EXT4_INODE_WRITEBACK_DATA_MODE;	/* writeback */
	/* We do not support data journalling with delayed allocation */
	if (!S_ISREG(inode->i_mode) ||
	    test_opt(inode->i_sb, DATA_FLAGS) == EXT4_MOUNT_JOURNAL_DATA)
		return EXT4_INODE_JOURNAL_DATA_MODE;	/* journal data */
	if ((EXT4_I(inode)->i_flags & EXT4_JOURNAL_DATA_FL) &&
	    !test_opt(inode->i_sb, DELALLOC))
		return EXT4_INODE_JOURNAL_DATA_MODE;	/* journal data */
	if (test_opt(inode->i_sb, DATA_FLAGS) == EXT4_MOUNT_ORDERED_DATA)
		return EXT4_INODE_ORDERED_DATA_MODE;	/* ordered */
	if (test_opt(inode->i_sb, DATA_FLAGS) == EXT4_MOUNT_WRITEBACK_DATA)
		return EXT4_INODE_WRITEBACK_DATA_MODE;	/* writeback */
	else
		BUG();
}

// マクロを展開するとこんなん。 s_mount_opt に持っている
//#define test_opt(sb, opt)		(EXT4_SB(sb)->s_mount_opt & \
//					 EXT4_MOUNT_##opt)
```

ジャーナルモードの判定用関数

```c
static inline int ext4_should_journal_data(struct inode *inode)
{
	return ext4_inode_journal_mode(inode) & EXT4_INODE_JOURNAL_DATA_MODE;
}

static inline int ext4_should_order_data(struct inode *inode)
{
	return ext4_inode_journal_mode(inode) & EXT4_INODE_ORDERED_DATA_MODE;
}

static inline int ext4_should_writeback_data(struct inode *inode)
{
	return ext4_inode_journal_mode(inode) & EXT4_INODE_WRITEBACK_DATA_MODE;
}
```

判定用の関数は下記のように呼びだされている

```
ext4_should_journal_data  156 fs/ext4/file.c   		if (!ext4_should_journal_data(inode))
ext4_should_journal_data   87 fs/ext4/fsync.c  	if (ext4_should_journal_data(inode))
ext4_should_journal_data  103 fs/ext4/inode.c  	    (!is_metadata && !ext4_should_journal_data(inode))) {
ext4_should_journal_data 1605 fs/ext4/inode.c  	if (!ext4_should_journal_data(inode))
ext4_should_journal_data 2825 fs/ext4/inode.c  	if (PageChecked(page) && ext4_should_journal_data(inode)) {
ext4_should_journal_data 2962 fs/ext4/inode.c  		BUG_ON(ext4_should_journal_data(inode));
ext4_should_journal_data 4119 fs/ext4/inode.c  	if (ext4_should_journal_data(inode)) {
ext4_should_journal_data 4131 fs/ext4/inode.c  	if (ext4_should_journal_data(inode)) {
ext4_should_journal_data 5629 fs/ext4/inode.c  	if (ext4_should_journal_data(inode))
ext4_should_journal_data 3954 fs/ext4/super.c  	    ext4_should_journal_data(nd.dentry->d_inode)) {
ext4_should_order_data  223 fs/ext4/inode.c  	if (ext4_should_order_data(inode))
ext4_should_order_data 2340 fs/ext4/inode.c  	if (ext4_should_order_data(mpd->inode)) {
ext4_should_order_data 3252 fs/ext4/inode.c  				if (ext4_should_order_data(inode))
ext4_should_order_data 4134 fs/ext4/inode.c  		if (ext4_should_order_data(inode))
ext4_should_order_data 5459 fs/ext4/inode.c  		if (ext4_should_order_data(inode)) {
ext4_should_writeback_data 2834 fs/ext4/inode.c  	if (test_opt(inode->i_sb, NOBH) && ext4_should_writeback_data(inode))
ext4_should_writeback_data 4072 fs/ext4/inode.c  	     ext4_should_writeback_data(inode) && PageUptodate(page)) {
ext4_should_writeback_data 4770 fs/ext4/mballoc.c 	if (!ext4_should_writeback_data(inode)```
```

address_space_operations は journal モードごとに別れる。 da = delalloc

```
static const struct address_space_operations_ext ext4_ordered_aops = {
	.orig_aops.readpage		= ext4_readpage,
	.orig_aops.readpages		= ext4_readpages,
	.orig_aops.writepage		= ext4_writepage,
	.orig_aops.sync_page		= block_sync_page,
	.write_begin			= ext4_write_begin,
	.write_end			= ext4_ordered_write_end,
	.orig_aops.bmap			= ext4_bmap,
	.orig_aops.invalidatepage	= ext4_invalidatepage,
	.orig_aops.releasepage		= ext4_releasepage,
	.orig_aops.direct_IO		= ext4_direct_IO,
	.orig_aops.migratepage		= buffer_migrate_page,
};

static const struct address_space_operations_ext ext4_writeback_aops = {
	.orig_aops.readpage		= ext4_readpage,
	.orig_aops.readpages		= ext4_readpages,
	.orig_aops.writepage		= ext4_writepage,
	.orig_aops.sync_page		= block_sync_page,
	.write_begin			= ext4_write_begin,
	.write_end			= ext4_writeback_write_end,
	.orig_aops.bmap			= ext4_bmap,
	.orig_aops.invalidatepage	= ext4_invalidatepage,
	.orig_aops.releasepage		= ext4_releasepage,
	.orig_aops.direct_IO		= ext4_direct_IO,
	.orig_aops.migratepage		= buffer_migrate_page,
};

static const struct address_space_operations_ext ext4_journalled_aops = {
	.orig_aops.readpage		= ext4_readpage,
	.orig_aops.readpages		= ext4_readpages,
	.orig_aops.writepage		= ext4_writepage,
	.orig_aops.sync_page		= block_sync_page,
	.write_begin			= ext4_write_begin,
	.write_end			= ext4_journalled_write_end,
	.orig_aops.set_page_dirty	= ext4_journalled_set_page_dirty,
	.orig_aops.bmap			= ext4_bmap,
	.orig_aops.invalidatepage	= ext4_invalidatepage,
	.orig_aops.releasepage		= ext4_releasepage,
};

static const struct address_space_operations_ext ext4_da_aops = {
	.orig_aops.readpage		= ext4_readpage,
	.orig_aops.readpages		= ext4_readpages,
	.orig_aops.writepage		= ext4_writepage,
	.orig_aops.writepages		= ext4_da_writepages,
	.orig_aops.sync_page		= block_sync_page,
	.write_begin			= ext4_da_write_begin,
	.write_end			= ext4_da_write_end,
	.orig_aops.bmap			= ext4_bmap,
	.orig_aops.invalidatepage	= ext4_da_invalidatepage,
	.orig_aops.releasepage		= ext4_releasepage,
	.orig_aops.direct_IO		= ext4_direct_IO,
	.orig_aops.migratepage		= buffer_migrate_page,
};
```