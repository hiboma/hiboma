# SIGBUS

## mmap(2) で MAP_FILE してファイルサイズの範囲外にアクセス

下記のようなコードで検証再現できる

```c
#if 0
CFLAGS="-g -O0 -std=gnu99 -W -Wall"
o=`basename $0`
o=".${o%.*}"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

int main()
{
	int fd = open("/tmp/size-zeo.txt", O_CREAT|O_RDWR);
	if (fd == -1) {
		perror("open");
		exit(1);
	}

	char *p = (char *)mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_FILE|MAP_SHARED, fd, 0);
	if (p == MAP_FAILED) {
		perror("failed mmap");
		exit(2);
	}

	p[0] = 1;
 
	pause();
	exit(0);
}
```

当たり前だけど strace では観測できない

```console
[vagrant@vagrant-centos65 emacs-24.3]$ strace ./.sigbus 
execve("./.sigbus", ["./.sigbus"], [/* 22 vars */]) = 0
brk(0)                                  = 0x2573000
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7ffe6da50000
access("/etc/ld.so.preload", R_OK)      = -1 ENOENT (No such file or directory)
open("/etc/ld.so.cache", O_RDONLY)      = 3
fstat(3, {st_mode=S_IFREG|0644, st_size=31980, ...}) = 0
mmap(NULL, 31980, PROT_READ, MAP_PRIVATE, 3, 0) = 0x7ffe6da48000
close(3)                                = 0
open("/lib64/libc.so.6", O_RDONLY)      = 3
read(3, "\177ELF\2\1\1\3\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0000\356\1\0\0\0\0\0"..., 832) = 832
fstat(3, {st_mode=S_IFREG|0755, st_size=1921216, ...}) = 0
mmap(NULL, 3750152, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x7ffe6d49e000
mprotect(0x7ffe6d629000, 2093056, PROT_NONE) = 0
mmap(0x7ffe6d828000, 20480, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0x18a000) = 0x7ffe6d828000
mmap(0x7ffe6d82d000, 18696, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_ANONYMOUS, -1, 0) = 0x7ffe6d82d000
close(3)                                = 0
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7ffe6da47000
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7ffe6da46000
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7ffe6da45000
arch_prctl(ARCH_SET_FS, 0x7ffe6da46700) = 0
mprotect(0x7ffe6d828000, 16384, PROT_READ) = 0
mprotect(0x7ffe6da51000, 4096, PROT_READ) = 0
munmap(0x7ffe6da48000, 31980)           = 0
open("/tmp/size-zeo.txt", O_RDWR|O_CREAT, 03777753302776770) = 3
mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED, 3, 0) = 0x7ffe6da4f000
--- SIGBUS (Bus error) @ 0 (0) ---
+++ killed by SIGBUS +++
Bus error
```

Kazuho さんの書かれている [Apache+mod_sslでSIGBUSが発生した件](http://blog.kazuhooku.com/2014/05/apachemodsslsigbus.html) が同種のバグになる

### 実装の推測

 * mmap(2) した仮想アドレスを参照する
 * mmap(2) した直後で PTE が無いのでページフォルトする
 * アクセスしたアドレスのリージョンは MAP_FILE された vm_area_struct なので struct vm_operations のうんにゃらを呼ぶ
 * ファイルの中身をページイン? しようとするがサイズ0
 * => SIGBUS ?

### カーネルの実装を追う

適当に grep すると VM_FAULT_SIGBUS なるフラグが見つかる

```c
#define VM_FAULT_SIGBUS	0x0002
```