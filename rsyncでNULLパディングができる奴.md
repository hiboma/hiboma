# rsync でファイルの先頭に NULL の padding ができる

 * --partial
 * --append
 * --link-dest

を併用すると、コピーしたファイルの先頭に NULL(\0) のパディングが入り意図しない**破損**になる 。もじゃもじゃの人が見つけた。

( rsync の仕様として正しい気もするので、挙動を正確に把握できていれば「破損」と書くのは適切さを欠いているかもしれません )

## 再現手順

```sh
# もじゃもじゃさんが再現した手順です
rm -rfv /tmp/{src,backup1,backup2}
mkdir /tmp/{src,backup1,backup2}

# 10bytes のファイル作成
echo -n 1234567890 > /tmp/src/aaa.txt

# バックアップ
rsync -av --partial --append /tmp/src/ /tmp/backup1/

# 10bytes 足す
echo -n abcdefghij >> /tmp/src/aaa.txt

# 再度ばっくうp
rsync -a --partial --append --link-dest /tmp/backup1/ /tmp/src/ /tmp/backup2/

cat -A /tmp/backup2/aaa.txt
```

`1234567890abcdefghij` なファイルができるかと思いきや、先頭 10バイトが `^@ (NULL)` になっている

```
$ cat -A /tmp/backup2/aaa.txt
^@^@^@^@^@^@^@^@^@^@abcdefghij

$ cat -A /tmp/src/aaa.txt
1234567890abcdefghij

cat -A /tmp/backup1/aaa.txt
1234567890
```

## rsync のデバッグログ

```
$ rsync -avvvvv --partial --append --link-dest /tmp/backup1/ /tmp/src/ /tmp/backup2/
FILE_STRUCT_LEN=24, EXTRA_LEN=4
cmd=<NULL> machine=<NULL> user=<NULL> path=/tmp/backup2/
cmd[0]=. cmd[1]=/tmp/backup2/ 
note: iconv_open("UTF-8", "UTF-8") succeeded.
(Client) Protocol versions: remote=30, negotiated=30
(Server) Protocol versions: remote=30, negotiated=30
sending incremental file list
[sender] change_dir(/tmp/src)
[sender] make_file(.,*,0)
[sender] make_file(aaa.txt,*,2)
[sender] flist start=1, used=2, low=0, high=1
[sender] i=1 /tmp/src ./ mode=040775 len=4096 uid=501 gid=501 flags=5
[sender] i=2 /tmp/src aaa.txt mode=0100664 len=20 uid=501 gid=501 flags=0
send_file_list done
file list sent
send_files starting
server_recv(2) starting pid=3686
received 2 names
[receiver] flist start=1, used=2, low=0, high=1
[receiver] i=1 0 ./ mode=040775 len=4096 gid=501 flags=5
[receiver] i=2 1 aaa.txt mode=0100664 len=20 gid=501 flags=0
recv_file_list done
get_local_name count=2 /tmp/backup2/
[receiver] change_dir(/tmp/backup2)
generator starting pid=3686
delta-transmission enabled
recv_generator(.,0)
send_files(0, /tmp/src/.)
recv_generator(.,1)
recv_generator(aaa.txt,2)
gen mapped /tmp/backup1/aaa.txt of size 10
generating and sending sums for 2
send_files(2, /tmp/src/aaa.txt)
count=1 rem=10 blength=700 s2length=2 flength=10
count=1 n=700 rem=10
send_files mapped /tmp/src/aaa.txt of size 20
calling match_sums /tmp/src/aaa.txt
aaa.txt
sending file_sum
false_alarms=0 hash_hits=0 matches=0
sender finished /tmp/src/aaa.txt
recv_files(2) starting
generate_files phase=1
recv_files(.)
recv_files(aaa.txt)
recv mapped /tmp/backup1/aaa.txt of size 10
data recv 10 at 10
got file_sum
finishing aaa.txt
send_files phase=1
touch_up_dirs: . (0)
recv_files phase=1
generate_files phase=2
send_files phase=2
send files finished
total: matches=0  hash_hits=0  false_alarms=0 data=10
recv_files phase=2
generate_files phase=3
recv_files finished
generate_files finished
client_run waiting on 3686

sent 118 bytes  received 35 bytes  306.00 bytes/sec
total size is 20  speedup is 0.13
_exit_cleanup(code=0, file=main.c, line=1039): entered
_exit_cleanup(code=0, file=main.c, line=1039): about to call exit(0)
```

## 理由

デバッグログを読んだ感じでは以下の理屈なようです

```
  1234567890abcdefghij  # src/
- 1234567890            # backup1/ < --link-dest のファイルと比較して --partial で差分 (abcdefghij) を取り出す
----------------------- #
  @@@@@@@@@@abcdefghij  # backup2/ < --append  で offset=10 以降に追加
```

## strace

strace を取ってみると、 lseek することで NULL のパディングが出来ている様子

```
[pid  3732] open("aaa.txt", O_RDONLY)   = 3
[pid  3732] fstat(3, {st_mode=S_IFREG|0664, st_size=20, ...}) = 0
[pid  3732] lseek(3, 10, SEEK_SET)      = 10
[pid  3732] read(3, "abcdefghij", 10)   = 10
[pid  3732] close(3)                    = 0
[pid  3732] write(4, "6\0\0\7\3\4\210\0\1\0\0\0\274\2\0\0\2\0\0\0\n\0\0\0\n\0\0\0abcdefghij\0\0\0\0\251%WiB\351K.\365z\6a\1\264\210v", 58 <unfinished ...>
[pid  3734] read(0, "\3\4\210\0\1\0\0\0\274\2\0\0\2\0\0\0\n\0\0\0\n\0\0\0abcdefghij\0\0\0\0\251%WiB\351K.\365z\6a\1\264\210v", 54) = 54
[pid  3734] open("/tmp/backup1/aaa.txt", O_RDONLY) = 1
[pid  3734] open("aaa.txt", O_WRONLY|O_CREAT, 0600) = 3 # /tmp/backup2/aaa.txt を open
[pid  3734] lseek(3, 10, SEEK_SET)      = 10            # <= これで NULL になる
[pid  3734] write(3, "abcdefghij", 10)  = 10            # <= lskeek してから abcdefghij 書き込み
[pid  3734] ftruncate(3, 20)            = 0
[pid  3734] close(1)                    = 0
[pid  3734] close(3)                    = 0
```

