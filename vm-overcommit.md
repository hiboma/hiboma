# vm.overcommit_ratio, vm.overcommit_memory をソースで理解する

## まとめ

 * private writable なリージョンが Commited_AS に加算される
   * security_vm_enough_memory が使われてるコードを追うと分かる
     * mmap, brk, stack などのシステムコールの過程で加算
   * accountable_mapping = pmap で `rw--` のリージョン
     * VM_SHARED な場合は除外
 * プロセス単位の Committed_AS のサイズは取れない?
   * 下記のワンライナーで近い値は出せる
 * root だと3%のおまけがつくのと, プロセスサイズの3%ひかれる特殊ケースを理解する

```sh
sudo pmap <pid> | grep 'rw--' | perl -anle '$s=$F[1];$s=~s/k//;$sum+=$s;END { warn $sum }'
```

__todo___

do_mmap_pgoff で max_map_count なるもので ENOMEM になるケースもあるぞよ

```
	/* Too many mappings? */
	if (mm->map_count > sysctl_max_map_count)
		return -ENOMEM;
```

`vm.max_map_count = 65530` こんな値がセットされている

## /proc/meminfo から辿る

CommitLimit と Committed_AS を seq_printf してる部分は以下のコード。ここから逆に辿る

```c
static int meminfo_proc_show(struct seq_file *m, void *v)
{
	committed = percpu_counter_read_positive(&vm_Committed_A);
	allowed = ((totalram_pages - hugetlb_total_pages())
		* sysctl_overcommit_ratio / 100) + total_swap_pages;

	seq_printf(m,
        "CommitLimit:    %8lu kB\n"
		"Committed_AS:   %8lu kB\n"
// ...
		K(allowed),
		K(committed),
```

 * CommitLimit = allowd は `(ページ数 - HUGE TLBページ数) * vm.overcommmit_ratio /100 + swap のページ数` でよくある説明通り
   * Huge TLBページを引いているのが何でだろう?
   * ふつーの環境だと 0 だから気にしなくてもいいけど

## Committed_AS, CommitLimit

### extern struct percpu_counter vm_committed_as
 
Committed_AS は vm_acct_memory, vm_unacct_memory で加減される

```c
static inline void vm_acct_memory(long pages)
{
	percpu_counter_add(&vm_committed_as, pages);
}

static inline void vm_unacct_memory(long pages)
{
    // マイナスにして減らしてるだけ
	vm_acct_memory(-pages);
}
```

percpu_counter って何ですかね?

### struct percpu_counter とは?

Linux Kernel Architecture P.364 に説明載ってる

 * 大規模な SMPシステムでは _カウンター_ の仕組みがボトルネックになりうる
   * 1個のCPUがロックを獲得 => 他のCPUが待たされる
   * カウンターが頻繁に利用されるほど競合しやすい
 * 正確な値を返さなくていいカウンターがある
   * だいたい合ってる数値を返しておけばおk
   * 正確な数値と概算の数値を保持する配列を用意
   * CPUごとに異なるインデックスの数値を加減する
     * percpu_counter_add, percpu_counter_dec
   * 概算の数値が閾値 ( ***FBC_BATCH*** ) を超えたら 正確な数値のカウンタを出すためにロックを取って更新する
     * percpu_couter_sum
     * このケースは頻繁に発生しないので競合が起こりにくい

## security_vm_enough_memory -> vm_acct_memory の呼び出し

 * vm_acct_memory が呼び出されるのは __vm_enough_memory 内 ( vm_unacct_memory はいろんな所で呼び出される)
 * __vm_enough_memory では vm.overcommmit_memory の値に応じて オーバーコミットの判定をする
   * OVERCOMMIT_ALWAYS は何も見ないで 0 返す
   * OVERCOMMIT_GUESS は空きページ数を見て判別
   * OVERCOMMIT_NEVER は RAM と swap と overcommit_ratio の説明通り
     * 非root だと -3% 減る
     * 一つのプロセスで専有しないように, プロセスの仮想メモリサイズの -3% 減る
     * 最大で 6% のバッファが出来る
       * 実際は いろんなプロセスが Commit してるから 6% はありえないか
   * Huge TLB
     * http://blog.livedoor.jp/rootan2007/archives/51711958.html
     * https://access.redhat.com/site/documentation/ja-JP/Red_Hat_Enterprise_Linux/6/html/Performance_Tuning_Guide/main-memory.html#s-memory-tlb
       * 設定してないなら 0

