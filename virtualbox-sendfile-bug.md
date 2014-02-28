Vagarnt というか VirtualBoxでゲストOSLinuxの場合に、Apache や Nginx が /vagrantディレクトリ(sharedfolder) 上の静的ファイルを sendfile(2) を使ってサーブすると、ファイルの内容が更新されたにも関わらず古い内容を返す不具合が知られています

Apache では EnableSendfile off, Nginx では sendfile off にすることで回避出来る問題ですが、根本的な原因は何なのかソースを追って調べました。(というかある程度調べたメモを塩漬けにしていたので、整理して書きます)


##  調べたソースや環境

- VirtualBox-4.3.6
- ゲストOSは CentOS release 6.5 (Final)、カーネルは 2.6.32-431.1.2.0.1.el6.x86_64

VirtualBoxのソースは下記URLからダウンロードすることが出来ます


##  先に結論

続きが長いので先にまとめておきます

 * ゲストOS が Linux で使える sharedfolders (ex. /vagrant ) は **vboxsf** というファイルシステムである
 * vboxsf は sendfile(2) で **generic_file_splice_read** を呼ぶ
 * generic_file_splice_read は 読み出し側ファイルデスクリプタのデータをページキャッシュを経由してから書き出しディスクリプタ側に渡す
 * sendfile(2) は ページキャッシュの revalidate をしない
 * NFS や smbfs では generic_file_splice_read を呼ぶ前に ページキャッシュの revalidate をしている

これによって

 * sendfile(2) でデータを読み出した後に、ホストOSでデータを更新しても、その後の sendfile(2) でも古いページキャッシュを参照し続ける
 * Apache や Nginx が返す静的ファイルが意図したように更新されない

という不具合になるようです

カーネル開発者でない私が言うのもなんですが、vboxsf の実装は簡素な感じです。(ゲストOSとホストOSがやり取りする部分になると非常に複雑で分からんのですが、LinuxのVFSのレイヤだけなら割と読める感じ)


##  /vagrant のファイルシステムは何か?

ゲストOSがLinuxの場合にデフォルトで /vagrant としてマウントするファイルシステムは vboxsf (**fs**) ではないので注意) です

```
mount | grep /vagrant
/vagrant on /vagrant type vboxsf (uid=501,gid=501,rw)
```

vboxsfのソースは下記ディレクトリ以下に置いてあります

```
src/VBox/Additions/linux/sharedfolder

$ ls -1
Makefile.kmk
Makefile.module
dirops.c
files_vboxsf
lnkops.c
mount.vboxsf.c
regops.c
utils.c
vbsfmount.c
vbsfmount.h
vfsmod.c
vfsmod.h
```

vboxfs はゲストOSのLinuxカーネルモジュールとして実装されています

```
[vagrant@localhost ~]$ lsmod | grep vboxsf
vboxsf                 37678  3 
```

ということで vboxsf の実装を追って行きます


##  vboxsf の file_operations

vboxsf でのファイル操作は sf_reg_fops で定義されています

```c
struct file_operations sf_reg_fops =
{
    .read        = sf_reg_read,
    .open        = sf_reg_open,
    .write       = sf_reg_write,
    .release     = sf_reg_release,
    .mmap        = sf_reg_mmap,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 0)
# if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 23)
    .splice_read = generic_file_splice_read,
# else
    .sendfile    = generic_file_sendfile,
# endif
    .aio_read    = generic_file_aio_read,
    .aio_write   = generic_file_aio_write,
# if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 35)
    .fsync       = noop_fsync,
# else
    .fsync       = simple_sync_file,
# endif
    .llseek      = generic_file_llseek,
#endif
};
```

.sendfile を読んだらいいのかと思ってたのですが、2.6.23 以降は .splice_read なのですね。nnということで generic_file_splice_read を呼び出すようです。

Linuxカーネルでは generic_file_ の prefix を持つメソッドはファイルシステムに固有でなく、汎用的に使われる *** としてようです。vboxsf の実装ではありません。


##  vboxsf の write(2)

vboxsf では write(2) を sf_reg_write で実装しています

