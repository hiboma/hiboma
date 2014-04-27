# 3.2 workqueue

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

cpu_workqueue_struct の中身

 * work_struct のリスト
 * 待ちキュー

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

work_struct (≒ job)

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