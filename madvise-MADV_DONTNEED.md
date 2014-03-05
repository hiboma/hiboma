# madvise, MADV_DONTNEED

http://linux.die.net/man/2/madvise

```c
int madvise(void *addr, size_t length, int advice);
```

> MADV_DONTNEED
> Do not expect access in the near future. (For the time being, the application is finished with the given range, so the kernel can free resources associated with it.) Subsequent accesses of pages in this range will succeed, but will result either in reloading of the memory contents from the underlying mapped file (see mmap(2)) or zero-fill-on-demand pages for mappings without an underlying file.

## mmap した 無名メモリリージョンのページフレームを解放する

コードの概要

 * mmap で無名メモリリージョンを割り当て
 * memset で 0 初期化 (マイナーページフォルトを起こす)
 * pmap を取る
 * madvise( ..., MADV_DONTNEED) する
 * 再度 pmap を取る

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

#### 実行結果

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

 * ページフレーム (private dirty) のサイズが 0 になった
 * 仮想アドレスは残る ( vm_area_struct ?)

いわゆる「メモリ解放」として機能している

## MADV_DONTNEED のカーネルコード 2.6.32

```c 
static long
madvise_vma(struct vm_area_struct *vma, struct vm_area_struct **prev,
		unsigned long start, unsigned long end, int behavior)
{
	switch (behavior) {
	case MADV_REMOVE:
		return madvise_remove(vma, prev, start, end);
	case MADV_WILLNEED:
		return madvise_willneed(vma, prev, start, end);
	case MADV_DONTNEED:
		return madvise_dontneed(vma, prev, start, end);
	default:
		return madvise_behavior(vma, prev, start, end, behavior);
	}
}
```

madvise_dontneed の中身

```c
/*
 * Application no longer needs these pages.  If the pages are dirty,
 * it's OK to just throw them away.  The app will be more careful about
 * data it wants to keep.  Be sure to free swap resources too.  The
 * zap_page_range call sets things up for shrink_active_list to actually free
 * these pages later if no one else has touched them in the meantime,
 * although we could add these pages to a global reuse list for
 * shrink_active_list to pick up before reclaiming other pages.
 *
 * NB: This interface discards data rather than pushes it out to swap,
 * as some implementations do.  This has performance implications for
 * applications like large transactional databases which want to discard
 * pages in anonymous maps after committing to backing store the data
 * that was kept in them.  There is no reason to write this data out to
 * the swap area if the application is discarding it.
 *
 * An interface that causes the system to free clean pages and flush
 * dirty pages is already available as msync(MS_INVALIDATE).
 */
static long madvise_dontneed(struct vm_area_struct * vma,
			     struct vm_area_struct ** prev,
			     unsigned long start, unsigned long end)
{
	*prev = vma;
	if (vma->vm_flags & (VM_LOCKED|VM_HUGETLB|VM_PFNMAP))
		return -EINVAL;

	if (unlikely(vma->vm_flags & VM_NONLINEAR)) {
		struct zap_details details = {
			.nonlinear_vma = vma,
			.last_index = ULONG_MAX,
		};
		zap_page_range(vma, start, end - start, &details);
	} else
		zap_page_range(vma, start, end - start, NULL);
	return 0;
}
```

zap_page_range は munmap の過程でも呼ばれている

```c
/**
 * zap_page_range - remove user pages in a given range
 * @vma: vm_area_struct holding the applicable pages
 * @address: starting address of pages to zap
 * @size: number of bytes to zap
 * @details: details of nonlinear truncation or shared cache invalidation
 */
unsigned long zap_page_range(struct vm_area_struct *vma, unsigned long address,
		unsigned long size, struct zap_details *details)
{
	struct mm_struct *mm = vma->vm_mm;
	struct mmu_gather *tlb;
	unsigned long end = address + size;
	unsigned long nr_accounted = 0;

	lru_add_drain();
	update_hiwater_rss(mm);
	end = unmap_vmas(&tlb, vma, address, end, &nr_accounted, details, 0);
	if (tlb)
		tlb_finish_mmu(tlb, address, end);
	return end;
}
```

```
 Page Global Directroy
  -> Page Upper Directory
   -> Page Middle Directory
    -> Page Table Entry
```

ディレクトリからページテーブルエントリまでを辿る

 * unmap_page_range
 * zap_pud_range
   * pud_none
 * zap_pmd_range
   * pmd_none
   * Huge Page が出て来る
 * zap_pte_range
   * pte_none
   * pte_dirty
   * pte_file
   * pte_t *pte
   * pte_present
     * ページブレームの有無?

## pthread と madvise

 * pthread_exit する際に madvise( ..., MADV_DONTNEED )を呼び出してスタックのページフレームを reclaim する
   * CentOS6.4  glibc-2.12
   * CentOS5.10 glibc-2.5 でも実装されていない
      * 下記に補足
   * CentOS4.8 glibc-2.3.4 だと実装されていない

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

### CentOS5.10 glibc-2.5 から

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
