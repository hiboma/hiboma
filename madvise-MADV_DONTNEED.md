# madvise, MADV_DONTNEED

http://linux.die.net/man/2/madvise

```c
int madvise(void *addr, size_t length, int advice);
```

> MADV_DONTNEED
> Do not expect access in the near future. (For the time being, the application is finished with the given range, so the kernel can free resources associated with it.) Subsequent accesses of pages in this range will succeed, but will result either in reloading of the memory contents from the underlying mapped file (see mmap(2)) or zero-fill-on-demand pages for mappings without an underlying file.

## mmap した 無名メモリリージョンのページフレームを解放する

```c
#if 0
#!/bin/bash
o=`basename $0`
o="__${o%.*}"
CFLAGS="-O0 -g -std=gnu99 -W -Wall"
gcc ${CFLAGS} ${LDFLAGS} -o $o $0 && ./$o $*; exit
#endif

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <err.h>

void pmap() {
	char command[30];
	sprintf(command, "pmap -x %d", getpid());
	system(command);
}

int main(){

	size_t mmap_size = sysconf(_SC_PAGESIZE) * 1024;
	char *p = mmap(NULL, mmap_size, PROT_READ|PROT_WRITE,
		       MAP_PRIVATE|MAP_ANONYMOUS, 0,0);
	if (!p)
		err(1, "mmap failed");

	// for (size_t i = 0; i < mmap_size; i++)
	//         p[i] = '\0';
	memset(p, 0, mmap_size);

	pmap();

	if(madvise(p, mmap_size, MADV_DONTNEED) == -1)
		err(1, "madvise failed");

	pmap();
  exit(0);
}
```

実行結果

```
[vagrant@vagrant-centos65 vagrant]$ bash mmap.c 
29551:   ./__mmap
Address           Kbytes     RSS   Dirty Mode   Mapping
0000000000400000       4       4       0 r-x--  __mmap
0000000000600000       4       4       4 rw---  __mmap
00007f8de3b19000    4096    4096    4096 rw---    [ anon ]
00007f8de3f19000    1580     264       0 r-x--  libc-2.12.so
00007f8de40a4000    2044       0       0 -----  libc-2.12.so
00007f8de42a3000      16      16      16 r----  libc-2.12.so
00007f8de42a7000       4       4       4 rw---  libc-2.12.so
00007f8de42a8000      20      12      12 rw---    [ anon ]
00007f8de42ad000     128     104       0 r-x--  ld-2.12.so
00007f8de44c3000      12      12      12 rw---    [ anon ]
00007f8de44cb000       4       4       4 rw---    [ anon ]
00007f8de44cc000       4       4       4 r----  ld-2.12.so
00007f8de44cd000       4       4       4 rw---  ld-2.12.so
00007f8de44ce000       4       4       4 rw---    [ anon ]
00007fff4867e000      84      12      12 rw---    [ stack ]
00007fff487b1000       4       4       0 r-x--    [ anon ]
ffffffffff600000       4       0       0 r-x--    [ anon ]
----------------  ------  ------  ------
total kB            8016    4548    4172
29551:   ./__mmap
Address           Kbytes     RSS   Dirty Mode   Mapping
0000000000400000       4       4       0 r-x--  __mmap
0000000000600000       4       4       4 rw---  __mmap
00007f8de3b19000    4096       0       0 rw---    [ anon ]
00007f8de3f19000    1580     264       0 r-x--  libc-2.12.so
00007f8de40a4000    2044       0       0 -----  libc-2.12.so
00007f8de42a3000      16      16      16 r----  libc-2.12.so
00007f8de42a7000       4       4       4 rw---  libc-2.12.so
00007f8de42a8000      20      12      12 rw---    [ anon ]
00007f8de42ad000     128     104       0 r-x--  ld-2.12.so
00007f8de44c3000      12      12      12 rw---    [ anon ]
00007f8de44cb000       4       4       4 rw---    [ anon ]
00007f8de44cc000       4       4       4 r----  ld-2.12.so
00007f8de44cd000       4       4       4 rw---  ld-2.12.so
00007f8de44ce000       4       4       4 rw---    [ anon ]
00007fff4867e000      84      12      12 rw---    [ stack ]
00007fff487b1000       4       4       0 r-x--    [ anon ]
ffffffffff600000       4       0       0 r-x--    [ anon ]
----------------  ------  ------  ------
total kB            8016     452      76
```

 * munmap と違って、ページフレーム (private dirty) が 0 になった