## pthread のスタックサイズについて

 * pthread のスタックは mmap で作られる
   * http://d.hatena.ne.jp/hiboma/20130310/1362926275
 * スタックが伸縮する際にページフレームは relcaim されるのか? が疑問
   * => 結論されない
   * pthread_exit する際に madvise( ..., MADV_DONTNEED) でページフレームを reclaim する
   * munmap するかと思いきやそうではなかった

## 検証コード

 * SIGSEGV を起こすギリギリまでスタック領域を使う
   * alloca しまくる

```c
#if 0
#!/bin/bash
o=`basename $0`
o="__${o%.*}"
CFLAGS="-O2 -g -std=gnu99 -W -pthread -Wall -Wno-unused-parameter"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#define _GNU_SOURCE
#include <unistd.h>
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

void show_pmap() {
	char *shell_pmap;

	/* use the heap, luke */
	asprintf(&shell_pmap, "/usr/bin/pmap -x %d", getpid());
	system(shell_pmap);
	free(shell_pmap);
}

void run_out_stack_space() {
	size_t alloca_size = sysconf(_SC_PAGESIZE);

	for(int j = 0; j < 2548; j++) {
		/* allocate memory from stack */
		char *p = alloca(alloca_size);

		/* cause minor page fault */
		for (size_t i = 0; i < alloca_size; i++)
			p[i] = '\0';
	}

	fprintf(stderr, "> In run_out_stack_space\n");
	show_pmap();
}

void * start_thread(void *arg) {

	fprintf(stderr, "> Before run_out_stack_space\n");
	show_pmap();

	run_out_stack_space();
	fprintf(stderr, "> After run_out_stack_space\n");
	show_pmap();

	return NULL;
}

int main() {
	pthread_t thread;

	if(pthread_create(&thread, NULL, start_thread, NULL))
		err(1, "pthread_create");

	pthread_join(thread, NULL);

	fprintf(stderr, "> After pthread_join\n");

	show_pmap();
	exit(0);
}
```

## 実行結果