```c
/*
 * Check that a process has enough memory to allocate a new virtual
 * mapping. 0 means there is enough memory for the allocation to
 * succeed and -ENOMEM implies there is not.
 * 
 * 0 なら十分なメモリがある ( cap_vm_enough_memory から呼ばれるので 0 を返すインタフェース )
 * ENOMEM なら駄目ポ
 * 
 * We currently support three overcommit policies, which are set via the
 * vm.overcommit_memory sysctl.  See Documentation/vm/overcommit-accounting
 *
 * Strict overcommit modes added 2002 Feb 26 by Alan Cox.
 * Additional code 2002 Jul 20 by Robert Love.
 *
 * cap_sys_admin is 1 if the process has admin privileges, 0 otherwise.
 * root 権限持ってるか否かで数値の扱いが違う
 *
 * Note this is a helper function intended to be used by LSMs which
 * wish to use this logic.
 */
int __vm_enough_memory(struct mm_struct *mm, long pages, int cap_sys_admin)
{
	unsigned long free, allowed;

	vm_acct_memory(pages);

	/*
	 * Sometimes we want to use more memory than we have
	 */
    // vm.overcommit_memory=1 の時。何も判定しない !!!!
	if (sysctl_overcommit_memory == OVERCOMMIT_ALWAYS)
		return 0;

    // vm.overcommit_memory=0 の時
    // 空きページ数を元に判定
	if (sysctl_overcommit_memory == OVERCOMMIT_GUESS) {
		unsigned long n;

        // ページキャッシュの総数かな?
		free = global_page_state(NR_FILE_PAGES);
        // swap のページ数
		free += nr_swap_pages;

		/*
		 * Any slabs which are created with the
		 * SLAB_RECLAIM_ACCOUNT flag claim to have contents
		 * which are reclaimable, under pressure.  The dentry
		 * cache and most inode caches should fall into this
		 */
         // memory pressure 下では SLAB_RECLAIM_ACCOUNT フラグのたったslabキャッシュを再利用可
         // dentry キャッシュと indoe キャッシュが含まれる
		free += global_page_state(NR_SLAB_RECLAIMABLE);

		/*
		 * Leave the last 3% for root
		 */
        // root 用に 3% 残しておく => root だと CommitLimit ギリギリまで使いうる
		if (!cap_sys_admin)
			free -= free / 32;

		if (free > pages)
			return 0;

		/*
		 * nr_free_pages() is very expensive on large systems,
		 * only call if we're about to fail.
		 */
        // コストが高いとあるが何で?
		n = nr_free_pages();

		/*
		 * Leave reserved pages. The pages are not for anonymous pages.
		 */
		if (n <= totalreserve_pages)
			goto error;
		else
			n -= totalreserve_pages;

		/*
		 * Leave the last 3% for root
		 */
        // やっぱり root 用に 3% 予約
		if (!cap_sys_admin)
			n -= n / 32;
		free += n;

		if (free > pages)
			return 0;

		goto error;
	}

    // vm.overcommit_memory=2 の時 OVERCOMMIT_NEVER
    // HugeTLB https://access.redhat.com/site/documentation/ja-JP/Red_Hat_Enterprise_Linux/6/html/Performance_Tuning_Guide/main-memory.html#s-memory-tlb
    // ttp://blog.livedoor.jp/rootan2007/archives/51711958.html
    // ふつーのサーバーだと hugetlb_total_pages() のサイズは 0 かなー
	allowed = (totalram_pages - hugetlb_total_pages())
	       	* sysctl_overcommit_ratio / 100;
	/*
	 * Leave the last 3% for root
	 */
	if (!cap_sys_admin)
		allowed -= allowed / 32;
	allowed += total_swap_pages;

	/* Don't let a single process grow too big:
	   leave 3% of the size of this process for other processes */
    // mm の有無でカーネルスレッドで無い場合 
	if (mm)
        // 一つのプロセスで使い切らないように 3% 引いておく
		allowed -= mm->total_vm / 32;

    // allowed (CommitLimit) より小さければ ok 
	if (percpu_counter_read_positive(&vm_committed_as) < allowed)
		return 0;
error:
    // カウンタから減算する
	vm_unacct_memory(pages);

	return -ENOMEM;
}
```

