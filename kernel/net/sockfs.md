# sockfs

## sockfs ファイルシステムの登録

```c
satic struct file_system_type sock_fs_type = {
	.name =		"sockfs",
	.get_sb =	sockfs_get_sb,
	.kill_sb =	kill_anon_super,
};
```

## スーパーブロックの初期化

get_sb_pseudo で疑似スーパーブロックとして返す ( get_sb_nodev と何が違うんだっけ? )

```c
static int sockfs_get_sb(struct file_system_type *fs_type,
			 int flags, const char *dev_name, void *data,
			 struct vfsmount *mnt)
{
	return get_sb_pseudo(fs_type, "socket:", &sockfs_ops, SOCKFS_MAGIC,
			     mnt);
}
```

## struct socket <=> struct file の変換

sock_from_file で成される

 * file->private_data に struct socket を保持している
 * `file->f_op == &socket_file_ops` でソケットかどうか判定するというなかなか荒技

```c
static struct socket *sock_from_file(struct file *file, int *err)
{
	if (file->f_op == &socket_file_ops)
		return file->private_data;	/* set in sock_map_fd */

	*err = -ENOTSOCK;
	return NULL;
}
```