
## /proc/meminfo

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
   * HUGEページを引いているのが違うかな

## Committed_AS

`struct percpu_counter`

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
     * 頻繁に発生しないので競合が怒りにくい

`extern struct percpu_counter vm_committed_as;`
 
vm_acct_memory, vm_unacct_memory で加減される

```
static inline void vm_acct_memory(long pages)
{
	percpu_counter_add(&vm_committed_as, pages);
}
```

```
static inline void vm_unacct_memory(long pages)
{
    // マイナスにして減らしてるだけ
	vm_acct_memory(-pages);
}
```

## vm_acct_memory <- security_vm_enough_memory

```c
security_vm_enough_memory(len)

/*
 * Check that a process has enough memory to allocate a new virtual
 * mapping. 0 means there is enough memory for the allocation to
 * succeed and -ENOMEM implies there is not.
 *
 * We currently support three overcommit policies, which are set via the
 * vm.overcommit_memory sysctl.  See Documentation/vm/overcommit-accounting
 *
 * Strict overcommit modes added 2002 Feb 26 by Alan Cox.
 * Additional code 2002 Jul 20 by Robert Love.
 *
 * cap_sys_admin is 1 if the process has admin privileges, 0 otherwise.
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
