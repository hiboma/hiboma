# 非特権ユーザが特権ユーザのファイルのst_ctimeをchownで更新できる.md

https://gist.github.com/hiboma/896bf9fe34144cb5bc94 にも書いた

## / ルートディレクトリで検証

まずは stat を取る

```
$ stat /
  File: `/'
  Size: 4096            Blocks: 8          IO Block: 4096   ディレクトリ
Device: fd00h/64768d    Inode: 2           Links: 23
Access: (0555/dr-xr-xr-x)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2014-08-20 19:03:32.018086791 +0900
Modify: 2014-08-20 13:25:38.214464218 +0900
Change: 2014-08-20 13:25:38.214464218 +0900 # これが 
```

非特権ユーザで chown(2) する。 uid, gid の指定は -1 にしておく

```
$ perl -e 'chown(-1, -1, "/") or die $!'
```

再度 stat をとると、Change (st_ctime) が更新されている

```
 stat /
  File: `/'
  Size: 4096            Blocks: 8          IO Block: 4096   ディレクトリ
Device: fd00h/64768d    Inode: 2           Links: 23
Access: (0555/dr-xr-xr-x)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2014-08-20 19:03:32.018086791 +0900
Modify: 2014-08-20 13:25:38.214464218 +0900
Change: 2014-08-20 22:28:30.859172981 +0900 # 更新される
```

## chown(2) の実装をおう

```c
int chown(const char *pathname, uid_t owner, gid_t group);
```

owner, group の値は指定すると、 chown_common で strct iattr のフラグを立てるのに使われている

 * ATTR_CTIME
   * st_ctime を更新するフラグ
 * ATTR_UID
   * uid を更新するフラグ
   * -1 の場合は無効
 * ATTR_GID
   * gid を更新するフラグ
   * -1 の場合は無効

```c
static int chown_common(struct dentry * dentry, uid_t user, gid_t group)
{
	struct inode *inode = dentry->d_inode;
	int error;
	struct iattr newattrs;

	newattrs.ia_valid =  ATTR_CTIME;

    /* -1 でなければ ATTR_UID を立てる */
	if (user != (uid_t) -1) {
		newattrs.ia_valid |= ATTR_UID;
		newattrs.ia_uid = user;
	}

    /* -1 でなければ ATTR_GID を立てる */    
	if (group != (gid_t) -1) {
		newattrs.ia_valid |= ATTR_GID;
		newattrs.ia_gid = group;
	}
	if (!S_ISDIR(inode->i_mode))
		newattrs.ia_valid |=
			ATTR_KILL_SUID | ATTR_KILL_SGID | ATTR_KILL_PRIV;
	mutex_lock(&inode->i_mutex);
	error = notify_change(dentry, &newattrs);
	mutex_unlock(&inode->i_mutex);

	return error;
}
```

struct iattr の中身は ↓ な感じ。

 * Inode Attributes
 * notify_change で使われる

inode で変更したい属性を iattr にセットして、 notifier_change にぶん投げて使うみたい

```c
/*
 * This is the Inode Attributes structure, used for notify_change().  It
 * uses the above definitions as flags, to know which values have changed.
 * Also, in this manner, a Filesystem can look at only the values it cares
 * about.  Basically, these are the attributes that the VFS layer can
 * request to change from the FS layer.
 *
 * Derek Atkins <warlord@MIT.EDU> 94-10-20
 */
struct iattr {
	unsigned int	ia_valid;
	umode_t		ia_mode;
	uid_t		ia_uid;
	gid_t		ia_gid;
	loff_t		ia_size;
	struct timespec	ia_atime;
	struct timespec	ia_mtime;
	struct timespec	ia_ctime;

	/*
	 * Not an attribute, but an auxilary info for filesystems wanting to
	 * implement an ftruncate() like method.  NOTE: filesystem should
	 * check for (ia_valid & ATTR_FILE), and not for (ia_file != NULL).
	 */
	struct file	*ia_file;
};
```

## ATTR_UID と ATTR_GID のバリデーション

inode_change_ok で ATTR_UID, ATTR_GID を変更出来るかどうかの権限確認が行われる

```c
/**
 * inode_change_ok - check if attribute changes to an inode are allowed
 * @inode:	inode to check
 * @attr:	attributes to change
 *
 * Check if we are allowed to change the attributes contained in @attr
 * in the given inode.  This includes the normal unix access permission
 * checks, as well as checks for rlimits and others.
 *
 * Should be called as the first thing in ->setattr implementations,
 * possibly after taking additional locks.
 */
int inode_change_ok(const struct inode *inode, struct iattr *attr)
{
	unsigned int ia_valid = attr->ia_valid;

//...    

	/* Make sure a caller can chown. */
	if ((ia_valid & ATTR_UID) &&
	    (current_fsuid() != inode->i_uid ||
	     attr->ia_uid != inode->i_uid) && !capable(CAP_CHOWN))
		return -EPERM;

	/* Make sure caller can chgrp. */
	if ((ia_valid & ATTR_GID) &&
	    (current_fsuid() != inode->i_uid ||
	    (!in_group_p(attr->ia_gid) && attr->ia_gid != inode->i_gid)) &&
	    !capable(CAP_CHOWN))
		return -EPERM;        
```

ATTR_UID, ATTR_GID が無い場合は ここをすり抜けちゃうね!
加えて ATTR_CTIME は inode_change_ok でバリデーションされていない