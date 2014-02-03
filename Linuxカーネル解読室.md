# 序章

## 0.1 Linuxカーネルとは

 * __イベント駆動型__
   * システムコール
   * 割り込み

## 0.1.1 UNIX の互換実装

 * __モノリシックカーネル__
 * __マイクロカーネル__
   * Mac OSX もだよ
     * XNU Kernel ___XNU's Not UNIX___
       * Mach microkernel
       * The BSD Layer (FreeBSD由来)
       * libKern
       * I/O Kit
 * マイクロカーネルの実例は???

#### System V

![71k140k5bfl _ss500_ gif](https://f.cloud.github.com/assets/172456/1985620/2e21f650-8441-11e3-9865-62d7b7871f15.jpeg)

#### Solaris Internals

![51jyl26gg-l](https://f.cloud.github.com/assets/172456/1985642/8275fcd8-8441-11e3-8eea-1f6a901dc27b.jpg)

#### 4.3BSD

![41okjaranfl _sl500_aa300_](https://f.cloud.github.com/assets/172456/1985643/84f1a764-8441-11e3-8a4a-521bbbf57f22.jpg)

## 0.2 Linuxカーネルのソースコード

 * バニラカーネルのダウンロード
   * https://www.kernel.org/
 * CentOS の kernel SRPM
   * http://vault.centos.org/ から探す
   * http://vault.centos.org/6.5/os/Source/SPackages/kernel-2.6.32-431.el6.src.rpm
 * CPUアーキテクチャの整理
   * ぎょーむ的には i386, x86_64 を中心に見る事になるのを確認

## 0.3 Linuカーネル機能の概要

## 0.4 カーネルプリミティブ

 * ___プリミティブ___ とは?
   * 基本機能?
 * ___非同期___
 
#### 0.4.1 プロセススケジューラ

__マルチタクス環境__

 * ___並列に実行されます___ と書いてるけど、マルチコア/マルチCPUが前提になっていて、並行の話が無いような
   * ___parallel___, ___concurrent___ を整理しよう
   * https://twitter.com/tnmt/status/318211278810275840
 * プロセスが___実行___される とは?
 * ___公平性、応答性、スループット___
   * どういうアルゴリズムにしたら理想なんだろうかを考えてみる (難しいけど)

#### 0.4.2 割り込み処理と遅延処理

 * ___割り込み___
   * ___Interrupt___
   * メタファとして、仕事中に急に呼びかけられて中断させられるという説明
   * コンテキストが変わる
   * http://www.cqpub.co.jp/interface/sample/200606/I0606147.pdf の図が分かりやすそう
 * ___ハードウェアからの事象___ とは? 何か例が無いと分かりにくそう
   * Ethernetカードにパケットが届いた
     * => パケットをコピーしないといけない
     * => 次のパケットに備えないといけない
     * 転送が遅い、パケットロス?
   * HDDの読み取りが終わった
     * => バッファにコピーしないといけない
     * => 次のHDDのコマンドに備えないといけない
     * I/O が遅い、重たい
   * マウス、キーボード
     * => スクロール、クリック、打鍵に応じて描画やキーボード入力
     * => 反応が遅い、イライラする
   * タイマ割り込み
     * インターバルの時間内に割り込み処理を完了しないと、次回の割り込みを取りこぼす
 * ___ソフト割り込み___
   * _割り込み処理を遅延させる仕組み_
 * ___割り込みレベル___
   * 低い優先度の割り込みをマスクする
   * 優先度の高い/低いの説明
     * 4.3BSD クロック割り込みの優先度は非常に高い
     * 他のほとんどの処理はブロックされる
     * ネットワークパケットのロス、ディスクヘッドのセクタ転送? を取りこぼしたりする可能性。"重要"

---

 * 割り込みを確認する

```
[vagrant@vagrant-centos65 ~]$ cat /proc/interrupts
           CPU0       CPU1
  0:        191          0   IO-APIC-edge      timer
  1:          7          0   IO-APIC-edge      i8042
  8:          0          0   IO-APIC-edge      rtc0
  9:          0          0   IO-APIC-fasteoi   acpi
 12:        108          0   IO-APIC-edge      i8042
 19:        690          0   IO-APIC-fasteoi   eth0
 20:        100          0   IO-APIC-fasteoi   vboxguest
 21:       1930          0   IO-APIC-fasteoi   ahci
NMI:          0          0   Non-maskable interrupts
LOC:      16493      43382   Local timer interrupts
SPU:          0          0   Spurious interrupts
PMI:          0          0   Performance monitoring interrupts
IWI:          0          0   IRQ work interrupts
RES:       9384       2599   Rescheduling interrupts
CAL:         85         62   Function call interrupts
TLB:        274        405   TLB shootdowns
TRM:          0          0   Thermal event interrupts
THR:          0          0   Threshold APIC interrupts
MCE:          0          0   Machine check exceptions
MCP:          1          1   Machine check polls
ERR:          0
MIS:          0
```

----

Linuxカーネル本より。Intelでの呼び方

 * ___同期割り込み___
   * ___例外___ 
   * CPUの命令を実行中にCPUの制御回路が生成
   * 命令の実行終了時のみ制御回路が割り込みを発生させる => 同期的
 * ___非同期割り込み___
   * ___割り込み___
   * インターバルタイマ、I/Oデバイス
   * CPU以外のハードウェアデバイスが任意の時点で生成

#### 0.4.3 時計

 * ___ハードウェアから一定周期で発生する割り込み___
 * ___時限処理___
   * _ネットワークプロトコルスタック、デバイスドライバが多用しています_
   * どんな風に?
     * TCP/IPのパケット再送, タイムアウトの実装
     * デバイスへのポーリング

#### 0.4.4 システムコール

P.96 の図を見た方がよい

 * ___Linuxカーネルコードの実行を開始します___
 * ___システムコールがプロセス間通信として実現されているOSも存在します___
   * Mach http://www.osrg.net/rtmach/publications/transtech-mach-3.pdf の例
 * ___プロセスのコンテキスト___
   * プロセスのコンテキストではないコンテキストとは?
   * 割り込みコンテキスト
 * ___保護機能___
   * [プロテクトモード](http://ja.wikipedia.org/wiki/プロテクトモード) <=> リアルモード
 * メモリ保護機能が無くて、Linuxカーネルのメモリを書き変えてしまったらどうなるか?
   * データの破壊, 整合性が狂う, ハードウェアの制御が出来ない, クラッシュ ... etc
 * ___CPUの実行レベル___

#### 0.4.5 同期と排他

 * synchronization, mutual execution
 * ___同一資源___
   * 何かサンプルは?
 * ___セマフォ___
 * ___スピンロック___
 * ___RCU___
 * ___シーケンスカウンタロック___

### 0.5 プロセス管理

 * ___プログラムの実行状態___
 * ___プロセス空間情報___
   * メモリのレイアウト P.25
 * ___制御端末___
   * telnetやSSHでのログイン => 仮想端末
   * コンソールからのログイン

#### 0.5.1 プロセス

 * ___ダイナミックリンクライブラリ___
   * ダイナミックリンカ (ld), 共有オブジェクトファイル (*.so)

#### 0.5.2 シグナル

 * ___非同期事象___
 * `man signal` で signal の一覧を見てみる
 * 似ているというか、ハードウェアからの割り込みモデルをソフトウェアで真似たのがシグナルのモデル
   * と 4.3BSD本に書いてある

#### 0.5.3

 * ___一種のプロセス___ とはどういうことか?
   * struct task_struct
 * ___POSIXスレッドインターフェイス___
   * pthread, 芋虫
   * 実装ではなく仕様/インターフェイス

### 0.6 メモリ管理

 * 実メモリ管理
   * PTEを解さないメモリ
 * ___仮想記憶___, ___仮想空間___
   * ps aux の VSZ

#### 0.6.1 実メモリ管理

 * ___ページ___
 ```sh
$ getconf PAGESIZE
```
 * CPUのアーキテクチャ依存
 * ___Buddyシステム___
   * ページの結合、断片化
 * ___Slabアロケータ__
   * PAGESIZE以下のメモリ
   * kmem_cache_alloc ( dentry cache, inode cahce ...)
 * テキストセグメントの ___書き込み保護___
   * 書き込もうとしたらどうなるか => SIGSEGV

#### 0.6.2 仮想記憶

 * __アドレス空間__
   * mm_struct, vm_area_struct

#### 0.6.2 デマンドページング

 * ___CoW___

#### ページアウトとスワップ

 * ___ページアウト___
   * 二次記憶に追い出す = スワップ
   * kswapd

### 0.7 ファイルシステム

 * ___バイトストリーム___
   * バイトストリームでないファイルとは?
 * ___デバイスやLinuxカーネル内のデータ構造もファイルとして扱える___
   * /dev, /sys, /proc 以下のこと?

#### 0.7.1 ファイル記述子

#### 0.7.2 キャッシュ機構

 * ___ページキャッシュ___
 * ___順次アクセス___
   * シーケンシャルリード
   * struct backing_dev_info
 * ___遅延させて2次記憶に書き出す___
   * dirty なページの書き出し => pdflush
   * 2.6.32 だと pdflush は bdiスレッドに置き換わった [refs](http://www.oreilly.co.jp/community/blog/2010/08/buffer-cache-and-aio-part1.html)
   * generic_file_aio_write
 * ___inodeキャッシュ___, __dentryキャッシュ___
   * slabアロケータ
     * kmem_cache_alloc
   * dget, dput, iget, iput

### 0.7.3 仮想ファイルシステム

 * VFS ( ___Virtual FileSystem___ or ___Virtual Filesystem Switch___ )
   * ActiveRecord (データストアを意識しない抽象レイヤ) を例に出す
   * 統一的なインタフェースを提供、下位実装を隠蔽
     * ___common file model___
   * 関数ポインタを駆使してオブジェクト指向風に操作

#### 0.7.3.1 ローカルファイルシステム

#### 0.7.3.2 ネットワークファイルシステム

#### 0.7.3.3 擬似ファイルシステム ( psuedo filesystem )

 * procfs
 * sysfs
 * ___ホットプラグ___
   * CPU, デバイス

#### 0.7.4 EXT2

 * ___ブロックグループ___
 * ___ビットマップ___
 * ___ブロック確保機能___

#### 0.7.5 EXT3

 * ___ジャーナル___

#### 0.7.6 ブロック型デバイス

 * データ転送の単位がブロックサイズ
 * キャラクタデバイスが無い?
 * 下記コマンドでブロック型デバイス出せる
 

```
$ ls -hal /dev/ | grep ^b
brw-rw----   1 root    disk      7,   0 Feb  2 12:38 loop0
brw-rw----   1 root    disk      7,   1 Feb  2 12:38 loop1
brw-rw----   1 root    disk      7,   2 Feb  2 12:38 loop2
brw-rw----   1 root    disk      7,   3 Feb  2 12:38 loop3
...
```

 * ___バッファ___ から 複数ページの集まり???
 * ___エレベータ___ (I/Oスケジューラ???)
   * Noop
   * CFQ
   * Deadline

## 0.8 ネットワーク

 * BSD由来 (4.3BSDでは既に実装済み)

### 0.8.1 ソケット

 * ___ソケットバッファ___
   * struct sk_buff, struct sk_buff_head

#### 0.8.2 TCP/IPプロトコルスタック

 * System V ___STREAMS___

### 0.9 プロセス間通信

 * IPC
   * パイプ
   * 名前付きパイプ
   * ___プリエンプションの発生回数を抑制するような実装___
 * ___System V IPC___
   * shared memory
     * ___ファイルシステムとしてアクセス可能___ => tmpfs
   * semahpre
   * message
 * futex
   * 同一ページをプロセス間でマップ、ロック変数を共有
   * 競合が発生しない限りシステムコールを介さずに排他

## 第2章

TODO
 * レジスタの種類を整理
   * 汎用レジスタ
     * eax, ebx, ecx, edx, ... eip, esp ?
   * 特権レジスタ

### context_switch

schedule の中で呼ばれるよ

 * mm_struct
   * メモリディスクリプタ
   * vm_area_struct, red-black木, セグメントのアドレス, ...
 * カーネルスレッドでは current->mm が NULL

```c
/*
 * context_switch - switch to the new MM and the new
 * thread's register state.
 */
static inline
task_t * context_switch(runqueue_t *rq, task_t *prev, task_t *next)
{
	struct mm_struct *mm = next->mm;
	struct mm_struct *oldmm = prev->active_mm;

    // http://wiki.bit-hive.com/north/pg/likely%A4%C8unlikely
    // if (!mm) として読んで OK
    // つまりは mm == NULL -> 実行中のタスクがカーネルスレッドの場合を指す
	if (unlikely(!mm)) {
        // カーネルスレッドでは mm_struct を切り替える必要が無い
        // というか、 mm_struct を共有する
		next->active_mm = oldmm;
		atomic_inc(&oldmm->mm_count);
        // TLBフラッシュの遅延?
		enter_lazy_tlb(oldmm, next);
	} else
        // カーネルスレッド以外 = 普通のプロセスの場合
		switch_mm(oldmm, mm, next);

	if (unlikely(!prev->mm)) {
		prev->active_mm = NULL;
		WARN_ON(rq->prev_mm);
		rq->prev_mm = oldmm;
	}

	/* Here we just switch the register state and the stack. */
	switch_to(prev, next, prev);

	return prev;
}
```

```c
struct task_struct {
	volatile long state;	/* -1 unrunnable, 0 runnable, >0 stopped */
	struct thread_info *thread_info;
	atomic_t usage;
	unsigned long flags;	/* per process flags, defined below */
	unsigned long ptrace;

	int lock_depth;		/* BKL lock depth */

#if defined(CONFIG_SMP) && defined(__ARCH_WANT_UNLOCKED_CTXSW)
	int oncpu;
#endif
	int prio, static_prio;
	struct list_head run_list;
	prio_array_t *array;

	unsigned short ioprio;

	unsigned long sleep_avg;
	unsigned long long timestamp, last_ran;
	unsigned long long sched_time; /* sched_clock time spent running */
	int activated;

	unsigned long policy;
	cpumask_t cpus_allowed;
	unsigned int time_slice, first_time_slice;

#ifdef CONFIG_SCHEDSTATS
	struct sched_info sched_info;
#endif

	struct list_head tasks;
	/*
	 * ptrace_list/ptrace_children forms the list of my children
	 * that were stolen by a ptracer.
	 */
	struct list_head ptrace_children;
	struct list_head ptrace_list;

	struct mm_struct *mm, *active_mm;

/* task state */
	struct linux_binfmt *binfmt;
	long exit_state;
	int exit_code, exit_signal;
	int pdeath_signal;  /*  The signal sent when the parent dies  */
	/* ??? */
	unsigned long personality;
	unsigned did_exec:1;
	pid_t pid;
	pid_t tgid;
	/* 
	 * pointers to (original) parent process, youngest child, younger sibling,
	 * older sibling, respectively.  (p->father can be replaced with 
	 * p->parent->pid)
	 */
	struct task_struct *real_parent; /* real parent process (when being debugged) */
	struct task_struct *parent;	/* parent process */
	/*
	 * children/sibling forms the list of my children plus the
	 * tasks I'm ptracing.
	 */
	struct list_head children;	/* list of my children */
	struct list_head sibling;	/* linkage in my parent's children list */
	struct task_struct *group_leader;	/* threadgroup leader */

	/* PID/PID hash table linkage. */
	struct pid pids[PIDTYPE_MAX];

	struct completion *vfork_done;		/* for vfork() */
	int __user *set_child_tid;		/* CLONE_CHILD_SETTID */
	int __user *clear_child_tid;		/* CLONE_CHILD_CLEARTID */

	unsigned long rt_priority;
	cputime_t utime, stime;
	unsigned long nvcsw, nivcsw; /* context switch counts */
	struct timespec start_time;
/* mm fault and swap info: this can arguably be seen as either mm-specific or thread-specific */
	unsigned long min_flt, maj_flt;

  	cputime_t it_prof_expires, it_virt_expires;
	unsigned long long it_sched_expires;
	struct list_head cpu_timers[3];

/* process credentials */
	uid_t uid,euid,suid,fsuid;
	gid_t gid,egid,sgid,fsgid;
	struct group_info *group_info;
	kernel_cap_t   cap_effective, cap_inheritable, cap_permitted;
	unsigned keep_capabilities:1;
	struct user_struct *user;
#ifdef CONFIG_KEYS
	struct key *thread_keyring;	/* keyring private to this thread */
	unsigned char jit_keyring;	/* default keyring to attach requested keys to */
#endif
	int oomkilladj; /* OOM kill score adjustment (bit shift). */
	char comm[TASK_COMM_LEN]; /* executable name excluding path
				     - access with [gs]et_task_comm (which lock
				       it with task_lock())
				     - initialized normally by flush_old_exec */
/* file system info */
	int link_count, total_link_count;
/* ipc stuff */
	struct sysv_sem sysvsem;
/* CPU-specific state of this task */
	struct thread_struct thread;
/* filesystem information */
	struct fs_struct *fs;
/* open file information */
	struct files_struct *files;
/* namespace */
	struct namespace *namespace;
/* signal handlers */
	struct signal_struct *signal;
	struct sighand_struct *sighand;

	sigset_t blocked, real_blocked;
	struct sigpending pending;

	unsigned long sas_ss_sp;
	size_t sas_ss_size;
	int (*notifier)(void *priv);
	void *notifier_data;
	sigset_t *notifier_mask;
	
	void *security;
	struct audit_context *audit_context;
	seccomp_t seccomp;

/* Thread group tracking */
   	u32 parent_exec_id;
   	u32 self_exec_id;
/* Protection of (de-)allocation: mm, files, fs, tty, keyrings */
	spinlock_t alloc_lock;
/* Protection of proc_dentry: nesting proc_lock, dcache_lock, write_lock_irq(&tasklist_lock); */
	spinlock_t proc_lock;

/* journalling filesystem info */
	void *journal_info;

/* VM state */
	struct reclaim_state *reclaim_state;

	struct dentry *proc_dentry;
	struct backing_dev_info *backing_dev_info;

	struct io_context *io_context;

	unsigned long ptrace_message;
	siginfo_t *last_siginfo; /* For ptrace use.  */
/*
 * current io wait handle: wait queue entry to use for io waits
 * If this thread is processing aio, this points at the waitqueue
 * inside the currently handled kiocb. It may be NULL (i.e. default
 * to a stack based synchronous wait) if its doing sync IO.
 */
	wait_queue_t *io_wait;
/* i/o counters(bytes read/written, #syscalls */
	u64 rchar, wchar, syscr, syscw;
#if defined(CONFIG_BSD_PROCESS_ACCT)
	u64 acct_rss_mem1;	/* accumulated rss usage */
	u64 acct_vm_mem1;	/* accumulated virtual memory usage */
	clock_t acct_stimexpd;	/* clock_t-converted stime since last update */
#endif
#ifdef CONFIG_NUMA
  	struct mempolicy *mempolicy;
	short il_next;
#endif
#ifdef CONFIG_CPUSETS
	struct cpuset *cpuset;
	nodemask_t mems_allowed;
	int cpuset_mems_generation;
#endif
	atomic_t fs_excl;	/* holding fs exclusive resources */
};
```

## 第4章 時計

### 4.4 各種タイマー関連ハードウェア

 * ___APIC___
   * http://ja.wikipedia.org/wiki/APIC
   * Local APIC
     * 各CPUコアに内蔵
   * I/O APIC
     * Local APIC に割り込みを転送(リダイレクション)。SMPの場合はどれか一つのコアを選択
     * VirtualBox に `Enable I/O APIC` の項目がある
       * I/O APIC を無効にすると /var/log/messages に SMP disabled が出て、仮想CPUを複数あててもゲストOSでは1個のみになる

![2014-01-28 13 24 43](https://f.cloud.github.com/assets/172456/2016294/310db0ac-87d4-11e3-8cf7-150dd0194910.png)

 * http://serverfault.com/questions/74672/why-should-i-enable-io-apic-in-virtualbox

> Note: Enabling the I/O APIC is required for 64-bit guest operating systems, especially Windows Vista;
> it is also required if you want to use more than one virtual CPU in a virtual machine.

> However, software support for I/O APICs has been unreliable with some operating systems other than Windows.
> Also, the use of an I/O APIC slightly increases the overhead of virtualization and therefore slows down the guest OS a little.
     

   