#### strace の全部ログ

```
$ strace -s120 -f rsync -a --partial --append --link-dest /tmp/backup1/ /tmp/src/ /tmp/backup2/
execve("/usr/bin/rsync", ["rsync", "-a", "--partial", "--append", "--link-dest", "/tmp/backup1/", "/tmp/src/", "/tmp/backup2/"], [/* 21 vars */]) = 0
brk(0)                                  = 0x1f49000
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f633896c000
access("/etc/ld.so.preload", R_OK)      = -1 ENOENT (No such file or directory)
open("/etc/ld.so.cache", O_RDONLY)      = 3
fstat(3, {st_mode=S_IFREG|0644, st_size=16422, ...}) = 0
mmap(NULL, 16422, PROT_READ, MAP_PRIVATE, 3, 0) = 0x7f6338967000
close(3)                                = 0
open("/lib64/libacl.so.1", O_RDONLY)    = 3
read(3, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0\200\36\0\0\0\0\0\0@\0\0\0\0\0\0\0000s\0\0\0\0\0\0\0\0\0\0@\0008\0\7\0@\0\34\0\33\0\1\0\0\0\5\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0,m\0\0\0\0\0\0,m\0\0\0\0\0\0\0\0 \0\0\0\0\0"..., 832) = 832
fstat(3, {st_mode=S_IFREG|0755, st_size=31280, ...}) = 0
mmap(NULL, 2126416, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x7f6338546000
mprotect(0x7f633854d000, 2093056, PROT_NONE) = 0
mmap(0x7f633874c000, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0x6000) = 0x7f633874c000
close(3)                                = 0
open("/lib64/libpopt.so.0", O_RDONLY)   = 3
read(3, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0\20\33\0\0\0\0\0\0@\0\0\0\0\0\0\0\10\207\0\0\0\0\0\0\0\0\0\0@\0008\0\6\0@\0\34\0\33\0\1\0\0\0\5\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\364~\0\0\0\0\0\0\364~\0\0\0\0\0\0\0\0 \0\0\0\0\0"..., 832) = 832
fstat(3, {st_mode=S_IFREG|0755, st_size=36360, ...}) = 0
mmap(NULL, 2131536, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x7f633833d000
mprotect(0x7f6338345000, 2097152, PROT_NONE) = 0
mmap(0x7f6338545000, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0x8000) = 0x7f6338545000
close(3)                                = 0
open("/lib64/libc.so.6", O_RDONLY)      = 3
read(3, "\177ELF\2\1\1\3\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0000\356\1\0\0\0\0\0@\0\0\0\0\0\0\0@>\35\0\0\0\0\0\0\0\0\0@\0008\0\n\0@\0J\0I\0\6\0\0\0\5\0\0\0@\0\0\0\0\0\0\0@\0\0\0\0\0\0\0@\0\0\0\0\0\0\0000\2\0\0\0\0\0\0000\2\0\0\0\0\0\0\10\0\0\0\0\0\0\0"..., 832) = 832
fstat(3, {st_mode=S_IFREG|0755, st_size=1921216, ...}) = 0
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6338966000
mmap(NULL, 3750152, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x7f6337fa9000
mprotect(0x7f6338134000, 2093056, PROT_NONE) = 0
mmap(0x7f6338333000, 20480, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0x18a000) = 0x7f6338333000
mmap(0x7f6338338000, 18696, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_ANONYMOUS, -1, 0) = 0x7f6338338000
close(3)                                = 0
open("/lib64/libattr.so.1", O_RDONLY)   = 3
read(3, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0\200\23\0\0\0\0\0\0@\0\0\0\0\0\0\0XB\0\0\0\0\0\0\0\0\0\0@\0008\0\7\0@\0\33\0\32\0\1\0\0\0\5\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\304:\0\0\0\0\0\0\304:\0\0\0\0\0\0\0\0 \0\0\0\0\0"..., 832) = 832
fstat(3, {st_mode=S_IFREG|0755, st_size=18712, ...}) = 0
mmap(NULL, 2113888, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x7f6337da4000
mprotect(0x7f6337da8000, 2093056, PROT_NONE) = 0
mmap(0x7f6337fa7000, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0x3000) = 0x7f6337fa7000
close(3)                                = 0
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6338965000
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6338964000
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6338963000
arch_prctl(ARCH_SET_FS, 0x7f6338964700) = 0
mprotect(0x7f6337fa7000, 4096, PROT_READ) = 0
mprotect(0x7f6338333000, 16384, PROT_READ) = 0
mprotect(0x7f633874c000, 4096, PROT_READ) = 0
mprotect(0x7f633896d000, 4096, PROT_READ) = 0
munmap(0x7f6338967000, 16422)           = 0
rt_sigaction(SIGUSR1, {0x41ad10, [], SA_RESTORER|SA_NOCLDSTOP, 0x7f6337fdb9a0}, NULL, 8) = 0
rt_sigaction(SIGUSR2, {0x41b600, [], SA_RESTORER|SA_NOCLDSTOP, 0x7f6337fdb9a0}, NULL, 8) = 0
rt_sigaction(SIGCHLD, {0x41b650, [], SA_RESTORER|SA_NOCLDSTOP, 0x7f6337fdb9a0}, NULL, 8) = 0
gettimeofday({1407424184, 133109}, NULL) = 0
geteuid()                               = 501
umask(0)                                = 02
brk(0)                                  = 0x1f49000
brk(0x1f6a000)                          = 0x1f6a000
open("/usr/lib/locale/locale-archive", O_RDONLY) = 3
fstat(3, {st_mode=S_IFREG|0644, st_size=99158576, ...}) = 0
mmap(NULL, 99158576, PROT_READ, MAP_PRIVATE, 3, 0) = 0x7f6331f13000
close(3)                                = 0
open("/etc/popt", O_RDONLY)             = -1 ENOENT (No such file or directory)
stat("/etc/popt.d", {st_mode=S_IFDIR|0755, st_size=4096, ...}) = 0
open("/etc/popt.d", O_RDONLY|O_NONBLOCK|O_DIRECTORY|O_CLOEXEC) = 3
fcntl(3, F_GETFD)                       = 0x1 (flags FD_CLOEXEC)
getdents(3, /* 2 entries */, 32768)     = 48
open("/usr/lib64/gconv/gconv-modules.cache", O_RDONLY) = 4
fstat(4, {st_mode=S_IFREG|0644, st_size=26060, ...}) = 0
mmap(NULL, 26060, PROT_READ, MAP_SHARED, 4, 0) = 0x7f633895c000
close(4)                                = 0
getdents(3, /* 0 entries */, 32768)     = 0
close(3)                                = 0
open("/home/vagrant/.popt", O_RDONLY)   = -1 ENOENT (No such file or directory)
rt_sigaction(SIGINT, {0x40af50, [], SA_RESTORER|SA_NOCLDSTOP, 0x7f6337fdb9a0}, NULL, 8) = 0
rt_sigaction(SIGHUP, {0x40af50, [], SA_RESTORER|SA_NOCLDSTOP, 0x7f6337fdb9a0}, NULL, 8) = 0
rt_sigaction(SIGTERM, {0x40af50, [], SA_RESTORER|SA_NOCLDSTOP, 0x7f6337fdb9a0}, NULL, 8) = 0
rt_sigprocmask(SIG_UNBLOCK, [HUP INT USR1 USR2 TERM CHLD], NULL, 8) = 0
rt_sigaction(SIGPIPE, {SIG_IGN, [], SA_RESTORER|SA_NOCLDSTOP, 0x7f6337fdb9a0}, NULL, 8) = 0
rt_sigaction(SIGXFSZ, {SIG_IGN, [], SA_RESTORER|SA_NOCLDSTOP, 0x7f6337fdb9a0}, NULL, 8) = 0
getcwd("/home/vagrant", 4095)           = 14
socketpair(PF_FILE, SOCK_STREAM, 0, [3, 4]) = 0
fcntl(3, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(3, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
fcntl(4, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(4, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
socketpair(PF_FILE, SOCK_STREAM, 0, [5, 6]) = 0
fcntl(5, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(5, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
fcntl(6, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(6, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
clone(Process 3733 attached
child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f63389649d0) = 3733
[pid  3732] close(6)                    = 0
[pid  3732] close(3)                    = 0
[pid  3732] fcntl(5, F_GETFL)           = 0x802 (flags O_RDWR|O_NONBLOCK)
[pid  3732] fcntl(4, F_GETFL)           = 0x802 (flags O_RDWR|O_NONBLOCK)
[pid  3732] select(5, NULL, [4], [4], {60, 0}) = 1 (out [4], left {59, 999991})
[pid  3732] write(4, "\36\0\0\0", 4)    = 4
[pid  3732] select(6, [5], [], NULL, {60, 0} <unfinished ...>
[pid  3733] dup2(3, 0)                  = 0
[pid  3733] close(4)                    = 0
[pid  3733] close(5)                    = 0
[pid  3733] dup2(6, 1)                  = 1
[pid  3733] close(3)                    = 0
[pid  3733] close(6)                    = 0
[pid  3733] fcntl(0, F_GETFL)           = 0x802 (flags O_RDWR|O_NONBLOCK)
[pid  3733] fcntl(1, F_GETFL)           = 0x802 (flags O_RDWR|O_NONBLOCK)
[pid  3733] select(2, NULL, [1], [1], {60, 0}) = 1 (out [1], left {59, 999993})
[pid  3733] write(1, "\36\0\0\0", 4 <unfinished ...>
[pid  3732] <... select resumed> )      = 1 (in [5], left {59, 999436})
[pid  3732] read(5, "\36\0\0\0", 4)     = 4
[pid  3732] select(6, [5], [], NULL, {60, 0} <unfinished ...>
[pid  3733] <... write resumed> )       = 4
[pid  3733] select(1, [0], [], NULL, {60, 0}) = 1 (in [0], left {59, 999993})
[pid  3733] read(0, "\36\0\0\0", 4)     = 4
[pid  3733] select(2, NULL, [1], [1], {60, 0}) = 1 (out [1], left {59, 999994})
[pid  3733] write(1, "\7", 1 <unfinished ...>
[pid  3732] <... select resumed> )      = 1 (in [5], left {59, 999734})
[pid  3732] read(5, "\7", 1)            = 1
[pid  3732] select(6, [5], [], NULL, {60, 0} <unfinished ...>
[pid  3733] <... write resumed> )       = 1
[pid  3733] gettimeofday({1407424184, 140164}, NULL) = 0
[pid  3733] select(2, NULL, [1], [1], {60, 0}) = 1 (out [1], left {59, 999994})
[pid  3733] write(1, "\270\226\343S", 4 <unfinished ...>
[pid  3732] <... select resumed> )      = 1 (in [5], left {59, 999821})
[pid  3732] read(5, "\270\226\343S", 4) = 4
[pid  3732] fcntl(2, F_GETFL)           = 0x8002 (flags O_RDWR|O_LARGEFILE)
[pid  3732] gettimeofday({1407424184, 140469}, NULL) = 0
[pid  3732] chdir("/tmp/src")           = 0
[pid  3732] lstat(".", {st_mode=S_IFDIR|0775, st_size=4096, ...}) = 0
[pid  3732] mmap(NULL, 135168, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f633893b000
[pid  3732] socket(PF_FILE, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
[pid  3732] connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
[pid  3732] close(3)                    = 0
[pid  3732] socket(PF_FILE, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
[pid  3732] connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
[pid  3732] close(3)                    = 0
[pid  3732] open("/etc/nsswitch.conf", O_RDONLY) = 3
[pid  3732] fstat(3, {st_mode=S_IFREG|0644, st_size=1688, ...}) = 0
[pid  3732] mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f633896b000
[pid  3732] read(3, "#\n# /etc/nsswitch.conf\n#\n# An example Name Service Switch config file. This file should be\n# sorted with the most-used s"..., 4096) = 1688
[pid  3732] read(3, "", 4096)           = 0
[pid  3732] close(3)                    = 0
[pid  3732] munmap(0x7f633896b000, 4096) = 0
[pid  3732] open("/etc/ld.so.cache", O_RDONLY) = 3
[pid  3732] fstat(3, {st_mode=S_IFREG|0644, st_size=16422, ...}) = 0
[pid  3732] mmap(NULL, 16422, PROT_READ, MAP_PRIVATE, 3, 0) = 0x7f6338967000
[pid  3732] close(3)                    = 0
[pid  3732] open("/lib64/libnss_files.so.2", O_RDONLY) = 3
[pid  3732] read(3, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0\360!\0\0\0\0\0\0@\0\0\0\0\0\0\0H\371\0\0\0\0\0\0\0\0\0\0@\0008\0\t\0@\0!\0 \0\6\0\0\0\5\0\0\0@\0\0\0\0\0\0\0@\0\0\0\0\0\0\0@\0\0\0\0\0\0\0\370\1\0\0\0\0\0\0\370\1\0\0\0\0\0\0\10\0\0\0\0\0\0\0"..., 832) = 832
[pid  3732] fstat(3, {st_mode=S_IFREG|0755, st_size=65928, ...}) = 0
[pid  3732] mmap(NULL, 2151824, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x7f6331d05000
[pid  3732] mprotect(0x7f6331d11000, 2097152, PROT_NONE) = 0
[pid  3732] mmap(0x7f6331f11000, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0xc000) = 0x7f6331f11000
[pid  3732] close(3)                    = 0
[pid  3732] mprotect(0x7f6331f11000, 4096, PROT_READ) = 0
[pid  3732] munmap(0x7f6338967000, 16422) = 0
[pid  3732] open("/etc/passwd", O_RDONLY|O_CLOEXEC) = 3
[pid  3732] fcntl(3, F_GETFD)           = 0x1 (flags FD_CLOEXEC)
[pid  3732] fstat(3, {st_mode=S_IFREG|0644, st_size=1032, ...}) = 0
[pid  3732] mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f633896b000
[pid  3732] read(3, "root:x:0:0:root:/root:/bin/bash\nbin:x:1:1:bin:/bin:/sbin/nologin\ndaemon:x:2:2:daemon:/sbin:/sbin/nologin\nadm:x:3:4:adm:/"..., 4096) = 1032
[pid  3732] close(3)                    = 0
[pid  3732] munmap(0x7f633896b000, 4096) = 0
[pid  3732] socket(PF_FILE, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
[pid  3732] connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
[pid  3732] close(3)                    = 0
[pid  3732] socket(PF_FILE, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
[pid  3732] connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
[pid  3732] close(3)                    = 0
[pid  3732] open("/etc/group", O_RDONLY|O_CLOEXEC) = 3
[pid  3732] fstat(3, {st_mode=S_IFREG|0644, st_size=513, ...}) = 0
[pid  3732] mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f633896b000
[pid  3732] read(3, "root:x:0:\nbin:x:1:bin,daemon\ndaemon:x:2:bin,daemon\nsys:x:3:bin,adm\nadm:x:4:adm,daemon\ntty:x:5:\ndisk:x:6:\nlp:x:7:daemon\nm"..., 4096) = 513
[pid  3733] <... write resumed> )       = 4
[pid  3732] close(3)                    = 0
[pid  3733] select(1, [0], [], NULL, {60, 0} <unfinished ...>
[pid  3732] munmap(0x7f633896b000, 4096) = 0
[pid  3732] mmap(NULL, 266240, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f63388fa000
[pid  3732] open(".", O_RDONLY|O_NONBLOCK|O_DIRECTORY|O_CLOEXEC) = 3
[pid  3732] getdents(3, /* 3 entries */, 32768) = 80
[pid  3732] lstat("aaa.txt", {st_mode=S_IFREG|0664, st_size=20, ...}) = 0
[pid  3732] mmap(NULL, 266240, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f63388b9000
[pid  3732] getdents(3, /* 0 entries */, 32768) = 0
[pid  3732] close(3)                    = 0
[pid  3732] gettimeofday({1407424184, 146936}, NULL) = 0
[pid  3732] gettimeofday({1407424184, 146972}, NULL) = 0
[pid  3732] mmap(NULL, 266240, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6338878000
[pid  3732] select(5, NULL, [4], [4], {60, 0}) = 1 (out [4], left {59, 999993})
[pid  3732] write(4, "6\0\0\7\5\f\1.\0\0\20S\270\226\343\375A\0\0\201\365\7vagrant\201\365\7vagrant\230\7aaa.txt\0\24\0\264\201\0\0\0\377\1", 58 <unfinished ...>
[pid  3733] <... select resumed> )      = 1 (in [0], left {59, 996662})
[pid  3732] <... write resumed> )       = 58
[pid  3733] read(0,  <unfinished ...>
[pid  3732] select(6, [5], [], NULL, {60, 0} <unfinished ...>
[pid  3733] <... read resumed> "6\0\0\7", 4) = 4
[pid  3733] select(1, [0], [], NULL, {60, 0}) = 1 (in [0], left {59, 999991})
[pid  3733] read(0, "\5\f\1.\0\0\20S\270\226\343\375A\0\0\201\365\7vagrant\201\365\7vagrant\230\7aaa.txt\0\24\0\264\201\0\0\0\377\1", 54) = 54
[pid  3733] mmap(NULL, 266240, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f633891b000
[pid  3733] socket(PF_FILE, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
[pid  3733] connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
[pid  3733] close(3)                    = 0
[pid  3733] socket(PF_FILE, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
[pid  3733] connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
[pid  3733] close(3)                    = 0
[pid  3733] open("/etc/nsswitch.conf", O_RDONLY) = 3
[pid  3733] fstat(3, {st_mode=S_IFREG|0644, st_size=1688, ...}) = 0
[pid  3733] mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f633896b000
[pid  3733] read(3, "#\n# /etc/nsswitch.conf\n#\n# An example Name Service Switch config file. This file should be\n# sorted with the most-used s"..., 4096) = 1688
[pid  3733] read(3, "", 4096)           = 0
[pid  3733] close(3)                    = 0
[pid  3733] munmap(0x7f633896b000, 4096) = 0
[pid  3733] open("/etc/ld.so.cache", O_RDONLY) = 3
[pid  3733] fstat(3, {st_mode=S_IFREG|0644, st_size=16422, ...}) = 0
[pid  3733] mmap(NULL, 16422, PROT_READ, MAP_PRIVATE, 3, 0) = 0x7f6338967000
[pid  3733] close(3)                    = 0
[pid  3733] open("/lib64/libnss_files.so.2", O_RDONLY) = 3
[pid  3733] read(3, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0\360!\0\0\0\0\0\0@\0\0\0\0\0\0\0H\371\0\0\0\0\0\0\0\0\0\0@\0008\0\t\0@\0!\0 \0\6\0\0\0\5\0\0\0@\0\0\0\0\0\0\0@\0\0\0\0\0\0\0@\0\0\0\0\0\0\0\370\1\0\0\0\0\0\0\370\1\0\0\0\0\0\0\10\0\0\0\0\0\0\0"..., 832) = 832
[pid  3733] fstat(3, {st_mode=S_IFREG|0755, st_size=65928, ...}) = 0
[pid  3733] mmap(NULL, 2151824, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x7f6331d05000
[pid  3733] mprotect(0x7f6331d11000, 2097152, PROT_NONE) = 0
[pid  3733] mmap(0x7f6331f11000, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0xc000) = 0x7f6331f11000
[pid  3733] close(3)                    = 0
[pid  3733] mprotect(0x7f6331f11000, 4096, PROT_READ) = 0
[pid  3733] munmap(0x7f6338967000, 16422) = 0
[pid  3733] open("/etc/passwd", O_RDONLY|O_CLOEXEC) = 3
[pid  3733] fcntl(3, F_GETFD)           = 0x1 (flags FD_CLOEXEC)
[pid  3733] fstat(3, {st_mode=S_IFREG|0644, st_size=1032, ...}) = 0
[pid  3733] mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f633896b000
[pid  3733] read(3, "root:x:0:0:root:/root:/bin/bash\nbin:x:1:1:bin:/bin:/sbin/nologin\ndaemon:x:2:2:daemon:/sbin:/sbin/nologin\nadm:x:3:4:adm:/"..., 4096) = 1032
[pid  3733] close(3)                    = 0
[pid  3733] munmap(0x7f633896b000, 4096) = 0
[pid  3733] socket(PF_FILE, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
[pid  3733] connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
[pid  3733] close(3)                    = 0
[pid  3733] socket(PF_FILE, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
[pid  3733] connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
[pid  3733] close(3)                    = 0
[pid  3733] open("/etc/group", O_RDONLY|O_CLOEXEC) = 3
[pid  3733] fstat(3, {st_mode=S_IFREG|0644, st_size=513, ...}) = 0
[pid  3733] mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f633896b000
[pid  3733] read(3, "root:x:0:\nbin:x:1:bin,daemon\ndaemon:x:2:bin,daemon\nsys:x:3:bin,adm\nadm:x:4:adm,daemon\ntty:x:5:\ndisk:x:6:\nlp:x:7:daemon\nm"..., 4096) = 513
[pid  3733] close(3)                    = 0
[pid  3733] munmap(0x7f633896b000, 4096) = 0
[pid  3733] getegid()                   = 501
[pid  3733] getgroups(0, NULL)          = 2
[pid  3733] getgroups(2, [10, 501])     = 2
[pid  3733] mmap(NULL, 135168, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f63388fa000
[pid  3733] mmap(NULL, 266240, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f63388b9000
[pid  3733] mmap(NULL, 266240, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6338878000
[pid  3733] stat("/tmp/backup2/", {st_mode=S_IFDIR|0775, st_size=4096, ...}) = 0
[pid  3733] chdir("/tmp/backup2/")      = 0
[pid  3733] stat("/tmp/backup1/", {st_mode=S_IFDIR|0775, st_size=4096, ...}) = 0
[pid  3733] socketpair(PF_FILE, SOCK_STREAM, 0, [3, 4]) = 0
[pid  3733] fcntl(3, F_GETFL)           = 0x2 (flags O_RDWR)
[pid  3733] fcntl(3, F_SETFL, O_RDWR|O_NONBLOCK) = 0
[pid  3733] fcntl(4, F_GETFL)           = 0x2 (flags O_RDWR)
[pid  3733] fcntl(4, F_SETFL, O_RDWR|O_NONBLOCK) = 0
[pid  3733] clone(Process 3734 attached
child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7f63389649d0) = 3734
[pid  3733] close(4)                    = 0
[pid  3733] close(0 <unfinished ...>
[pid  3734] close(3 <unfinished ...>
[pid  3733] <... close resumed> )       = 0
[pid  3734] <... close resumed> )       = 0
[pid  3733] lstat(".",  <unfinished ...>
[pid  3734] close(1 <unfinished ...>
[pid  3733] <... lstat resumed> {st_mode=S_IFDIR|0775, st_size=4096, ...}) = 0
[pid  3734] <... close resumed> )       = 0
[pid  3733] lstat(".",  <unfinished ...>
[pid  3734] fcntl(4, F_GETFL <unfinished ...>
[pid  3733] <... lstat resumed> {st_mode=S_IFDIR|0775, st_size=4096, ...}) = 0
[pid  3734] <... fcntl resumed> )       = 0x802 (flags O_RDWR|O_NONBLOCK)
[pid  3733] lstat("aaa.txt",  <unfinished ...>
[pid  3734] select(5, NULL, [4], [4], {60, 0} <unfinished ...>
[pid  3733] <... lstat resumed> 0x7fffcc669fa0) = -1 ENOENT (No such file or directory)
[pid  3734] <... select resumed> )      = 1 (out [4], left {59, 999989})
[pid  3733] lstat("/tmp/backup1/aaa.txt",  <unfinished ...>
[pid  3734] write(4, "\0\0\0\34", 4 <unfinished ...>
[pid  3733] <... lstat resumed> {st_mode=S_IFREG|0664, st_size=10, ...}) = 0
[pid  3734] <... write resumed> )       = 4
[pid  3733] lstat("/tmp/backup1/aaa.txt",  <unfinished ...>
[pid  3734] select(1, [0], [], NULL, {60, 0} <unfinished ...>
[pid  3733] <... lstat resumed> {st_mode=S_IFREG|0664, st_size=10, ...}) = 0
[pid  3733] open("/tmp/backup1/aaa.txt", O_RDONLY) = 0
[pid  3733] close(0)                    = 0
[pid  3733] select(4, [3], [1], [1], {60, 0}) = 2 (in [3], out [1], left {59, 999993})
[pid  3733] select(4, [3], [], NULL, {60, 0}) = 1 (in [3], left {59, 999994})
[pid  3733] read(3, "\0\0\0\34", 8184)  = 4
[pid  3733] write(1, "\24\0\0\7\3\4\210\0\1\0\0\0\274\2\0\0\2\0\0\0\n\0\0\0", 24) = 24
[pid  3732] <... select resumed> )      = 1 (in [5], left {59, 988283})
[pid  3733] gettimeofday( <unfinished ...>
[pid  3732] read(5,  <unfinished ...>
[pid  3733] <... gettimeofday resumed> {1407424184, 159997}, NULL) = 0
[pid  3732] <... read resumed> "\24\0\0\7", 4) = 4
[pid  3733] select(4, [3], [], NULL, {60, 0} <unfinished ...>
[pid  3732] select(6, [5], [], NULL, {60, 0}) = 1 (in [5], left {59, 999993})
[pid  3732] read(5, "\3\4\210\0\1\0\0\0\274\2\0\0\2\0\0\0\n\0\0\0", 20) = 20
[pid  3732] open("aaa.txt", O_RDONLY)   = 3
[pid  3732] fstat(3, {st_mode=S_IFREG|0664, st_size=20, ...}) = 0
[pid  3732] lseek(3, 10, SEEK_SET)      = 10
[pid  3732] read(3, "abcdefghij", 10)   = 10
[pid  3732] close(3)                    = 0
[pid  3732] select(5, NULL, [4], [4], {60, 0}) = 1 (out [4], left {59, 999993})
[pid  3732] write(4, "6\0\0\7\3\4\210\0\1\0\0\0\274\2\0\0\2\0\0\0\n\0\0\0\n\0\0\0abcdefghij\0\0\0\0\251%WiB\351K.\365z\6a\1\264\210v", 58 <unfinished ...>
[pid  3734] <... select resumed> )      = 1 (in [0], left {59, 995355})
[pid  3732] <... write resumed> )       = 58
[pid  3734] read(0,  <unfinished ...>
[pid  3732] select(6, [5], [], NULL, {60, 0} <unfinished ...>
[pid  3734] <... read resumed> "6\0\0\7", 4) = 4
[pid  3734] select(1, [0], [], NULL, {60, 0}) = 1 (in [0], left {59, 999995})
[pid  3734] read(0, "\3\4\210\0\1\0\0\0\274\2\0\0\2\0\0\0\n\0\0\0\n\0\0\0abcdefghij\0\0\0\0\251%WiB\351K.\365z\6a\1\264\210v", 54) = 54
[pid  3734] open("/tmp/backup1/aaa.txt", O_RDONLY) = 1
[pid  3734] fstat(1, {st_mode=S_IFREG|0664, st_size=10, ...}) = 0
[pid  3734] open("aaa.txt", O_WRONLY|O_CREAT, 0600) = 3
[pid  3734] lseek(3, 10, SEEK_SET)      = 10
[pid  3734] mmap(NULL, 266240, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f6338837000
[pid  3734] write(3, "abcdefghij", 10)  = 10
[pid  3734] ftruncate(3, 20)            = 0
[pid  3734] close(1)                    = 0
[pid  3734] close(3)                    = 0
[pid  3734] lstat("aaa.txt", {st_mode=S_IFREG|0600, st_size=20, ...}) = 0
[pid  3734] chmod("aaa.txt", 0664)      = 0
[pid  3734] select(5, NULL, [4], [4], {60, 0}) = 1 (out [4], left {59, 999991})
[pid  3734] write(4, "\4\0\0k\2\0\0\0", 8) = 8
[pid  3733] <... select resumed> )      = 1 (in [3], left {59, 988669})
[pid  3734] select(1, [0], [], NULL, {60, 0} <unfinished ...>
[pid  3733] read(3, "\4\0\0k\2\0\0\0", 8184) = 8
[pid  3733] select(4, [3], [1], [1], {60, 0}) = 1 (out [1], left {59, 999991})
[pid  3733] write(1, "\1\0\0\7\0", 5)   = 5
[pid  3732] <... select resumed> )      = 1 (in [5], left {59, 990812})
[pid  3733] gettimeofday( <unfinished ...>
[pid  3732] read(5,  <unfinished ...>
[pid  3733] <... gettimeofday resumed> {1407424184, 173272}, NULL) = 0
[pid  3732] <... read resumed> "\1\0\0\7", 4) = 4
[pid  3732] select(6, [5], [], NULL, {60, 0} <unfinished ...>
[pid  3733] lstat(".",  <unfinished ...>
[pid  3732] <... select resumed> )      = 1 (in [5], left {59, 999993})
[pid  3733] <... lstat resumed> {st_mode=S_IFDIR|0775, st_size=4096, ...}) = 0
[pid  3732] read(5,  <unfinished ...>
[pid  3733] munmap(0x7f6338878000, 266240 <unfinished ...>
[pid  3732] <... read resumed> "\0", 1) = 1
[pid  3732] munmap(0x7f63388b9000, 266240) = 0
[pid  3732] munmap(0x7f63388fa000, 266240) = 0
[pid  3732] select(5, NULL, [4], [4], {60, 0}) = 1 (out [4], left {59, 999992})
[pid  3732] write(4, "\1\0\0\7\0", 5 <unfinished ...>
[pid  3734] <... select resumed> )      = 1 (in [0], left {59, 997791})
[pid  3732] <... write resumed> )       = 5
[pid  3734] read(0,  <unfinished ...>
[pid  3733] <... munmap resumed> )      = 0
[pid  3732] select(6, [5], [], NULL, {60, 0} <unfinished ...>
[pid  3734] <... read resumed> "\1\0\0\7", 4) = 4
[pid  3733] munmap(0x7f633891b000, 266240 <unfinished ...>
[pid  3734] select(1, [0], [], NULL, {60, 0}) = 1 (in [0], left {59, 999993})
[pid  3733] <... munmap resumed> )      = 0
[pid  3734] read(0, "\0", 1)            = 1
[pid  3734] munmap(0x7f6338878000, 266240 <unfinished ...>
[pid  3733] select(4, [3], [], NULL, {60, 0} <unfinished ...>
[pid  3734] <... munmap resumed> )      = 0
[pid  3734] munmap(0x7f633891b000, 266240) = 0
[pid  3734] select(5, NULL, [4], [4], {60, 0}) = 1 (out [4], left {59, 999993})
[pid  3734] write(4, "\0\0\0]", 4)      = 4
[pid  3733] <... select resumed> )      = 1 (in [3], left {59, 998827})
[pid  3734] select(1, [0], [], NULL, {60, 0} <unfinished ...>
[pid  3733] read(3, "\0\0\0]", 8184)    = 4
[pid  3733] select(4, [3], [1], [1], {60, 0}) = 1 (out [1], left {59, 999993})
[pid  3733] write(1, "\2\0\0\7\0\0", 6) = 6
[pid  3732] <... select resumed> )      = 1 (in [5], left {59, 998058})
[pid  3733] gettimeofday( <unfinished ...>
[pid  3732] read(5,  <unfinished ...>
[pid  3733] <... gettimeofday resumed> {1407424184, 176455}, NULL) = 0
[pid  3732] <... read resumed> "\2\0\0\7", 4) = 4
[pid  3733] select(4, [3], [], NULL, {60, 0} <unfinished ...>
[pid  3732] select(6, [5], [], NULL, {60, 0}) = 1 (in [5], left {59, 999993})
[pid  3732] read(5, "\0\0", 2)          = 2
[pid  3732] select(5, NULL, [4], [4], {60, 0}) = 1 (out [4], left {59, 999989})
[pid  3732] write(4, "\1\0\0\7\0", 5 <unfinished ...>
[pid  3734] <... select resumed> )      = 1 (in [0], left {59, 998060})
[pid  3732] <... write resumed> )       = 5
[pid  3734] read(0,  <unfinished ...>
[pid  3732] select(5, NULL, [4], [4], {60, 0} <unfinished ...>
[pid  3734] <... read resumed> "\1\0\0\7", 4) = 4
[pid  3734] select(1, [0], [], NULL, {60, 0} <unfinished ...>
[pid  3732] <... select resumed> )      = 1 (out [4], left {59, 999991})
[pid  3734] <... select resumed> )      = 1 (in [0], left {59, 999992})
[pid  3732] write(4, "\1\0\0\7\0", 5 <unfinished ...>
[pid  3734] read(0,  <unfinished ...>
[pid  3732] <... write resumed> )       = 5
[pid  3734] <... read resumed> "\0", 1) = 1
[pid  3734] select(5, NULL, [4], [4], {60, 0} <unfinished ...>
[pid  3732] gettimeofday( <unfinished ...>
[pid  3734] <... select resumed> )      = 1 (out [4], left {59, 999992})
[pid  3732] <... gettimeofday resumed> {1407424184, 180159}, NULL) = 0
[pid  3734] write(4, "\0\0\0]", 4 <unfinished ...>
[pid  3732] select(6, [5], [], NULL, {60, 0} <unfinished ...>
[pid  3734] <... write resumed> )       = 4
[pid  3734] select(1, [0], [], NULL, {60, 0} <unfinished ...>
[pid  3733] <... select resumed> )      = 1 (in [3], left {59, 995782})
[pid  3734] <... select resumed> )      = 1 (in [0], left {59, 999993})
[pid  3733] read(3,  <unfinished ...>
[pid  3734] read(0,  <unfinished ...>
[pid  3733] <... read resumed> "\0\0\0]", 8184) = 4
[pid  3733] select(4, [3], [], NULL, {60, 0} <unfinished ...>
[pid  3734] <... read resumed> "\1\0\0\7", 4) = 4
[pid  3734] select(1, [0], [], NULL, {60, 0}) = 1 (in [0], left {59, 999993})
[pid  3734] read(0, "\0", 1)            = 1
[pid  3734] gettimeofday({1407424184, 183808}, NULL) = 0
[pid  3734] select(5, NULL, [4], [4], {60, 0}) = 1 (out [4], left {60, 0})
[pid  3734] write(4, "\1\0\0]\0", 5)    = 5
[pid  3733] <... select resumed> )      = 1 (in [3], left {59, 997173})
[pid  3734] select(5, NULL, [4], [4], {60, 0} <unfinished ...>
[pid  3733] read(3,  <unfinished ...>
[pid  3734] <... select resumed> )      = 1 (out [4], left {59, 999993})
[pid  3733] <... read resumed> "\1\0\0]\0", 8184) = 5
[pid  3734] write(4, "\0s\0", 3 <unfinished ...>
[pid  3733] select(4, [3], [], NULL, {60, 0} <unfinished ...>
[pid  3734] <... write resumed> )       = 3
[pid  3733] <... select resumed> )      = 1 (in [3], left {59, 999993})
[pid  3734] select(1, [0], [], NULL, {60, 0} <unfinished ...>
[pid  3733] read(3, "\0s\0", 8184)      = 3
[pid  3733] gettimeofday({1407424184, 184847}, NULL) = 0
[pid  3733] select(4, [3], [1], [1], {60, 0}) = 1 (out [1], left {59, 999993})
[pid  3733] write(1, "\1\0\0\7\0", 5)   = 5
[pid  3732] <... select resumed> )      = 1 (in [5], left {59, 996141})
[pid  3733] gettimeofday( <unfinished ...>
[pid  3732] read(5,  <unfinished ...>
[pid  3733] <... gettimeofday resumed> {1407424184, 185011}, NULL) = 0
[pid  3732] <... read resumed> "\1\0\0\7", 4) = 4
[pid  3733] kill(3734, SIGUSR2 <unfinished ...>
[pid  3732] select(6, [5], [], NULL, {60, 0} <unfinished ...>
[pid  3734] <... select resumed> )      = ? ERESTARTNOHAND (To be restarted)
[pid  3733] <... kill resumed> )        = 0
[pid  3732] <... select resumed> )      = 1 (in [5], left {59, 999993})
[pid  3734] --- SIGUSR2 (User defined signal 2) @ 0 (0) ---
[pid  3733] wait4(3734,  <unfinished ...>
[pid  3732] read(5,  <unfinished ...>
[pid  3734] exit_group(0)               = ?
Process 3734 detached
[pid  3733] <... wait4 resumed> 0x7fffcc66d1bc, WNOHANG, NULL) = 0
[pid  3732] <... read resumed> "\0", 1) = 1
[pid  3733] --- SIGCHLD (Child exited) @ 0 (0) ---
[pid  3732] wait4(3733,  <unfinished ...>
[pid  3733] wait4(-1,  <unfinished ...>
[pid  3732] <... wait4 resumed> 0x7fffcc67024c, WNOHANG, NULL) = 0
[pid  3733] <... wait4 resumed> [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], WNOHANG, NULL) = 3734
[pid  3732] gettimeofday( <unfinished ...>
[pid  3733] wait4(-1,  <unfinished ...>
[pid  3732] <... gettimeofday resumed> {1407424184, 185851}, NULL) = 0
[pid  3733] <... wait4 resumed> 0x7fffcc66ccdc, WNOHANG, NULL) = -1 ECHILD (No child processes)
[pid  3732] select(0, NULL, NULL, NULL, {0, 20000} <unfinished ...>
[pid  3733] rt_sigreturn(0xffffffffffffffff) = 0
[pid  3733] gettimeofday({1407424184, 185999}, NULL) = 0
[pid  3733] select(0, NULL, NULL, NULL, {0, 20000}) = 0 (Timeout)
[pid  3732] <... select resumed> )      = 0 (Timeout)
[pid  3733] gettimeofday( <unfinished ...>
[pid  3732] gettimeofday( <unfinished ...>
[pid  3733] <... gettimeofday resumed> {1407424184, 207079}, NULL) = 0
[pid  3732] <... gettimeofday resumed> {1407424184, 207017}, NULL) = 0
[pid  3733] wait4(3734,  <unfinished ...>
[pid  3732] wait4(3733,  <unfinished ...>
[pid  3733] <... wait4 resumed> 0x7fffcc66d1bc, WNOHANG, NULL) = -1 ECHILD (No child processes)
[pid  3732] <... wait4 resumed> 0x7fffcc67024c, WNOHANG, NULL) = 0
[pid  3733] rt_sigaction(SIGUSR1, {SIG_IGN, [], SA_RESTORER, 0x7f6337fdb9a0},  <unfinished ...>
[pid  3732] gettimeofday( <unfinished ...>
[pid  3733] <... rt_sigaction resumed> NULL, 8) = 0
[pid  3732] <... gettimeofday resumed> {1407424184, 207728}, NULL) = 0
[pid  3733] rt_sigaction(SIGUSR2, {SIG_IGN, [], SA_RESTORER, 0x7f6337fdb9a0},  <unfinished ...>
[pid  3732] select(0, NULL, NULL, NULL, {0, 20000} <unfinished ...>
[pid  3733] <... rt_sigaction resumed> NULL, 8) = 0
[pid  3733] exit_group(0)               = ?
Process 3733 detached
<... select resumed> )                  = ? ERESTARTNOHAND (To be restarted)
--- SIGCHLD (Child exited) @ 0 (0) ---
wait4(-1, [{WIFEXITED(s) && WEXITSTATUS(s) == 0}], WNOHANG, NULL) = 3733
wait4(-1, 0x7fffcc66fd5c, WNOHANG, NULL) = -1 ECHILD (No child processes)
rt_sigreturn(0xffffffffffffffff)        = -1 EINTR (Interrupted system call)
gettimeofday({1407424184, 208347}, NULL) = 0
select(0, NULL, NULL, NULL, {0, 20000}) = 0 (Timeout)
gettimeofday({1407424184, 229839}, NULL) = 0
wait4(3733, 0x7fffcc67024c, WNOHANG, NULL) = -1 ECHILD (No child processes)
rt_sigaction(SIGUSR1, {SIG_IGN, [], SA_RESTORER, 0x7f6337fdb9a0}, NULL, 8) = 0
rt_sigaction(SIGUSR2, {SIG_IGN, [], SA_RESTORER, 0x7f6337fdb9a0}, NULL, 8) = 0
wait4(3733, 0x7fffcc67023c, WNOHANG, NULL) = -1 ECHILD (No child processes)
exit_group(0)                           = ?
```

## ソース

> gen mapped /tmp/backup1/aaa.txt of size 5

```c
	if (verbose > 3) {
		rprintf(FINFO, "gen mapped %s of size %.0f\n",
			fnamecmp, (double)sx.st.st_size);
	}
```

> send_files mapped /tmp/src/aaa.txt of size 10

```c
		if (verbose > 2) {
			rprintf(FINFO, "send_files mapped %s%s%s of size %.0f\n",
				path,slash,fname, (double)st.st_size);
		}

```