# mount --rbind

--rbind ってどやって実装されてるの?

## /bin/mount ソース

mount は util-linux-ng-2.17.2 に入ってる

```
mount/mount.c:  { "rbind",	0, 0, MS_BIND|MS_REC }, /* Idem, plus mounted subtrees */
```

**MS_BIND|MS_REC** が正解らしい MS_REC は ___recursive___

## カーネル

 * http://wiki.bit-hive.com/north/pg/mount%A5%AA%A5%D7%A5%B7%A5%E7%A5%F3 も参考に

### do_mount

MS_BIND は loopback 扱いなのだな

```c
long do_mount(char *dev_name, const char *dir_name, char *type_page,
		  unsigned long flags, void *data_page)
{
	struct path path;
	int retval = 0;
	int mnt_flags = 0;
 
//

 	else if (flags & MS_BIND)
		retval = do_loopback(&path, dev_name, flags & MS_REC);
```        
