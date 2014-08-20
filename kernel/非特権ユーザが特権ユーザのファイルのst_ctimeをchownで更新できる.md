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

```c
static int chown_common(struct dentry * dentry, uid_t user, gid_t group)
{
	struct inode *inode = dentry->d_inode;
	int error;
	struct iattr newattrs;

	newattrs.ia_valid =  ATTR_CTIME;
	if (user != (uid_t) -1) {
		newattrs.ia_valid |= ATTR_UID;
		newattrs.ia_uid = user;
	}
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