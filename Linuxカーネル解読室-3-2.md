# 3.2 workqueue

/proc/\<pid\>/stack がこんなんなってるカーネルスレッド

```
[<ffffffff81094dac>] worker_thread+0x1fc/0x2a0
[<ffffffff8109aef6>] kthread+0x96/0xa0
[<ffffffff8100c20a>] child_rip+0xa/0x20
[<ffffffffffffffff>] 0xffffffffffffffff
```

みたとこ下記のスレッドが相当する

```
root        23  0.0  0.0      0     0 ?        S    13:37   0:00 [cgroup]
root        25  0.0  0.0      0     0 ?        S    13:37   0:00 [netns]
root        30  0.0  0.0      0     0 ?        S    13:37   0:00 [kintegrityd/0]
root        31  0.0  0.0      0     0 ?        S    13:37   0:00 [kintegrityd/1]
root        32  0.0  0.0      0     0 ?        S    13:37   0:00 [kintegrityd/2]
root        33  0.0  0.0      0     0 ?        S    13:37   0:00 [kintegrityd/3]
root        34  0.4  0.0      0     0 ?        S    13:37   0:11 [kblockd/0]
root        35  0.0  0.0      0     0 ?        S    13:37   0:01 [kblockd/1]
root        36  0.0  0.0      0     0 ?        S    13:37   0:01 [kblockd/2]
root        37  0.0  0.0      0     0 ?        S    13:37   0:01 [kblockd/3]
root        38  0.0  0.0      0     0 ?        S    13:37   0:00 [kacpid]
root        39  0.0  0.0      0     0 ?        S    13:37   0:00 [kacpi_notify]
root        40  0.0  0.0      0     0 ?        S    13:37   0:00 [kacpi_hotplug]
root        41  0.0  0.0      0     0 ?        S    13:37   0:00 [ata_aux]
root        42  0.0  0.0      0     0 ?        S    13:37   0:00 [ata_sff/0]
root        43  0.0  0.0      0     0 ?        S    13:37   0:00 [ata_sff/1]
root        44  0.0  0.0      0     0 ?        S    13:37   0:00 [ata_sff/2]
root        45  0.0  0.0      0     0 ?        S    13:37   0:00 [ata_sff/3]
root        46  0.0  0.0      0     0 ?        S    13:37   0:00 [ksuspend_usbd]
root        49  0.0  0.0      0     0 ?        S    13:37   0:00 [md/0]
root        50  0.0  0.0      0     0 ?        S    13:37   0:00 [md/1]
root        51  0.0  0.0      0     0 ?        S    13:37   0:00 [md/2]
root        57  0.0  0.0      0     0 ?        S    13:37   0:00 [linkwatch]
root        66  0.0  0.0      0     0 ?        S    13:37   0:00 [crypto/0]
root        67  0.0  0.0      0     0 ?        S    13:37   0:00 [crypto/1]
root        68  0.0  0.0      0     0 ?        S    13:37   0:00 [crypto/2]
root        69  0.0  0.0      0     0 ?        S    13:37   0:00 [crypto/3]
root        74  0.0  0.0      0     0 ?        S    13:37   0:00 [kthrotld/0]
root        75  0.0  0.0      0     0 ?        S    13:37   0:00 [kthrotld/1]
root        76  0.0  0.0      0     0 ?        S    13:37   0:00 [kthrotld/2]
root        77  0.0  0.0      0     0 ?        S    13:37   0:00 [kthrotld/3]
root       271  0.0  0.0      0     0 ?        S    13:37   0:00 [ext4-dio-unwrit]
```

 * 遅延処理
   * カーネルスレッド
   * プロセスコンテキスト
 * queue_work   
 * run_workqueue
 * flush_workqueue
 * queue_delayed_work, cancel_delayed_work

> 主にプロセスコンテキストの処理を遅延させるために利用されています

 * 割り込みコンテキストの遅延処理
   * softirq, ksoftirqd, tasklet
 * デバイスドライバ、ブロックI/O、非同期I/O

## 3.2.1 workqueue のデータ構造

> それぞれのCPU用のエントリを持ち、そのCPU上で実行すべき処理 (work_struct構造体) を複数登録できます

2.6.15 と 2.6.32 とで中身が全然違う。下記は 2.6.32

```
[cpu0]
workqueue_struct
  \___ .cpu_wq -> cpu_workqueue_struct
                    \___ .work_list -> work_struct -> work_struct -> ...

[cpu1]                    
workqueue_struct
  \___ .cpu_wq -> cpu_workqueue_struct
                    \___ .work_list -> work_struct -> work_struct -> ...
```

workqueue_struct は CPUごとに用意 (1CPUしか使わないのもあるけど)

