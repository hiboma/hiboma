# 電源断で /proc/meminfo の Dirty ページがディスクに同期されず揮発するかどうかの検証

#### Dirty の書き出しを抑えるめちゃくちゃ設定をする

````sh
sudo sysctl -w vm.dirty_writeback_centisecs=1000000 # 単位は ms
sudo sysctl -w    vm.dirty_expire_centisecs=1000000 # 単位は ms
sudo sysctl -w    vm.dirty_background_ratio=99
sudo sysctl -w               vm.dirty_ratio=99
```

#### 100MB のテストデータを write する

```
ruby -e 'File.open("/tmp/100mb.txt", "w") { |io| io.print("@" * 1024 * 1024 * 100) }'
```

シェルのリダイレクトでもいいけど、 sync(2) 等で同期をとってないことを確かにしておきたいので ruby のワンライナーにしてます。strace を取ると、 write(2) 後に close(2) しているだけなのが確認できます

```
open("/tmp/100mb.txt", O_WRONLY|O_CREAT|O_TRUNC, 0666) = 3
rt_sigprocmask(SIG_BLOCK, NULL, [], 8)  = 0
rt_sigprocmask(SIG_BLOCK, NULL, [], 8)  = 0
rt_sigprocmask(SIG_BLOCK, NULL, [], 8)  = 0
mmap(NULL, 1052672, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f5fcce25000
mmap(NULL, 104861696, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f5fc53de000
fstat(3, {st_mode=S_IFREG|0664, st_size=0, ...}) = 0
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f5fccf92000
write(3, "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"..., 104857600) = 104857600
rt_sigprocmask(SIG_BLOCK, NULL, [], 8)  = 0
close(3)                                = 0
```

#### write 後、Dirty のサイズを見る

```
$ grep Dirty /proc/meminfo
Dirty:            102448 kB
```

#### ファイルの stat もとっておく

```
$ stat /tmp/100mb.txt
  File: `/tmp/100mb.txt'
  Size: 104857600       Blocks: 204800     IO Block: 4096   regular file
Device: fd00h/64768d    Inode: 1572876     Links: 1
Access: (0664/-rw-rw-r--)  Uid: (  500/ vagrant)   Gid: (  500/ vagrant)
Access: 2016-02-03 09:22:03.439382901 +0000
Modify: 2016-02-03 09:22:03.466399833 +0000
Change: 2016-02-03 09:22:03.466399833 +0000
```

#### Dirty が溜まっている状態で電源断や突然のホストダウンした状態を模擬的に再現する

```
vagrant halt --force
```

プチっとな

#### vagrant up 後にファイルの中身を見る

```
$ cat /tmp/100mb.txt
$
```

```
$ stat /tmp/100mb.txt
  File: `/tmp/100mb.txt'
  Size: 0               Blocks: 0          IO Block: 4096   regular empty file
Device: fd00h/64768d    Inode: 1572876     Links: 1
Access: (0664/-rw-rw-r--)  Uid: (  500/ vagrant)   Gid: (  500/ vagrant)
Access: 2016-02-03 09:26:21.357851070 +0000
Modify: 2016-02-03 09:22:03.466399833 +0000
Change: 2016-02-03 09:22:03.466399833 +0000
```

----

 * VM での検証なので、何か見落としている点は?
 * RAID が入ると挙動変わるかな?
