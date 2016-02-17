# /proc/sys/fs/inode-state

linux-3.10.0-327.el7.centos.x86_64

## 定義

```c
static struct ctl_table fs_table[] = {

//...

        {    
                .procname       = "inode-state",
                .data           = &inodes_stat,
                .maxlen         = 7*sizeof(int),
                .mode           = 0444,
                .proc_handler   = proc_nr_inodes,
        },   
```

```c
/*
 * Handle nr_inode sysctl
 */
#ifdef CONFIG_SYSCTL
int proc_nr_inodes(ctl_table *table, int write,
		   void __user *buffer, size_t *lenp, loff_t *ppos)
{
	inodes_stat.nr_inodes = get_nr_inodes();
	inodes_stat.nr_unused = get_nr_inodes_unused();
	return proc_dointvec(table, write, buffer, lenp, ppos);
}
#endif
```

## get_nr_inodes, get_nr_inodes_unused

per_cpu なデータを参照する

```c
static DEFINE_PER_CPU(unsigned int, nr_inodes);
static DEFINE_PER_CPU(unsigned int, nr_unused);

static int get_nr_inodes(void)
{
	int i;
	int sum = 0;
	for_each_possible_cpu(i)
		sum += per_cpu(nr_inodes, i);
	return sum < 0 ? 0 : sum;
}

static inline int get_nr_inodes_unused(void)
{
	int i;
	int sum = 0;
	for_each_possible_cpu(i)
		sum += per_cpu(nr_unused, i);
	return sum < 0 ? 0 : sum;
}
```

## nr_inodes

#### nr_inodes をインクリメントする

 * inode_init_always で nr_inodes をインクリメントしている
 * ファイルシステムの inode でなくて `struct inode` = VFS inode の数であることが分かる

```c
/**
 * inode_init_always - perform inode structure intialisation
 * @sb: superblock inode belongs to
 * @inode: inode to initialise
 *
 * These are initializations that need to be done on every inode
 * allocation as the fields are not initialised by slab allocation.
 */
int inode_init_always(struct super_block *sb, struct inode *inode)
{
	static const struct inode_operations empty_iops;
	static const struct file_operations no_open_fops = {.open = no_open};
	struct address_space *const mapping = &inode->i_data;

	inode->i_sb = sb;
	inode->i_blkbits = sb->s_blocksize_bits;
	inode->i_flags = 0;
	atomic_set(&inode->i_count, 1);
	inode->i_op = &empty_iops;
	inode->i_fop = &no_open_fops;
	inode->__i_nlink = 1;
	inode->i_opflags = 0;
	i_uid_write(inode, 0);
	i_gid_write(inode, 0);
	atomic_set(&inode->i_writecount, 0);
	inode->i_size = 0;
	inode->i_blocks = 0;
	inode->i_bytes = 0;
	inode->i_generation = 0;
#ifdef CONFIG_QUOTA
	memset(&inode->i_dquot, 0, sizeof(inode->i_dquot));
#endif
	inode->i_pipe = NULL;
	inode->i_bdev = NULL;
	inode->i_cdev = NULL;
	inode->i_rdev = 0;
	inode->dirtied_when = 0;

//...

	this_cpu_inc(nr_inodes); ★
```

#### nr_inodes をデクリメントする

```c
void __destroy_inode(struct inode *inode)
{
	BUG_ON(inode_has_buffers(inode));
	security_inode_free(inode);
	fsnotify_inode_delete(inode);
	if (!inode->i_nlink) {
		WARN_ON(atomic_long_read(&inode->i_sb->s_remove_count) == 0);
		atomic_long_dec(&inode->i_sb->s_remove_count);
	}

#ifdef CONFIG_FS_POSIX_ACL
	if (inode->i_acl && inode->i_acl != ACL_NOT_CACHED)
		posix_acl_release(inode->i_acl);
	if (inode->i_default_acl && inode->i_default_acl != ACL_NOT_CACHED)
		posix_acl_release(inode->i_default_acl);
#endif
	this_cpu_dec(nr_inodes);
}
EXPORT_SYMBOL(__destroy_inode);
```