```c
/**
 * Write to a regular file.
 *
 * @param file          the file
 * @param buf           the buffer
 * @param size          length of the buffer
 * @param off           offset within the file
 * @returns the number of written bytes on success, Linux error code otherwise
 */
static ssize_t sf_reg_write(struct file *file, const char *buf, size_t size, loff_t *off)
{
    int err;
    void *tmp;
    RTCCPHYS tmp_phys;
    size_t tmp_size;
    size_t left = size;
    ssize_t total_bytes_written = 0;
    struct inode *inode = file->f_dentry->d_inode;
    struct sf_inode_info *sf_i = GET_INODE_INFO(inode);
    struct sf_glob_info *sf_g = GET_GLOB_INFO(inode->i_sb);
    struct sf_reg_info *sf_r = file->private_data;
    loff_t pos;

    TRACE();
    BUG_ON(!sf_i);
    BUG_ON(!sf_g);
    BUG_ON(!sf_r);

    if (!S_ISREG(inode->i_mode))
    {
        LogFunc(("write to non regular file %d\n",  inode->i_mode));
        return -EINVAL;
    }

    pos = *off;
    if (file->f_flags & O_APPEND)
    {
        pos = inode->i_size;
        *off = pos;
    }

    /** XXX Check write permission according to inode->i_mode! */

    if (!size)
        return 0;

    tmp = alloc_bounce_buffer(&tmp_size, &tmp_phys, size, __PRETTY_FUNCTION__);
    if (!tmp)
        return -ENOMEM;

    while (left)
    {
        uint32_t to_write, nwritten;

        to_write = tmp_size;
        if (to_write > left)
            to_write = (uint32_t) left;

        nwritten = to_write;

        if (copy_from_user(tmp, buf, to_write))
        {
            err = -EFAULT;
            goto fail;
        }

#if 1
        if (VbglR0CanUsePhysPageList())
        {
            err = VbglR0SfWritePhysCont(&client_handle, &sf_g->map, sf_r->handle,
                                        pos, &nwritten, tmp_phys);
            err = RT_FAILURE(err) ? -EPROTO : 0;
        }
        else
#endif
            err = sf_reg_write_aux(__func__, sf_g, sf_r, tmp, &nwritten, pos);
        if (err)
            goto fail;

        pos  += nwritten;
        left -= nwritten;
        buf  += nwritten;
        total_bytes_written += nwritten;
        if (nwritten != to_write)
            break;
    }

    *off += total_bytes_written;
    if (*off > inode->i_size)
        inode->i_size = *off;

    sf_i->force_restat = 1;
    free_bounce_buffer(tmp);
    return total_bytes_written;

fail:
    free_bounce_buffer(tmp);
    return err;
}
```

ちょっと長いですが、char *buf のデータを VbglR0SfWritePhysCont に渡しているのが肝です。VbglR0SfWritePhysCont はゲストOSからホストOSに *** を発行するのようです。

sf_reg_write ではページキャッシュを経由しないでデータを書き込んでいます


##  NFS の file_operations

nfs の file_operation は下記の通り

```
const struct file_operations nfs_file_operations = {
	.llseek		= nfs_file_llseek,
	.read		= do_sync_read,
	.write		= do_sync_write,
	.aio_read	= nfs_file_read,
	.aio_write	= nfs_file_write,
	.mmap		= nfs_file_mmap,
	.open		= nfs_file_open,
	.flush		= nfs_file_flush,
	.release	= nfs_file_release,
	.fsync		= nfs_file_fsync,
	.lock		= nfs_lock,
	.flock		= nfs_flock,
	.splice_read	= nfs_file_splice_read,
	.splice_write	= nfs_file_splice_write,
	.check_flags	= nfs_check_flags,
	.setlease	= nfs_setlease,
};
```

nfs_file_splice_read  は generic_file_splice_read を呼んでいますが、その前に nfs_revalidate_mapping を呼び出しています

```c
static ssize_t
nfs_file_splice_read(struct file *filp, loff_t *ppos,
		     struct pipe_inode_info *pipe, size_t count,
		     unsigned int flags)
{
	struct dentry *dentry = filp->f_path.dentry;
	struct inode *inode = dentry->d_inode;
	ssize_t res;

	dprintk("NFS: splice_read(%s/%s, %lu@%Lu)\n",
		dentry->d_parent->d_name.name, dentry->d_name.name,
		(unsigned long) count, (unsigned long long) *ppos);

	res = nfs_revalidate_mapping(inode, filp->f_mapping);
	if (!res)
		res = generic_file_splice_read(filp, ppos, pipe, count, flags);
	return res;
}
```

