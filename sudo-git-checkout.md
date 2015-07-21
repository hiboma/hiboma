## sudo git checkout 

#### ここに README.md がある git リポジトリがあるじゃろ

```sh
$ ls -hald . README.md 
drwxr-xr-x 3 vagrant vagrant 4.0K Jul 21 10:41 .
-rw-rw-r-- 1 vagrant vagrant 2.1K Jul 21 10:27 README.md
```

#### ここで README.md を書き換えるじゃろ

```sh
$ echo 'file changed' > README.md 
$ git status
# On branch master
# Changed but not updated:
#   (use "git add <file>..." to update what will be committed)
#   (use "git checkout -- <file>..." to discard changes in working directory)
#
#	modified:   README.md
#
no changes added to commit (use "git add" and/or "git commit -a")
```

#### ここで `sudo git checkout .` するじゃろ ( 何故 sudo しているのかは問わないで!!!1 )

```sh
$ sudo git checkout .
```

#### README.md のオーナーが root:root になる

```sh
$ ls -hald . README.md
drwxr-xr-x 3 vagrant vagrant 4.0K Jul 21 10:42 .
-rw-r--r-- 1 root    root    2.1K Jul 21 10:42 README.md
```

## オーナーが変わる理由

strace で探りましょう

```sh
$ sudo strace -v git checkout .

# 略 ...

lstat("README.md", {st_dev=makedev(8, 1), st_ino=68891, st_mode=S_IFREG|0664, st_nlink=1, st_uid=500, st_gid=500, st_blksize=4096, st_blocks=8, st_size=13, st_atime=2015/07/21-10:45:08, st_mtime=2015/07/21-10:45:10, st_ctime=2015/07/21-10:45:10}) = 0
unlink("README.md")                     = 0

# 略 ...

open("README.md", O_WRONLY|O_CREAT|O_EXCL, 0666) = 4
write(4, "# Inspect 'Cannot allocate memor"..., 2105) = 2105
fstat(4, {st_dev=makedev(8, 1), st_ino=68891, st_mode=S_IFREG|0644, st_nlink=1, st_uid=0, st_gid=0, st_blksize=4096, st_blocks=8, st_size=2105, st_atime=2015/07/21-10:45:18, st_mtime=2015/07/21-10:45:18, st_ctime=2015/07/21-10:45:18}) = 0
close(4)                                = 0
```

git checkout は

 * unlink(2)
 * open(2) - write(2) - close(2)

で差分を元に戻している。ということで sudo をつけると root:root になる理由がお分かりいただけたかな
