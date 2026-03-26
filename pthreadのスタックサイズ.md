## pthread のスタックサイズについて

スタックが伸縮する際にページフレームは破棄 (relcaim) されるのか?

 * pthread のスタックは mmap で作られる
   * http://d.hatena.ne.jp/hiboma/20130310/1362926275
 * pthread_exit する際に madvise( ..., MADV_DONTNEED) でページフレームを reclaim する
   * CentOS6.5 で確認
   * CentOS4, CentOS5(!) では madvise していなかった。pthread_exit してもページフレームは reclaim されない

[madvise-MADV_DONTNEED.md](https://github.com/hiboma/hiboma/blob/master/madvise-MADV_DONTNEED.md) も読もう

## 検証コード

 * スレッドを一本はやして、SIGSEGV を起こすギリギリまでスタック領域を使う
   * alloca しまくってマイナーページフォルトを起こさせる
 * スタックを使いきってすぐに、pmap を見る
 * スタックを使い切った関数を抜けて pmap を見る
 * スレッドが pthread_exit さい後に pmap を見る

pmap の RSS の数値の増減を見て、ページフレームの割り当てを確認できる

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
00007f73ecdb5000   10240       8       8 rw---    [ anon ]         # スレッドのスタック
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
00007f73ecdb5000   10240   10240   10240 rw---    [ anon ]         # RSS が 10240KB に増えた
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
00007f73ecdb5000   10240   10240   10240 rw---    [ anon ]         # run_out_stack_space を抜けても RSS の数値は変わらない
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
00007f73ecdb4000       4     
00007f73ecdb5000   10240      24      24 rw---    [ anon ]        # pthread_exit すると RSS の数値が下がる
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

## pthread と madvise とスタックリージョン

 * pthread_exit する際に madvise( ..., MADV_DONTNEED )を呼び出してスタックのページフレームを reclaim する
   * CentOS6.4  glibc-2.12
   * CentOS5.10 glibc-2.5 でも実装されていない
      * 下記に補足
   * CentOS4.8 glibc-2.3.4 だと実装されていない

スタックの全ページを対象にしていない (スタック用の TLS, デスクリプタなどが置かれているフレームは除く)

```c
// glibc/nptl/pthread_create.c

  /* Mark the memory of the stack as usable to the kernel.  We free
     everything except for the space used for the TCB itself.  */
  size_t pagesize_m1 = __getpagesize () - 1;
#ifdef _STACK_GROWS_DOWN
  char *sp = CURRENT_STACK_FRAME;
  size_t freesize = (sp - (char *) pd->stackblock) & ~pagesize_m1;
#else
# error "to do"
#endif
  assert (freesize < pd->stackblock_size);
  if (freesize > PTHREAD_STACK_MIN)
    madvise (pd->stackblock, freesize - PTHREAD_STACK_MIN, MADV_DONTNEED);
```

libc のパッチ (git clone git://sourceware.org/git/glibc.git git show b42a214c)

```diff
commit b42a214c1807dc596cf3647fc35a0eb42ccc7e68
Author: Ulrich Drepper <drepper@redhat.com>
Date:   Mon Aug 24 16:23:47 2009 -0700

    Hint to kernel that thread stack memory can be removed.

diff --git a/nptl/ChangeLog b/nptl/ChangeLog
index 098ef3b..3887969 100644
--- a/nptl/ChangeLog
+++ b/nptl/ChangeLog
@@ -1,3 +1,9 @@
+2009-08-24  Ulrich Drepper  <drepper@redhat.com>
+
+	* pthread_create.c (start_thread): Hint to the kernel that memory for
+	the stack can be reused.  We do not mark all the memory.  The part
+	still in use and some reserve are kept.
+
 2009-08-23  Ulrich Drepper  <drepper@redhat.com>
 
 	* sysdeps/unix/sysv/linux/bits/posix_opt.h: Clean up namespace.
@@ -1847,9 +1853,9 @@
 	* sysdeps/unix/sysv/linux/sh/bits/pthreadtypes.h: Include endian.h.
 	Split __flags into __flags, __shared, __pad1 and __pad2.
 	* sysdeps/unix/sysv/linux/sh/libc-lowlevellock.S: Use private
-        futexes if they are available.
+	futexes if they are available.
 	* sysdeps/unix/sysv/linux/sh/lowlevellock.S: Adjust so that change
-        in libc-lowlevellock.S allow using private futexes.
+	in libc-lowlevellock.S allow using private futexes.
 	* sysdeps/unix/sysv/linux/sh/lowlevellock.h: Define
 	FUTEX_PRIVATE_FLAG.  Add additional parameter to lll_futex_wait,
 	lll_futex_timed_wait and lll_futex_wake.  Change lll_futex_wait
@@ -1857,12 +1863,12 @@
 	lll_private_futex_timed_wait and lll_private_futex_wake.
 	(lll_robust_mutex_unlock): Fix typo.
 	* sysdeps/unix/sysv/linux/sh/pthread_barrier_wait.S: Use private
-        field in futex command setup.
+	field in futex command setup.
 	* sysdeps/unix/sysv/linux/sh/pthread_cond_timedwait.S: Use
 	COND_NWAITERS_SHIFT instead of COND_CLOCK_BITS.
 	* sysdeps/unix/sysv/linux/sh/pthread_cond_wait.S: Likewise.
 	* sysdeps/unix/sysv/linux/sh/pthread_once.S: Use private futexes
-        if they are available.  Remove clear_once_control.
+	if they are available.  Remove clear_once_control.
 	* sysdeps/unix/sysv/linux/sh/pthread_rwlock_rdlock.S: Use private
 	futexes if they are available.
 	* sysdeps/unix/sysv/linux/sh/pthread_rwlock_timedrdlock.S: Likewise.
@@ -1873,7 +1879,7 @@
 	Wake only when there are waiters.
 	* sysdeps/unix/sysv/linux/sh/sem_wait.S: Add private futex
 	support.  Indicate that there are waiters.  Remove unnecessary
-        extra cancellation test.
+	extra cancellation test.
 	* sysdeps/unix/sysv/linux/sh/sem_timedwait.S: Likewise.  Removed
 	left-over duplication of __sem_wait_cleanup.
 
@@ -2587,14 +2593,14 @@
 	* tst-cancel25.c: New file.
 
 2006-09-05  Jakub Jelinek  <jakub@redhat.com>
-            Ulrich Drepper  <drepper@redhat.com>
+	    Ulrich Drepper  <drepper@redhat.com>
 
 	* sysdeps/pthread/gai_misc.h (GAI_MISC_NOTIFY): Don't decrement
 	counterp if it is already zero.
 	* sysdeps/pthread/aio_misc.h (AIO_MISC_NOTIFY): Likewise..
 
 2006-03-04  Jakub Jelinek  <jakub@redhat.com>
-            Roland McGrath  <roland@redhat.com>
+	    Roland McGrath  <roland@redhat.com>
 
 	* sysdeps/unix/sysv/linux/i386/lowlevellock.h
 	(LLL_STUB_UNWIND_INFO_START, LLL_STUB_UNWIND_INFO_END,
@@ -2608,7 +2614,7 @@
 	* sysdeps/unix/sysv/linux/i386/i486/lowlevelrobustlock.S: Likewise.
 
 2006-03-03  Jakub Jelinek  <jakub@redhat.com>
-            Roland McGrath  <roland@redhat.com>
+	    Roland McGrath  <roland@redhat.com>
 
 	* sysdeps/unix/sysv/linux/x86_64/lowlevellock.h
 	(LLL_STUB_UNWIND_INFO_START, LLL_STUB_UNWIND_INFO_END,
@@ -3181,7 +3187,7 @@
 	* sysdeps/pthread/pthread.h: Adjust mutex initializers.
 
 	* sysdeps/unix/sysv/linux/i386/not-cancel.h: Define openat_not_cancel,
-        openat_not_cancel_3, openat64_not_cancel, and openat64_not_cancel_3.
+	openat_not_cancel_3, openat64_not_cancel, and openat64_not_cancel_3.
 
 2006-02-08  Jakub Jelinek  <jakub@redhat.com>
 
@@ -3603,7 +3609,7 @@
 	* Makefile ($(test-modules)): Remove static pattern rule.
 
 2005-10-14  Jakub Jelinek  <jakub@redhat.com>
-            Ulrich Drepper  <drepper@redhat.com>
+	    Ulrich Drepper  <drepper@redhat.com>
 
 	* sysdeps/unix/sysv/linux/x86_64/pthread_once.S: Fix stack
 	alignment in callback function.
@@ -3621,7 +3627,7 @@
 	atomic_compare_and_exchange_bool_acq.
 
 2005-10-01  Ulrich Drepper  <drepper@redhat.com>
-            Jakub Jelinek  <jakub@redhat.com>
+	    Jakub Jelinek  <jakub@redhat.com>
 
 	* descr.h: Define SETXID_BIT and SETXID_BITMASK.  Adjust
 	CANCEL_RESTMASK.
diff --git a/nptl/pthread_create.c b/nptl/pthread_create.c
index c693979..89938b3 100644
--- a/nptl/pthread_create.c
+++ b/nptl/pthread_create.c
@@ -377,6 +377,19 @@ start_thread (void *arg)
     }
 #endif
 
+  /* Mark the memory of the stack as usable to the kernel.  We free
+     everything except for the space used for the TCB itself.  */
+  size_t pagesize_m1 = __getpagesize () - 1;
+#ifdef _STACK_GROWS_DOWN
+  char *sp = CURRENT_STACK_FRAME;
+  size_t freesize = (sp - (char *) pd->stackblock) & ~pagesize_m1;
+#else
+# error "to do"
+#endif
+  assert (freesize < pd->stackblock_size);
+  if (freesize > PTHREAD_STACK_MIN)
+    madvise (pd->stackblock, freesize - PTHREAD_STACK_MIN, MADV_DONTNEED);
+
   /* If the thread is detached free the TCB.  */
   if (IS_DETACHED (pd))
     /* Free the TCB.  */
```

[pthread-stacksize.md](https://github.com/hiboma/hiboma/blob/master/pthread-stacksize.md) を読もう

### CentOS5.10 glibc-2.5 で寄り道

 * madvise の MADV_DONTNEED はページの内容をディスクに書き戻さない
 * POSIX の POSIX_MADV_DONTNEED の挙動と違う
 * posix_madvise(2) では MADV_DONTNEED を指定するとシステムコールを呼び出さず無視される
```c
+#include <sysdep.h>
+#include <sys/mman.h>
+
+
+int
+posix_madvise (void *addr, size_t len, int advice)
+{
+  /* We have one problem: the kernel's MADV_DONTNEED does not
+     correspond to POSIX's POSIX_MADV_DONTNEED.  The former simply
+     discards changes made to the memory without writing it back to
+     disk, if this would be necessary.  The POSIX behavior does not
+     allow this.  There is no functionality mapping the POSIX behavior
+     so far so we ignore that advice for now.  */
+  if (advice == POSIX_MADV_DONTNEED)
+    return 0;
+
+  INTERNAL_SYSCALL_DECL (err);
+  int result = INTERNAL_SYSCALL (madvise, err, 3, addr, len, advice);
+  return INTERNAL_SYSCALL_ERRNO (result, err);
+}
```

知らないとドはまりしそう