```c
/*
 * The externally visible workqueue abstraction is an array of
 * per-CPU workqueues:
 */
struct workqueue_struct {
	struct cpu_workqueue_struct *cpu_wq;
	struct list_head list;
	const char *name;
	int singlethread;
	int freezeable;		/* Freeze threads during suspend */
	int rt;
#ifdef CONFIG_LOCKDEP
	struct lockdep_map lockdep_map;
#endif
};
```

struct cpu_workqueue_struct の中身

 * worklist が struct work_struct (ジョブ) のリスト
 * 待ちキュー
 * more_work でカーネルスレッドを待たせる

```c
/*
 * The per-CPU workqueue (if single thread, we always use the first
 * possible cpu).
 */
struct cpu_workqueue_struct {

	spinlock_t lock;

	struct list_head worklist;
	wait_queue_head_t more_work;
	struct work_struct *current_work;

	struct workqueue_struct *wq;
	struct task_struct *thread;
} ____cacheline_aligned;
```

struct work_struct (≒ job) の中身

 * 遅延処理用の関数
 * 遅延処理に渡す任意のデータ

```c
struct work_struct {
	atomic_long_t data;
#define WORK_STRUCT_PENDING 0		/* T if work item pending execution */
#define WORK_STRUCT_FLAG_MASK (3UL)
#define WORK_STRUCT_WQ_DATA_MASK (~WORK_STRUCT_FLAG_MASK)
	struct list_head entry;
	work_func_t func;
#ifdef CONFIG_LOCKDEP
	struct lockdep_map lockdep_map;
#endif
};
```

```c
struct delayed_work {
	struct work_struct work;
	struct timer_list timer;
};
```

## workqueue のスレッド

worker_thread 

```c
static int worker_thread(void *__cwq)
{
	struct cpu_workqueue_struct *cwq = __cwq;
	DEFINE_WAIT(wait);

	if (cwq->wq->freezeable)
		set_freezable();

	for (;;) {
		prepare_to_wait(&cwq->more_work, &wait, TASK_INTERRUPTIBLE);
		if (!freezing(current) &&
		    !kthread_should_stop() &&
		    list_empty(&cwq->worklist))
			schedule();
		finish_wait(&cwq->more_work, &wait);

		try_to_freeze();

		if (kthread_should_stop())
			break;

		run_workqueue(cwq);
	}

	return 0;
}
```

run_workqueue で work_struct をひたすら捌く

```c
static void run_workqueue(struct cpu_workqueue_struct *cwq)
{
	spin_lock_irq(&cwq->lock);
	while (!list_empty(&cwq->worklist)) {
		struct work_struct *work = list_entry(cwq->worklist.next,
						struct work_struct, entry);
		work_func_t f = work->func;
#ifdef CONFIG_LOCKDEP
		/*
		 * It is permissible to free the struct work_struct
		 * from inside the function that is called from it,
		 * this we need to take into account for lockdep too.
		 * To avoid bogus "held lock freed" warnings as well
		 * as problems when looking into work->lockdep_map,
		 * make a copy and use that here.
		 */
		struct lockdep_map lockdep_map = work->lockdep_map;
#endif
		trace_workqueue_execution(cwq->thread, work);
		cwq->current_work = work;
		list_del_init(cwq->worklist.next);
		spin_unlock_irq(&cwq->lock);

		BUG_ON(get_wq_data(work) != cwq);
		work_clear_pending(work);
		lock_map_acquire(&cwq->wq->lockdep_map);
		lock_map_acquire(&lockdep_map);
		f(work);
		lock_map_release(&lockdep_map);
		lock_map_release(&cwq->wq->lockdep_map);

		if (unlikely(in_atomic() || lockdep_depth(current) > 0)) {
			printk(KERN_ERR "BUG: workqueue leaked lock or atomic: "
					"%s/0x%08x/%d\n",
					current->comm, preempt_count(),
				       	task_pid_nr(current));
			printk(KERN_ERR "    last function: ");
			print_symbol("%s\n", (unsigned long)f);
			debug_show_held_locks(current);
			dump_stack();
		}

		spin_lock_irq(&cwq->lock);
		cwq->current_work = NULL;
	}
	spin_unlock_irq(&cwq->lock);
}
```

## 3.2.3 汎用workqueue

keventd_wq

```
[vagrant@vagrant-centos65 linux-3.14.2]$ ps aux | grep event
root        19  0.0  0.0      0     0 ?        S    13:37   0:01 [events/0]
root        20  0.0  0.0      0     0 ?        S    13:37   0:00 [events/1]
root        21  0.0  0.0      0     0 ?        S    13:37   0:00 [events/2]
root        22  0.0  0.0      0     0 ?        S    13:37   0:00 [events/3]
```