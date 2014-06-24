# SIGBUS

## special mapping の範囲外にアクセス

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
 * アクセスしたアドレスのリージョンは MAP_FILE された vm_area_struct なので ~~struct vm_operations~~ struct vm_operations_struct のうんにゃらを呼ぶ
 * ファイルの中身をページイン? しようとするがサイズ0
 * => SIGBUS ?

### カーネルの実装を追う

適当に grep すると VM_FAULT_SIGBUS なるフラグが見つかる

```c
#define VM_FAULT_SIGBUS	0x0002
```

arch/x86/mm/fault.c では do_sigbus から force_sig_info_fault で SIGBUS を飛ばしている

```c
static void
do_sigbus(struct pt_regs *regs, unsigned long error_code, unsigned long address,
	  unsigned int fault)
{
	struct task_struct *tsk = current;
	struct mm_struct *mm = tsk->mm;
	int code = BUS_ADRERR;

	up_read(&mm->mmap_sem);

	/* Kernel mode? Handle exceptions or die: */
	if (!(error_code & PF_USER)) {
		no_context(regs, error_code, address);
		return;
	}

	/* User-space => ok to do another page fault: */
	if (is_prefetch(regs, error_code, address))
		return;

	tsk->thread.cr2		= address;
	tsk->thread.error_code	= error_code;
	tsk->thread.trap_no	= 14;

	force_sig_info_fault(SIGBUS, code, address, tsk, fault);
}
```

VM_FAULT_SIGBUS を返すコードは filemap_fault が怪しい

 * filemap_fault は vm_operations_struct の .fault メソッド
 * 呼び出される箇所は後で調べる

```c
const struct vm_operations_struct generic_file_vm_ops = {
	.fault		= filemap_fault,
	.page_mkwrite	= filemap_page_mkwrite,
};
```

filemap_fault

 * page fault したら file を読み込む
   * vma ページフォルト起こした struct vm_area_struct
   * vmfs fault の詳細が入った struct vm_fault

```c
/**
 * filemap_fault - read in file data for page fault handling
 * @vma:	vma in which the fault was taken
 * @vmf:	struct vm_fault containing details of the fault
 *
 * filemap_fault() is invoked via the vma operations vector for a
 * mapped memory region to read in file data during a page fault.
 *
 * The goto's are kind of ugly, but this streamlines the normal case of having
 * it in the page cache, and handles the special cases reasonably without
 * having a lot of duplicated code.
 */
int filemap_fault(struct vm_area_struct *vma, struct vm_fault *vmf)
{
	int error;
	struct file *file = vma->vm_file;
	struct address_space *mapping = file->f_mapping;
	struct file_ra_state *ra = &file->f_ra;
	struct inode *inode = mapping->host;
	pgoff_t offset = vmf->pgoff;
	struct page *page;
	pgoff_t size;
	int ret = 0;

    // 1. ページサイズにアラインした inode の size
    // 2. offset が size を超えている場合は存在しないファイルを指している
    // 3. SIGBUS を飛ばす
	size = (i_size_read(inode) + PAGE_CACHE_SIZE - 1) >> PAGE_CACHE_SHIFT;
	if (offset >= size)
		return VM_FAULT_SIGBUS;

	/*
	 * Do we have something in the page cache already?
	 */
	page = find_get_page(mapping, offset);
	if (likely(page)) {
		/*
		 * We found the page, so try async readahead before
		 * waiting for the lock.
		 */
         // 先読み
		do_async_mmap_readahead(vma, ra, file, page, offset);
	} else {
		/* No page in the page cache at all */
        // ページキャッシュのページが無い場合
        
         // 先読み
		do_sync_mmap_readahead(vma, ra, file, offset);

        // mmap での読み込みはメジャーフォルトとして扱われる。
		count_vm_event(PGMAJFAULT);
		ret = VM_FAULT_MAJOR;
retry_find:
		page = find_get_page(mapping, offset);
		if (!page)
			goto no_cached_page;
	}

	if (!lock_page_or_retry(page, vma->vm_mm, vmf->flags)) {
		page_cache_release(page);
		return ret | VM_FAULT_RETRY;
	}

	/* Did it get truncated? */
	if (unlikely(page->mapping != mapping)) {
		unlock_page(page);
		put_page(page);
		goto retry_find;
	}
	VM_BUG_ON(page->index != offset);

	/*
	 * We have a locked page in the page cache, now we need to check
	 * that it's up-to-date. If not, it is going to be due to an error.
	 */
	if (unlikely(!PageUptodate(page)))
		goto page_not_uptodate;

	/*
	 * Found the page and have a reference on it.
	 * We must recheck i_size under page lock.
	 */
     // 冒頭と同じサイズ確認
     // オフセットが size 超えてたら SIGBUS
	size = (i_size_read(inode) + PAGE_CACHE_SIZE - 1) >> PAGE_CACHE_SHIFT;
	if (unlikely(offset >= size)) {
		unlock_page(page);
		page_cache_release(page);
		return VM_FAULT_SIGBUS;
	}

	ra->prev_pos = (loff_t)offset << PAGE_CACHE_SHIFT;
	vmf->page = page;
	trace_mm_filemap_fault(vma->vm_mm, (unsigned long)vmf->virtual_address,
				vmf->flags&FAULT_FLAG_NONLINEAR);
	return ret | VM_FAULT_LOCKED;

no_cached_page:
	/*
	 * We're only likely to ever get here if MADV_RANDOM is in
	 * effect.
	 */
	error = page_cache_read(file, offset);

	/*
	 * The page we want has now been added to the page cache.
	 * In the unlikely event that someone removed it in the
	 * meantime, we'll just come back here and read it again.
	 */
	if (error >= 0)
		goto retry_find;

	/*
	 * An error return from page_cache_read can result if the
	 * system is low on memory, or a problem occurs while trying
	 * to schedule I/O.
	 */
     // page_cache_read がコケる
     // => page_cache_alloc_cold ENOMEM でコケるケース
     // => 物理メモリがほんと足らんケースで OOM
	if (error == -ENOMEM)
		return VM_FAULT_OOM;

    // ENOMEM でない場合???
    // 何が返ってくるのか分からない
	return VM_FAULT_SIGBUS;

page_not_uptodate:
	/*
	 * Umm, take care of errors if the page isn't up-to-date.
	 * Try to re-read it _once_. We do this synchronously,
	 * because there really aren't any performance issues here
	 * and we need to check for errors.
	 */
	ClearPageError(page);

    // readpage でファイルの中身を page に読み込み?
	error = mapping->a_ops->readpage(file, page);
	if (!error) {
		wait_on_page_locked(page);
		if (!PageUptodate(page))
			error = -EIO;
	}
	page_cache_release(page);

	if (!error || error == AOP_TRUNCATED_PAGE)
		goto retry_find;

	/* Things didn't work out. Return zero to tell the mm layer so. */
	shrink_readahead_size_eio(file, ra);
	return VM_FAULT_SIGBUS;
}
EXPORT_SYMBOL(filemap_fault);
```