```
[vagrant@vagrant-centos65 vagrant]$  ./__recursive 
> Before run_out_stack_space
29600:   ./__recursive
Address           Kbytes     RSS   Dirty Mode   Mapping
0000000000400000       4       4       0 r-x--  __recursive
0000000000600000       4       4       4 rw---  __recursive
000000000157e000     132       4       4 rw---    [ anon ]
00007f73e8000000     132       4       4 rw---    [ anon ]
00007f73e8021000   65404       0       0 -----    [ anon ]
00007f73ecdb4000       4       0       0 -----    [ anon ]
00007f73ecdb5000   10240       8       8 rw---    [ anon ]
00007f73ed7b5000    1580     320       0 r-x--  libc-2.12.so
00007f73ed940000    2044       0       0 -----  libc-2.12.so
00007f73edb3f000      16      16      16 r----  libc-2.12.so
00007f73edb43000       4       4       4 rw---  libc-2.12.so
00007f73edb44000      20      16      16 rw---    [ anon ]
00007f73edb49000      92      60       0 r-x--  libpthread-2.12.so
00007f73edb60000    2048       0       0 -----  libpthread-2.12.so
00007f73edd60000       4       4       4 r----  libpthread-2.12.so
00007f73edd61000       4       4       4 rw---  libpthread-2.12.so
00007f73edd62000      16       4       4 rw---    [ anon ]
00007f73edd66000     128     104       0 r-x--  ld-2.12.so
00007f73edf7c000      12      12      12 rw---    [ anon ]
00007f73edf84000       4       4       4 rw---    [ anon ]
00007f73edf85000       4       4       4 r----  ld-2.12.so
00007f73edf86000       4       4       4 rw---  ld-2.12.so
00007f73edf87000       4       4       4 rw---    [ anon ]
00007fff206e2000      84      12      12 rw---    [ stack ]
00007fff207ff000       4       4       0 r-x--    [ anon ]
ffffffffff600000       4       0       0 r-x--    [ anon ]
----------------  ------  ------  ------
total kB           81996     600     108
> In run_out_stack_space
29600:   ./__recursive
Address           Kbytes     RSS   Dirty Mode   Mapping
0000000000400000       4       4       0 r-x--  __recursive
0000000000600000       4       4       4 rw---  __recursive
000000000157e000     132       4       4 rw---    [ anon ]
00007f73e8000000     132       4       4 rw---    [ anon ]
00007f73e8021000   65404       0       0 -----    [ anon ]
00007f73ecdb4000       4       0       0 -----    [ anon ]
00007f73ecdb5000   10240   10240   10240 rw---    [ anon ]
00007f73ed7b5000    1580     324       0 r-x--  libc-2.12.so
00007f73ed940000    2044       0       0 -----  libc-2.12.so
00007f73edb3f000      16      16      16 r----  libc-2.12.so
00007f73edb43000       4       4       4 rw---  libc-2.12.so
00007f73edb44000      20      16      16 rw---    [ anon ]
00007f73edb49000      92      60       0 r-x--  libpthread-2.12.so
00007f73edb60000    2048       0       0 -----  libpthread-2.12.so
00007f73edd60000       4       4       4 r----  libpthread-2.12.so
00007f73edd61000       4       4       4 rw---  libpthread-2.12.so
00007f73edd62000      16       4       4 rw---    [ anon ]
00007f73edd66000     128     104       0 r-x--  ld-2.12.so
00007f73edf7c000      12      12      12 rw---    [ anon ]
00007f73edf84000       4       4       4 rw---    [ anon ]
00007f73edf85000       4       4       4 r----  ld-2.12.so
00007f73edf86000       4       4       4 rw---  ld-2.12.so
00007f73edf87000       4       4       4 rw---    [ anon ]
00007fff206e2000      84      12      12 rw---    [ stack ]
00007fff207ff000       4       4       0 r-x--    [ anon ]
ffffffffff600000       4       0       0 r-x--    [ anon ]
----------------  ------  ------  ------
total kB           81996   10836   10340
> After run_out_stack_space
29600:   ./__recursive
Address           Kbytes     RSS   Dirty Mode   Mapping
0000000000400000       4       4       0 r-x--  __recursive
0000000000600000       4       4       4 rw---  __recursive
000000000157e000     132       4       4 rw---    [ anon ]
00007f73e8000000     132       4       4 rw---    [ anon ]
00007f73e8021000   65404       0       0 -----    [ anon ]
00007f73ecdb4000       4       0       0 -----    [ anon ]
00007f73ecdb5000   10240   10240   10240 rw---    [ anon ]
00007f73ed7b5000    1580     324       0 r-x--  libc-2.12.so
00007f73ed940000    2044       0       0 -----  libc-2.12.so
00007f73edb3f000      16      16      16 r----  libc-2.12.so
00007f73edb43000       4       4       4 rw---  libc-2.12.so
00007f73edb44000      20      16      16 rw---    [ anon ]
00007f73edb49000      92      60       0 r-x--  libpthread-2.12.so
00007f73edb60000    2048       0       0 -----  libpthread-2.12.so
00007f73edd60000       4       4       4 r----  libpthread-2.12.so
00007f73edd61000       4       4       4 rw---  libpthread-2.12.so
00007f73edd62000      16       4       4 rw---    [ anon ]
00007f73edd66000     128     104       0 r-x--  ld-2.12.so
00007f73edf7c000      12      12      12 rw---    [ anon ]
00007f73edf84000       4       4       4 rw---    [ anon ]
00007f73edf85000       4       4       4 r----  ld-2.12.so
00007f73edf86000       4       4       4 rw---  ld-2.12.so
00007f73edf87000       4       4       4 rw---    [ anon ]
00007fff206e2000      84      12      12 rw---    [ stack ]
00007fff207ff000       4       4       0 r-x--    [ anon ]
ffffffffff600000       4       0       0 r-x--    [ anon ]
----------------  ------  ------  ------
total kB           81996   10836   10340
> After pthread_join
29600:   ./__recursive
Address           Kbytes     RSS   Dirty Mode   Mapping
0000000000400000       4       4       0 r-x--  __recursive
0000000000600000       4       4       4 rw---  __recursive
000000000157e000     132       4       4 rw---    [ anon ]
00007f73e8000000     132       4       4 rw---    [ anon ]
00007f73e8021000   65404       0       0 -----    [ anon ]
00007f73ecdb4000       4       0       0 -----    [ anon ]
00007f73ecdb5000   10240      24      24 rw---    [ anon ]
00007f73ed7b5000    1580     328       0 r-x--  libc-2.12.so
00007f73ed940000    2044       0       0 -----  libc-2.12.so
00007f73edb3f000      16      16      16 r----  libc-2.12.so
00007f73edb43000       4       4       4 rw---  libc-2.12.so
00007f73edb44000      20      16      16 rw---    [ anon ]
00007f73edb49000      92      60       0 r-x--  libpthread-2.12.so
00007f73edb60000    2048       0       0 -----  libpthread-2.12.so
00007f73edd60000       4       4       4 r----  libpthread-2.12.so
00007f73edd61000       4       4       4 rw---  libpthread-2.12.so
00007f73edd62000      16       4       4 rw---    [ anon ]
00007f73edd66000     128     104       0 r-x--  ld-2.12.so
00007f73edf7c000      12      12      12 rw---    [ anon ]
00007f73edf84000       4       4       4 rw---    [ anon ]
00007f73edf85000       4       4       4 r----  ld-2.12.so
00007f73edf86000       4       4       4 rw---  ld-2.12.so
00007f73edf87000       4       4       4 rw---    [ anon ]
00007fff206e2000      84      12      12 rw---    [ stack ]
00007fff207ff000       4       4       0 r-x--    [ anon ]
ffffffffff600000       4       0       0 r-x--    [ anon ]
----------------  ------  ------  ------
total kB           81996     624     124
```