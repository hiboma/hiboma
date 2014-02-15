# vm.overcommit_ratio, vm.overcommit_memory をソースで理解する

 * 2.6.32 vanilla kernel

## /proc/meminfo から辿る

CommitLimit と Committed_AS を seq_printf してる部分は以下のコード

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

 * CommitLimit = allowd は `(ページ数 - HUGEページ数) * vm.overcommmit_ratio /100 + swap のページ数` でよくある説明通り
   * HUGEページを引いているのが何でだろう

## Committed_AS, CommitLimit

### extern struct percpu_counter vm_committed_as
 
vm_acct_memory, vm_unacct_memory で加減される

```c
static inline void vm_acct_memory(long pages)
{
	percpu_counter_add(&vm_committed_as, pages);
}
```

```c
static inline void vm_unacct_memory(long pages)
{
    // マイナスにして減らしてるだけ
	vm_acct_memory(-pages);
}
```

percpu_counter って何ですかね

### struct percpu_counter

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

## vm_acct_memory <- security_vm_enough_memory

vm_acct_memory が呼び出されるのは以下のコード ( vm_unacct_memory はいろんな所で呼び出される)

```c
security_vm_enough_memory(len)

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

3行+α まとめ

 * OVERCOMMIT_ALWAYS はほんと何も見ない
 * OVERCOMMIT_GUESS は空きページ数を見て判別
 * OVERCOMMIT_NEVER は RAM と swap と overcommit_ratio の説明通り
   * 非root だと -3% 減る
   * 一つのプロセスで専有しないように, プロセスの仮想メモリサイズの -3% 減る
   * 最大で 6% のバッファが出来る
     * 実際は いろんなプロセスが Commit してるから 6% はありえないか

足らん場合は ENOMEM 返す => 続きあり

> 非root だと -3% 減る

https://github.com/hiboma/vagrant-inspect-vm.overcommit で比較

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

3% 分多く commit している

## security_vm_enough_***

security_vm_enough_*** -> cap_vm_enough_memory -> __vm_enough_memory の流れ

 * security_vm_enough_memory
 * security_vm_enough_memory_mm
   * カーネルスレッドを渡すと WARN_ON を出す。
 * security_vm_enough_memory_kern


 ## mmap

   * MAP_PRIVATE|MAP_ANONYMOUS は Committed_AS に加算される

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
 

 