nfs_revalidate_mapping は ページキャッシュを revalidate (ページキャッシュの内容が古ければ更新する) しています

```c
/**
 * nfs_revalidate_mapping - Revalidate the pagecache
 * @inode - pointer to host inode
 * @mapping - pointer to mapping
 *
 * This version of the function will take the inode->i_mutex and attempt to
 * flush out all dirty data if it needs to invalidate the page cache.
 */
int nfs_revalidate_mapping(struct inode *inode, struct address_space *mapping)
{
	struct nfs_inode *nfsi = NFS_I(inode);
	int ret = 0;

	if ((nfsi->cache_validity & NFS_INO_REVAL_PAGECACHE)
			|| nfs_attribute_timeout(inode) || NFS_STALE(inode)) {
		ret = __nfs_revalidate_inode(NFS_SERVER(inode), inode);
		if (ret < 0)
			goto out;
	}
	if (nfsi->cache_validity & NFS_INO_INVALID_DATA)
		ret = nfs_invalidate_mapping(inode, mapping);
out:
	return ret;
}
```


## smbfs の file_operations 

smbfs (samba) では .smb_file_splice_read  を呼んでいます

```c
const struct file_operations smb_file_operations =
{
	.llseek 	= smb_remote_llseek,
	.read		= do_sync_read,
	.aio_read	= smb_file_aio_read,
	.write		= do_sync_write,
	.aio_write	= smb_file_aio_write,
	.ioctl		= smb_ioctl,
	.mmap		= smb_file_mmap,
	.open		= smb_file_open,
	.release	= smb_file_release,
	.fsync		= smb_fsync,
	.splice_read	= smb_file_splice_read,
};
```

smb_file_splice_read の実装は以下の通りです

```c
static ssize_t
smb_file_splice_read(struct file *file, loff_t *ppos,
		     struct pipe_inode_info *pipe, size_t count,
		     unsigned int flags)
{
	struct dentry *dentry = file->f_path.dentry;
	ssize_t status;

	VERBOSE("file %s/%s, pos=%Ld, count=%lu\n",
		DENTRY_PATH(dentry), *ppos, count);

	status = smb_revalidate_inode(dentry);
	if (status) {
		PARANOIA("%s/%s validation failed, error=%Zd\n",
			 DENTRY_PATH(dentry), status);
		goto out;
	}
	status = generic_file_splice_read(file, ppos, pipe, count, flags);
out:
	return status;
}
```

nfs の時と同様に、generic_file_splice_read を呼び出す前に smb_revalidate_inode を呼び出しています

smb_revalidate_inode の実装は以下の通りです

```c
/*
 * This is called when we want to check whether the inode
 * has changed on the server.  If it has changed, we must
 * invalidate our local caches.
 */
int
smb_revalidate_inode(struct dentry *dentry)
{
	struct smb_sb_info *s = server_from_dentry(dentry);
	struct inode *inode = dentry->d_inode;
	int error = 0;

	DEBUG1("smb_revalidate_inode\n");
	lock_kernel();

	/*
	 * Check whether we've recently refreshed the inode.
	 */
	if (time_before(jiffies, SMB_I(inode)->oldmtime + SMB_MAX_AGE(s))) {
		VERBOSE("up-to-date, ino=%ld, jiffies=%lu, oldtime=%lu\n",
			inode->i_ino, jiffies, SMB_I(inode)->oldmtime);
		goto out;
	}

	error = smb_refresh_inode(dentry);
out:
	unlock_kernel();
	return error;
}
```

コメントの説明が簡潔に表していますね

“This is called when we want to check whether the inode has changed on the server.  If it has changed, we must invalidate our local caches.”

ということで NFSやSambaのようなネットワークファイルシステムでは generic_file_splice_read を呼び出す前に inode の変更を確認して適宜 ページキャッシュを破棄する必要があるのだと分かります。