#### 非root だと Commitできる量が -3% 減る の検証

https://github.com/hiboma/vagrant-inspect-vm.overcommit で比較した

__vagrant で実行__

```
CommitLimit:      597544 kB
Committed_AS:     564256 kB  # 残り 0.56 %
```

__root で実行__

```
CommitLimit:      597544 kB
Committed_AS:     582868 kB  # 残り 0.24 %
```

 * 3% 分多く commit している
   * rootが頑張っちゃうとシェルの操作まで巻き添えにするので大分危険
   * rootで富豪なデーモン動かしてはいけない

## security_vm_enough_*** API

 * __vm_enough_memory を呼び出す API群 をまとめる
 * `security_vm_enough_*** -> cap_vm_enough_memory -> __vm_enough_memory` の流れになる

### security_vm_enough_memory

 * カーネルスレッドを渡すと WARN_ON を出す以外は他と大体同じ
 * [mmap_region](http://lxr.free-electrons.com/source/mm/mmap.c?v=2.6.32#L1108)
    * accountable_mapping が重要
 * [do_brk](http://lxr.free-electrons.com/source/mm/mmap.c?v=2.6.32#L1990)
    * brk(2)
 * [vma_to_resize](http://lxr.free-electrons.com/source/mm/mremap.c?v=2.6.32#L262)
 * [swapoff](http://lxr.free-electrons.com/source/mm/swapfile.c?v=2.6.32#L1512)
    * swap したページをページフレームに読み込めるかどうか?
 * [mprotect_fixup](http://lxr.free-electrons.com/source/mm/mprotect.c?v=2.6.32#L136)
 * [dup_mmap](http://lxr.free-electrons.com/source/kernel/fork.c?v=2.6.32#L279)
   * fork の途中

### security_vm_enough_memory_mm

 * task_struct が渡ってこない無い関数パスでも呼び出せるようインタフェースを変えてるだけなのかな?
   * [acct_stack_growth](http://lxr.free-electrons.com/source/mm/mmap.c?v=2.6.32#L1553) スタックを拡張する際に呼び出し
   * [insert_vm_struct](http://lxr.free-electrons.com/source/mm/mmap.c?v=2.6.32#L2167)

### security_vm_enough_memory_kern

 * shmem.c ([shmem_acct_size](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L185), [shmem_acct_block](http://lxr.free-electrons.com/source/mm/shmem.c?v=2.6.32#L203)) でのみ使われている
     * ファイルシステムの実装として使われている。システムコールとは違うことを _kern で意味したい?

## Committed_AS に加算されるかどうかはどこで決まるのか? mmap で検証

 * accountable_mapping() の実装を追うとよい
   * `We account for memory if it's a private writeable__ mapping`
   * HugePage と VM_NORESERVE は除外される

```c
/*
 * We account for memory if it's a private writeable mapping,
 * not hugepages and VM_NORESERVE wasn't set.
 */
static inline int accountable_mapping(struct file *file, unsigned int vm_flags)
{
	/*
	 * hugetlb has its own accounting separate from the core VM
	 * VM_HUGETLB may not be set yet so we cannot check for that flag.
	 */
	if (file && is_file_hugepages(file))
		return 0;

	return (vm_flags & (VM_NORESERVE | VM_SHARED | VM_WRITE)) == VM_WRITE;
}
```

VM_WRITE フラグがたってると加算されるぽい

#### 検証

 * PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS は Committed_AS に加算される
   * private writable

```
[vagrant@vagrant-centos65 ~]$ pmap 494
494:   ./__mmap
0000000000400000      4K r-x--  /home/vagrant/__mmap
0000000000600000      4K rw---  /home/vagrant/__mmap
00007f7ee974f000 491520K rw---    [ anon ]              # private writable 加算される
00007f7f0774f000   1580K r-x--  /lib64/libc-2.12.so
00007f7f078da000   2044K -----  /lib64/libc-2.12.so
00007f7f07ad9000     16K r----  /lib64/libc-2.12.so
00007f7f07add000      4K rw---  /lib64/libc-2.12.so
00007f7f07ade000     20K rw---    [ anon ]
00007f7f07ae3000    128K r-x--  /lib64/ld-2.12.so
00007f7f07cf9000     12K rw---    [ anon ]
00007f7f07d01000      4K rw---    [ anon ]
00007f7f07d02000      4K r----  /lib64/ld-2.12.so
00007f7f07d03000      4K rw---  /lib64/ld-2.12.so
00007f7f07d04000      4K rw---    [ anon ]
00007fff5f9b2000     84K rw---    [ stack ]
00007fff5f9ff000      4K r-x--    [ anon ]
ffffffffff600000      4K r-x--    [ anon ]
 total           495440K
```

 * PROT_READ, MAP_PRIVATE|MAP_ANONYMOUS だと加算されない
    * 無名リージョンを読み出しだけだと意味無いな

```
[vagrant@vagrant-centos65 ~]$ pmap 440
440:   ./__mmap
0000000000400000      4K r-x--  /home/vagrant/__mmap
0000000000600000      4K rw---  /home/vagrant/__mmap
00007f1d1d5ff000 4618240K r----    [ anon ]             # not private writable, 加算されない
00007f1e373ff000   1580K r-x--  /lib64/libc-2.12.so
00007f1e3758a000   2044K -----  /lib64/libc-2.12.so
00007f1e37789000     16K r----  /lib64/libc-2.12.so
00007f1e3778d000      4K rw---  /lib64/libc-2.12.so
00007f1e3778e000     20K rw---    [ anon ]
00007f1e37793000    128K r-x--  /lib64/ld-2.12.so
00007f1e379a9000     12K rw---    [ anon ]
00007f1e379b1000      4K rw---    [ anon ]
00007f1e379b2000      4K r----  /lib64/ld-2.12.so
00007f1e379b3000      4K rw---  /lib64/ld-2.12.so
00007f1e379b4000      4K rw---    [ anon ]
00007fff1a8fd000     84K rw---    [ stack ]
00007fff1a9ff000      4K r-x--    [ anon ]
ffffffffff600000      4K r-x--    [ anon ]
 total          4622160K
```

実証用のコード

```c
 #if 0
#!/bin/bash
o=`basename $0`
o="__${o%.*}"
CFLAGS="-O2 -g -std=gnu99 -W -Wall -fPIE"
gcc ${CFLAGS} ${LDFLAGS} -o $o $0 && ./$o $*; exit
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <err.h>
#include <time.h>
#include <sys/time.h>

static int MILLI_SEC = 1000000;

int main(int argc, char *argv[]) {

	struct timespec spec = {0, 100 * MILLI_SEC};
	size_t length = 1 * 1024 * 1024;

	if (argc == 2)
		length = atoi(argv[1]);
	
	for (;;) {
		void *p = mmap(NULL, length, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
		if (p == MAP_FAILED) {
			perror("mmap failed");
			exit(EXIT_FAILURE);
		}
		nanosleep(&spec, NULL);
	}
	
	exit(0);
}
```

## VM_NORESERVE が除外されるのはどういう用途?

 * mmap(2) に MAP_NORESERVE を立てた場合
   * OVERCOMMIT_NEVER では無視される (全て厳密にカウントされる)
 *　

```
unsigned long mmap_region(struct file *file, unsigned long addr,
			  unsigned long len, unsigned long flags,
			  unsigned int vm_flags, unsigned long pgoff)
{

 ///...

	/*
	 * Set 'VM_NORESERVE' if we should not account for the
	 * memory use of this mapping.
	 */
	if ((flags & MAP_NORESERVE)) {
		/* We honor MAP_NORESERVE if allowed to overcommit */
		if (sysctl_overcommit_memory != OVERCOMMIT_NEVER)
			vm_flags |= VM_NORESERVE;

        // file は struct *file 
        // ファイルを mmap した場合は VM_NORESERVE になる
		/* hugetlb applies strict overcommit unless MAP_NORESERVE */
		if (file && is_file_hugepages(file))
			vm_flags |= VM_NORESERVE;
	}
```

