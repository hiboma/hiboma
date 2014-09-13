


probe ポイント多過ぎてカーネルごと死ぬ例

```c
probe kernel.function("*").call
{
 if (pid() == target())
     printf ("%s -> %s\n", thread_indent(1), probefunc())
}

probe kernel.function("*@fs/*.c").call
{
 if (pid() == target())
     printf ("%s <- %s\n", thread_indent(-1), probefunc())
}
```

次くらいに絞り込むと動いてくれる

```c
/* sudo foo.tap -c /bin/ls */

probe kernel.function("*@fs/*.c").call
{
 if (pid() == target())
     printf ("%s -> %s\n", thread_indent(1), probefunc())
}

probe kernel.function("*@fs/*.c").call
{
 if (pid() == target())
     printf ("%s <- %s\n", thread_indent(-1), probefunc())
}
```

出力例

```
     0 ls(2274): -> sys_getdents
     3 ls(2274):  -> fget
     4 ls(2274):  -> sys_getdents
     6 ls(2274):  -> vfs_readdir
     8 ls(2274):   -> touch_atime
     9 ls(2274):   -> vfs_readdir
    10 ls(2274):  -> sys_getdents
    12 ls(2274):  -> fput
    13 ls(2274):  -> sys_getdents
    14 ls(2274): -> tracesys
     0 ls(2274): -> path_put
     2 ls(2274):  -> dput
     3 ls(2274):  -> path_put
     4 ls(2274): -> __audit_syscall_exit
     0 ls(2274): -> sys_close
     1 ls(2274):  -> filp_close
     3 ls(2274):   -> dnotify_flush
     6 ls(2274):    -> fsnotify_find_mark_entry
     7 ls(2274):    -> dnotify_flush
     8 ls(2274):   -> filp_close
    10 ls(2274):   -> locks_remove_posix
    11 ls(2274):   -> filp_close
    13 ls(2274):   -> fput
    15 ls(2274):    -> __fput
    17 ls(2274):     -> inotify_inode_queue_event
    18 ls(2274):     -> __fput
    20 ls(2274):     -> __fsnotify_parent
    22 ls(2274):     -> __fput
    23 ls(2274):     -> inotify_dentry_parent_queue_event
    25 ls(2274):     -> __fput
    26 ls(2274):     -> fsnotify
    28 ls(2274):     -> __fput
    29 ls(2274):     -> locks_remove_flock
    31 ls(2274):     -> __fput
    33 ls(2274):     -> file_kill
    34 ls(2274):     -> __fput
    36 ls(2274):     -> dput
    37 ls(2274):     -> __fput
    39 ls(2274):     -> mntput_no_expire
    40 ls(2274):     -> __fput
    41 ls(2274):    -> fput
```

## 参考リンク
 
 * http://d.hatena.ne.jp/mmitou/20120721/1342879187
