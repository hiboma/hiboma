## 1.7　事象の待ち合わせ

 * 実行可能状態
   * TASK_RUNNING
 * 待機状態
   * TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE

> 待機状態のプロセスには2種類あります。1つはシグナルを受け付ける待機状態で、もう1つはシグナルを受け付けない待機状態です。前者はソケットや端末などでの事象発生を待ち合わせるときに利用します

ソケットや端末からデータを受け取れる保証が無いので、シグナルで解除できる必要がある

### 待機状態を観察

 * **/proc/<pid>/wchan**
 * ***ps ax -opid,state,wchan:25,cmd*** で確認してみる

```
   32 S worker_thread             [aio/0]
   33 S worker_thread             [crypto/0]
   38 S worker_thread             [kthrotld/0]
   40 S worker_thread             [kpsmoused]
   41 S worker_thread             [usbhid_resumer]
   71 S worker_thread             [kstriped]
  133 S scsi_error_handler        [scsi_eh_0]
  134 S scsi_error_handler        [scsi_eh_1]
  200 S kjournald2                [jbd2/sda1-8]
  201 S worker_thread             [ext4-dio-unwrit]
  275 S poll_schedule_timeout     /sbin/udevd -d
  298 S worker_thread             [virtio-net]
  300 S worker_thread             [iprt/0]
  484 S bdi_writeback_task        [flush-8:0]
  498 S poll_schedule_timeout     /sbin/udevd -d
  576 S kauditd_thread            [kauditd]
  824 S ep_poll                   auditd
  974 S poll_schedule_timeout     /usr/sbin/sshd
 1050 S ep_poll                   /usr/libexec/postfix/master
 1060 S hrtimer_nanosleep         crond
 1075 S n_tty_read                /sbin/agetty /dev/ttyS0 9600 vt100-nav
 1076 S n_tty_read                /sbin/mingetty /dev/tty1
 1078 S n_tty_read                /sbin/mingetty /dev/tty2
 1080 S n_tty_read                /sbin/mingetty /dev/tty3
 1082 S n_tty_read                /sbin/mingetty /dev/tty4
 1084 S poll_schedule_timeout     /sbin/udevd -d
 1085 S n_tty_read                /sbin/mingetty /dev/tty5
 1087 S n_tty_read                /sbin/mingetty /dev/tty6
 1943 S ep_poll                   qmgr -l -t fifo -u
 2262 S ep_poll                   pickup -l -t fifo -u
 2326 S unix_stream_recvmsg       sshd: vagrant [priv]
 2328 S poll_schedule_timeout     sshd: vagrant@pts/0
 2329 S wait                      -bash
 2348 R -                         ps ax -opid,state,wchan:25,cmd
```

## 1.7.1 待機処理

>　待機の対象となる可能性のあるカーネルオブジェクト（ファイルや、実ページ、端末など）は、それぞれWAITキュー（wait_queue_head_t型のリストヘッド）を用意しています。

[wait_queue_head_t](https://github.com/hiboma/kernel_module_scratch/tree/master/wait_queue_head_t) をメンバに持つカーネルオブジェクト

 * struct semaphore
 * struct kioctx
 * struct request_list
 * struct completion
 * struct file_lock
 * struct super_block
 * struct semaphore で wait_queue_head_t を持っているもの
   * struct block_device
   * struct inode
   * struct super_block
   * .. 一杯
  
```c
struct __wait_queue_head {
	spinlock_t lock;
	struct list_head task_list;
};
typedef struct __wait_queue_head wait_queue_head_t;
```

## sleep_on の実装

wait_queue_head_t はただのリスト

```
struct __wait_queue_head {
	spinlock_t lock;
	struct list_head task_list;
};
```

wait_queue_t の定義

```c
struct __wait_queue {
	unsigned int flags;
#define WQ_FLAG_EXCLUSIVE	0x01 // 1プロセスずつ起床させるか否かのフラグ
	void *private;
	wait_queue_func_t func;      // try_to_wake_up など起床用のコールバック
	struct list_head task_list;
};
```

> WAITキューからプロセスを外すのは、実は起床したプロセス自身です <55>

```c
 void sleep_on(wait_queue_head_t *q)
 {
         // 下記三行は ソースでは SLEEP_ON_VAR マクロで定義されている
         // 2.6.32: sleep_on_common に書き直されている
         unsigned long flags;
         // この関数スコープで queue を実現できるので、スタックに確保されている
         wait_queue_t wait;
         init_waitqueue_entry(&wait, current); ――<51>

         // 2.6.32: __set_current_state に書き直されている
         current->state = TASK_UNINTERRUPTIBLE; ――<52>
         spin_lock_irqsave(&q->lock,flags);
         // ただのリスト操作
         __add_wait_queue(q, &wait); ――<53>
         spin_unlock(&q->lock);

         // TASK_INTERRUPTIBLE, TASK_UNINTERRUPTIBLE なら deactivate_task で
         // runqueue から外される
         schedule(); ――<54>

         // 起床後 自分でキューから外す
         spin_lock_irq(&q->lock);
         __remove_wait_queue(q, &wait); ――<55>
         spin_unlock_irqrestore(&q->lock, flags);
 }
```

## 1.7.2 起床処理

起床すると TASK_RUNNING にはなるが、優先度の次第ですぐに実行権を得て再開する訳でないのが注意

 * in_interrupt
   * 割り込みコンテキストかどうかのフラグが current_thread_info にセットされている
 ```c
#define in_interrupt()		(irq_count())
#define irq_count()	(preempt_count() & (HARDIRQ_MASK | SOFTIRQ_MASK))
#define preempt_count()	(current_thread_info()->preempt_count)
```
 * activate_task
   * enqueue_task
 * resched_task()
   * 再スケジューリング要求 = 他プロセスからのプリエンプション要求
   * TIF_NEED_RESCHED の有無
   * プロセッサ間割り込み
     * runqueue はCPUごとに用意されているので、別のCPUに再スケジューリング用キュを出すには割り込みを書ける必要がある

## IPI Inter Processor Interrupt

> ほかのCPUのプロセススケジューラに対して要求する場合は、プロセッサ間割り込みを利用します

resched_task の smp_send_reschedule の事を指す

```c
/*
 * resched_task - mark a task 'to be rescheduled now'.
 *
 * On UP this means the setting of the need_resched flag, on SMP it
 * might also involve a cross-CPU call to trigger the scheduler on
 * the target CPU.
 */
#ifdef CONFIG_SMP
static void resched_task(task_t *p)
{
	int cpu;

	assert_spin_locked(&task_rq(p)->lock);

    // TIF_NEED_RESCHED が立っている == 再スケジューリング要求が出ている
	if (unlikely(test_tsk_thread_flag(p, TIF_NEED_RESCHED)))
		return;

	set_tsk_thread_flag(p, TIF_NEED_RESCHED);

    // 実行CPU がプロセスのCPUと一緒かどうか
	cpu = task_cpu(p);
	if (cpu == smp_processor_id())
		return;

	/* NEED_RESCHED must be visible before we test POLLING_NRFLAG */
	smp_mb();
	if (!test_tsk_thread_flag(p, TIF_POLLING_NRFLAG))
        // 指定したCPUに IPI で再スケジューリングを飛ばす
		smp_send_reschedule(cpu);
}
#else
```

smp_send_reschedule の中身

 * プロセッサ間割り込みを利用して、他のCPUに再スケジューリング要求を出す
   * IPI = Inter Processor Interrupts の略称
   * RESCHEDULE_VECTOR は再スケジューリングを要求する割り込み番号のこと
     * 他にも INVALIDATE_TLB_VECTOR (TLBのフラッシュ) ... などがある

```c
/*
 * this function sends a 'reschedule' IPI to another CPU.
 * it goes straight through and wastes no time serializing
 * anything. Worst case is that we lose a reschedule ...
 */

void smp_send_reschedule(int cpu)
{
	send_IPI_mask(cpumask_of_cpu(cpu), RESCHEDULE_VECTOR);
}
```

asm-i386/mach-default/irq_vectors にベクタが羅列されている

```c
/*
 * Special IRQ vectors used by the SMP architecture, 0xf0-0xff
 *
 *  some of the following vectors are 'rare', they are merged
 *  into a single vector (CALL_FUNCTION_VECTOR) to save vector space.
 *  TLB, reschedule and local APIC vectors are performance-critical.
 *
 *  Vectors 0xf0-0xfa are free (reserved for future Linux use).
 */
#define SPURIOUS_APIC_VECTOR	0xff
#define ERROR_APIC_VECTOR	0xfe
#define INVALIDATE_TLB_VECTOR	0xfd
#define RESCHEDULE_VECTOR	0xfc
#define CALL_FUNCTION_VECTOR	0xfb
```

割り込みベクタと割り込みハンドラは SMP の初期化で設定されている

```c
void __init smp_intr_init(void)
{
	/*
	 * IRQ0 must be given a fixed assignment and initialized,
	 * because it's used before the IO-APIC is set up.
	 */
	set_intr_gate(FIRST_DEVICE_VECTOR, interrupt[0]);

	/*
	 * The reschedule interrupt is a CPU-to-CPU reschedule-helper
	 * IPI, driven by wakeup.
	 */
	set_intr_gate(RESCHEDULE_VECTOR, reschedule_interrupt);

	/* IPI for invalidation */
	set_intr_gate(INVALIDATE_TLB_VECTOR, invalidate_interrupt);

	/* IPI for generic function call */
	set_intr_gate(CALL_FUNCTION_VECTOR, call_function_interrupt);
}
```

invalidate_interrupt, reschedule_interrupt の実装は長いので省略

## try_to_wake_up の実装

```c
/***
 * try_to_wake_up - wake up a thread
 * @p: the to-be-woken-up thread
 * @state: the mask of task states that can be woken
 * @sync: do a synchronous wakeup?
 *
 * Put it on the run-queue if it's not already there. The "current"
 * thread is always on the run-queue (except when the actual
 * re-schedule is in progress), and as such you're allowed to do
 * the simpler "current->state = TASK_RUNNING" to mark yourself
 * runnable without the overhead of this.
 *
 * returns failure only if the task is already active.
 */
static int try_to_wake_up(task_t *p, unsigned int state, int sync)
{
	int cpu, this_cpu, success = 0;
	unsigned long flags;
	long old_state;
	runqueue_t *rq;
#ifdef CONFIG_SMP
	unsigned long load, this_load;
	struct sched_domain *sd, *this_sd = NULL;
	int new_cpu;
#endif

    // 起床するプロセスの runqueue をロック
	rq = task_rq_lock(p, &flags);
	old_state = p->state;
    // ???
    // TASK_RUNNING な場合?
	if (!(old_state & state))
		goto out;

    // 優先度??
	if (p->array)
		goto out_running;

	cpu = task_cpu(p);
	this_cpu = smp_processor_id();

#ifdef CONFIG_SMP
    // rq で p が TASK_RUNNING でCPU使ってる場合は out_activate
	if (unlikely(task_running(rq, p)))
		goto out_activate;

	new_cpu = cpu;

    // Try To Wake Up Count
	schedstat_inc(rq, ttwu_cnt);
	if (cpu == this_cpu) {
        // Try To Wake Up Count Local
        // 起床したCPUが変わらない場合
		schedstat_inc(rq, ttwu_local);
		goto out_set_cpu;
	}

	for_each_domain(this_cpu, sd) {
		if (cpu_isset(cpu, sd->span)) {
			schedstat_inc(sd, ttwu_wake_remote);
			this_sd = sd;
			break;
		}
	}

	if (unlikely(!cpu_isset(this_cpu, p->cpus_allowed)))
		goto out_set_cpu;

	/*
	 * Check for affine wakeup and passive balancing possibilities.
	 */
	if (this_sd) {
		int idx = this_sd->wake_idx;
		unsigned int imbalance;

		imbalance = 100 + (this_sd->imbalance_pct - 100) / 2;

		load = source_load(cpu, idx);
		this_load = target_load(this_cpu, idx);

		new_cpu = this_cpu; /* Wake to this CPU if we can */

		if (this_sd->flags & SD_WAKE_AFFINE) {
			unsigned long tl = this_load;
			/*
			 * If sync wakeup then subtract the (maximum possible)
			 * effect of the currently running task from the load
			 * of the current CPU:
			 */
			if (sync)
				tl -= SCHED_LOAD_SCALE;

			if ((tl <= load &&
				tl + target_load(cpu, idx) <= SCHED_LOAD_SCALE) ||
				100*(tl + SCHED_LOAD_SCALE) <= imbalance*load) {
				/*
				 * This domain has SD_WAKE_AFFINE and
				 * p is cache cold in this domain, and
				 * there is no bad imbalance.
				 */
				schedstat_inc(this_sd, ttwu_move_affine);
				goto out_set_cpu;
			}
		}

		/*
		 * Start passive balancing when half the imbalance_pct
		 * limit is reached.
		 */
		if (this_sd->flags & SD_WAKE_BALANCE) {
			if (imbalance*this_load <= 100*load) {
				schedstat_inc(this_sd, ttwu_move_balance);
				goto out_set_cpu;
			}
		}
	}

	new_cpu = cpu; /* Could not wake to this_cpu. Wake to cpu instead */
out_set_cpu:
	new_cpu = wake_idle(new_cpu, p);
	if (new_cpu != cpu) {
		set_task_cpu(p, new_cpu);
		task_rq_unlock(rq, &flags);
		/* might preempt at this point */
		rq = task_rq_lock(p, &flags);
		old_state = p->state;
		if (!(old_state & state))
			goto out;
		if (p->array)
			goto out_running;

		this_cpu = smp_processor_id();
		cpu = task_cpu(p);
	}

out_activate:
#endif /* CONFIG_SMP */

    // TASK_UNINTERRUPTIBLE なプロセスを起床させた場合
    // activated が -1 になる
	if (old_state == TASK_UNINTERRUPTIBLE) {
		rq->nr_uninterruptible--;
		/*
		 * Tasks on involuntary sleep don't earn
		 * sleep_avg beyond just interactive state.
		 */
		p->activated = -1;
	}

	/*
	 * Tasks that have marked their sleep as noninteractive get
	 * woken up without updating their sleep average. (i.e. their
	 * sleep is handled in a priority-neutral manner, no priority
	 * boost and no penalty.)
	 */
    // バッチ形プロセスの場合
	if (old_state & TASK_NONINTERACTIVE)
        // enqueue_task するだけで優先度を変更しない
        // activate_task との違いを確認するとよい
		__activate_task(p, rq);
	else
        // 対話型プロセスの場合 activate_task を呼ぶ
        //
        //   __activate_task に加えて recalc_task_prio で優先度の再計算をする
        //   割り込みコンテキストの場合は p->activated = 2 にする
        //   TASK_INTERRUPTIBLE の場合は  p->activated = 1 にする
        //
        // p->timestamp が更新される
        // activate_task によって優先度が更新され resched_task される可能性が高くなる
		activate_task(p, rq, cpu == this_cpu);
	/*
	 * Sync wakeups (i.e. those types of wakeups where the waker
	 * has indicated that it will leave the CPU in short order)
	 * don't trigger a preemption, if the woken up task will run on
	 * this cpu. (in this case the 'I will reschedule' promise of
	 * the waker guarantees that the freshly woken up task is going
	 * to be considered on this CPU.)
	 */
     // 同期 wakeup
	if (!sync || cpu != this_cpu) {

        // #define TASK_PREEMPTS_CURR(p, rq) \
        //	((p)->prio < (rq)->curr->prio)
        // 起床したプロセスの方が current より優先度が高い場合 は再スケジューリング要求 (プリエンプション要求) を出す
        // prio の値が低い方が優先度高い
		if (TASK_PREEMPTS_CURR(p, rq))
			resched_task(rq->curr);
	}
	success = 1;

out_running:
    // runqueue に繋いだので TASK_RUNNING にしておく
	p->state = TASK_RUNNING;
out:
	task_rq_unlock(rq, &flags);

	return success;
}

/*
 * activate_task - move a task to the runqueue and do priority recalculation
 *
 * Update all the scheduling statistics stuff. (sleep average
 * calculation, priority modifiers, etc.)
 */
static void activate_task(task_t *p, runqueue_t *rq, int local)
{
	unsigned long long now;

	now = sched_clock();
#ifdef CONFIG_SMP
	if (!local) {
		/* Compensate for drifting sched_clock */
		runqueue_t *this_rq = this_rq();
		now = (now - this_rq->timestamp_last_tick)
			+ rq->timestamp_last_tick;
	}
#endif

	if (!rt_task(p))
        // 優先度の再計算
        // 長いこと待機状態だったプロセスの方が高い優先度になる
		p->prio = recalc_task_prio(p, now);

	/*
	 * This checks to make sure it's not an uninterruptible task
	 * that is now waking up.
	 */
	if (!p->activated) {
		/*
		 * Tasks which were woken up by interrupts (ie. hw events)
		 * are most likely of interactive nature. So we give them
		 * the credit of extending their sleep time to the period
		 * of time they spend on the runqueue, waiting for execution
		 * on a CPU, first time around:
		 */
		if (in_interrupt())
           // 割り込みコンテキストからの起床
			p->activated = 2;
		else {
			/*
			 * Normal first-time wakeups get a credit too for
			 * on-runqueue time, but it will be weighted down:
			 */
            // 通常コンテキスト? からの起床
			p->activated = 1;
		}
	}

    // timestamp は runqueue に繋がれた際の時刻
	p->timestamp = now;

    // enqueue_task で runqueue の active キューに繋ぐ
    // enqueue_task は 優先度 Array の末尾に繋ぐ (実行待ち状態)
    //
    //  +---+
    //  |---|
    //  |---| => task_t <=> task_t <=> <= enqueue_task
    //  |---|
    //  |---| => task_t <=> task_t ...
    //  +---+
    //
	__activate_task(p, rq);
}

int fastcall wake_up_process(task_t *p)
{
	return try_to_wake_up(p, TASK_STOPPED | TASK_TRACED |
				 TASK_INTERRUPTIBLE | TASK_UNINTERRUPTIBLE, 0);
}

EXPORT_SYMBOL(wake_up_process);
```

 * wake_up_*_sync 群はプリエンプト要求を出さない (起床後も実行中のプロセスが継続される)
   * try_to_wake_up で プリエンプトするか否かを決定している

 ```c
// try_to_wake_up

	/*
	 * Sync wakeups (i.e. those types of wakeups where the waker
	 * has indicated that it will leave the CPU in short order)
	 * don't trigger a preemption, if the woken up task will run on
	 * this cpu. (in this case the 'I will reschedule' promise of
	 * the waker guarantees that the freshly woken up task is going
	 * to be considered on this CPU.)
	 */
    // 1. sync が立ってなければプリエンプションする
    // 2. 別のCPU ならプリエンプションする
	if (!sync || cpu != this_cpu) {
       // ((p)->prio < (rq)->curr->prio) 優先度の比較
		if (TASK_PREEMPTS_CURR(p, rq))
            // TIF_NEED_RESCHED を立てる
			resched_task(rq->curr);
	}
```

> ところでLinuxカーネル内のコードでは、プロセスを待機状態に遷移させるとき、sleep_on関数やsleep_on_interruptible関数を利用せず、その関数と同等のこと（WAITキュー操作とプロセススケジューラの呼び出し）を直接行っている個所があちこちにあります

サンプルが欲しいな

```
1 目的の事象が成立しているか調べる
  <ここでイベントが発火する可能性がある>
2 成立していなければ、sleep_on関数を呼び出す
  2-1 プロセスをWAITキューに登録
  2-2 プロセススケジューラ（schedule関数）を呼び出す
  2-3 プロセスが起床したら、プロセスをWAITキューから外す
```

```
1 プロセスをWAITキューに登録（prepare_to_wait関数、またはprepare_to_wait_exclusive関数）
2 目的の事象が成立しているか調べる
3 成立していなければ、プロセススケジューラ（schedule関数）を呼び出す
4 プロセスが起床したら、プロセスをWAITキューから外す（finish_wait関数）
```

>　ところで、もう1つ実装上の疑問点を持たれた方もおられると思います。プロセスが待機状態になったとき、そのプロセス用のtask_struct構造体をWAITキューに直接登録しないのはなぜなのでしょうか？　実はこの構造には面白い特徴があり、プロセスを同時に複数のWAITキューに登録できます。複数の事象を同時に待ち合わせ、いずれかの事象が成立したら起床できます（図1-15）。この仕組みはselectシステムコールやpollシステムコールの実現に利用しています。

select や poll は複数のファイルデスクリプタの監視ができるので複数の waitqueue に繋いでる状態にを取りうる

## poll を覗き見

select(2) は do_select の中で file_operations の .poll を呼び出す

```
int do_select(int n, fd_set_bits *fds, long *timeout)
{
	struct poll_wqueues table;
	poll_table *wait;
	int retval, i;
	long __timeout = *timeout;

	rcu_read_lock();
	retval = max_select_fd(n, fds);
	rcu_read_unlock();

	if (retval < 0)
		return retval;
	n = retval;

	poll_initwait(&table);
	wait = &table.pt;
	if (!__timeout)
		wait = NULL;
	retval = 0;
	for (;;) {
		unsigned long *rinp, *routp, *rexp, *inp, *outp, *exp;

		set_current_state(TASK_INTERRUPTIBLE);

		inp = fds->in; outp = fds->out; exp = fds->ex;
		rinp = fds->res_in; routp = fds->res_out; rexp = fds->res_ex;

		for (i = 0; i < n; ++rinp, ++routp, ++rexp) {
			unsigned long in, out, ex, all_bits, bit = 1, mask, j;
			unsigned long res_in = 0, res_out = 0, res_ex = 0;
			struct file_operations *f_op = NULL;
			struct file *file = NULL;

			in = *inp++; out = *outp++; ex = *exp++;
			all_bits = in | out | ex;
			if (all_bits == 0) {
				i += __NFDBITS;
				continue;
			}

			for (j = 0; j < __NFDBITS; ++j, ++i, bit <<= 1) {
				if (i >= n)
					break;
				if (!(bit & all_bits))
					continue;
				file = fget(i);
				if (file) {
					f_op = file->f_op;
					mask = DEFAULT_POLLMASK;
					if (f_op && f_op->poll)
						mask = (*f_op->poll)(file, retval ? NULL : wait);
```

ソケットの場合 file_operations の正体は socket_file_ops

```c
/*
 *      Socket files have a set of 'special' operations as well as the generic file ones. These don't appear
 *      in the operation structures but are done directly via the socketcall() multiplexor.
 */

static struct file_operations socket_file_ops = {
        .owner =        THIS_MODULE,
        .llseek =       no_llseek,
        .aio_read =     sock_aio_read,
        .aio_write =    sock_aio_write,
        .poll =         sock_poll,
        .unlocked_ioctl = sock_ioctl,
        .mmap =         sock_mmap,
        .open =         sock_no_open,   /* special open code to disallow open via /proc */
        .release =      sock_close,
        .fasync =       sock_fasync,
        .readv =        sock_readv,
        .writev =       sock_writev,
        .sendpage =     sock_sendpage
};
```

tcp の poll は tcp_poll -> poll_wait と繋がる

```c
/*
 *	Wait for a TCP event.
 *
 *	Note that we don't need to lock the socket, as the upper poll layers
 *	take care of normal races (between the test and the event) and we don't
 *	go look at any of the socket buffers directly.
 */
unsigned int tcp_poll(struct file *file, struct socket *sock, poll_table *wait)
{
	unsigned int mask;
	struct sock *sk = sock->sk;
	struct tcp_sock *tp = tcp_sk(sk);

	poll_wait(file, sk->sk_sleep, wait);
```

udp の poll は udp_poll -> datagram_poll -> poll_wait と繋がる

```c
/**
 * 	datagram_poll - generic datagram poll
 *	@file: file struct
 *	@sock: socket
 *	@wait: poll table
 *
 *	Datagram poll: Again totally generic. This also handles
 *	sequenced packet sockets providing the socket receive queue
 *	is only ever holding data ready to receive.
 *
 *	Note: when you _don't_ use this routine for this protocol,
 *	and you use a different write policy from sock_writeable()
 *	then please supply your own write_space callback.
 */
unsigned int datagram_poll(struct file *file, struct socket *sock,
			   poll_table *wait)
{
	struct sock *sk = sock->sk;
	unsigned int mask;

	poll_wait(file, sk->sk_sleep, wait);
	mask = 0;

	/* exceptional events? */

    // select(2), poll(2) でどんなイベントが発生したかを確認するための
    // mask がセットされている
	if (sk->sk_err || !skb_queue_empty(&sk->sk_error_queue))
		mask |= POLLERR;
	if (sk->sk_shutdown == SHUTDOWN_MASK)
		mask |= POLLHUP;
```

poll_wait の中身はどんなんか?


```c
static inline void poll_wait(struct file * filp, wait_queue_head_t * wait_address, poll_table *p)
{
	if (p && wait_address)
		p->qproc(filp, wait_address, p);
}
```

select / poll は __pollwait で qproc を実装している

```c
static void __pollwait(struct file *filp, wait_queue_head_t *wait_address,
		       poll_table *_p)
{
	struct poll_wqueues *p = container_of(_p, struct poll_wqueues, pt);
	struct poll_table_page *table = p->table;

	if (!table || POLL_TABLE_FULL(table)) {
		struct poll_table_page *new_table;

		new_table = (struct poll_table_page *) __get_free_page(GFP_KERNEL);
		if (!new_table) {
			p->error = -ENOMEM;
			__set_current_state(TASK_RUNNING);
			return;
		}
		new_table->entry = new_table->entries;
		new_table->next = table;
		p->table = new_table;
		table = new_table;
	}

	/* Add a new entry */
	{
		struct poll_table_entry * entry = table->entry;
		table->entry = entry+1;
	 	get_file(filp);
	 	entry->filp = filp;
		entry->wait_address = wait_address;

        // ここで waitqueue に繋ぐ
		init_waitqueue_entry(&entry->wait, current);
        // WQ_FLAG_EXCLUSIVE 無し
        // waitqueue に繋ぐだけで schedule() は呼び出さずプロセスは続行する
		add_wait_queue(wait_address,&entry->wait);
	}
}
```

epoll は ep_ptable_queue_proc で qproc を実装している

```c
/*
 * This is the callback that is used to add our wait queue to the
 * target file wakeup lists.
 */
static void ep_ptable_queue_proc(struct file *file, wait_queue_head_t *whead,
				 poll_table *pt)
{
	struct epitem *epi = ep_item_from_epqueue(pt);
	struct eppoll_entry *pwq;

	if (epi->nwait >= 0 && (pwq = kmem_cache_alloc(pwq_cache, SLAB_KERNEL))) {
		init_waitqueue_func_entry(&pwq->wait, ep_poll_callback);
		pwq->whead = whead;
		pwq->base = epi;
		add_wait_queue(whead, &pwq->wait);
		list_add_tail(&pwq->llink, &epi->pwqlist);
		epi->nwait++;
	} else {
		/* We have to signal that an error occurred */
		epi->nwait = -1;
	}
}
```

## 1.7.4　子プロセスのスケジューリング

>forkシステムコールによって子プロセスが生成されたときは、この子プロセスを実行状態としてスケジューリング対象に加えます（wake_up_forked_process関数）

バニラカーネルにはそんな関数ないぞう

> 子プロセスの実行優先度は親プロセスから引き継ぎ*2、親プロセスと同じRUNキューの親プロセスの前に挿入し、プリエンプト要求を発生させます（set_need_resched関数）。

```c
// http://www.tsri.com/jeneral/kernel/kernel/sched.c/pm/PM-WAKE_UP_FORKED_PROCESS.html
/*
 * wake_up_forked_process - wake up a freshly forked process.
 *
 * This function will do some initial scheduler statistics housekeeping
 * that must be done for every newly created process.
 */
void wake_up_forked_process(task_t * p)
{
	unsigned long flags;
	runqueue_t *rq = task_rq_lock(current, &flags);

	BUG_ON(p->state != TASK_RUNNING);

	/*
	 * We decrease the sleep average of forking parents
	 * and children as well, to keep max-interactive tasks
	 * from forking tasks that are max-interactive.
	 */
    // 親プロセス
    // PARENT_PENALTY = 100
	current->sleep_avg = JIFFIES_TO_NS(CURRENT_BONUS(current) *
		PARENT_PENALTY / 100 * MAX_SLEEP_AVG / MAX_BONUS);

    // 子プロセス
    //   CHILD_PENALTY  = 95
    // 子プロセスの方が sleep_avg が短くなる
	p->sleep_avg = JIFFIES_TO_NS(CURRENT_BONUS(p) *
		CHILD_PENALTY / 100 * MAX_SLEEP_AVG / MAX_BONUS);

	p->interactive_credit = 0;

    // 優先度を引き継ぐ
	p->prio = effective_prio(p);
	set_task_cpu(p, smp_processor_id());

	if (unlikely(!current->array))
		__activate_task(p, rq);
	else {
		p->prio = current->prio;
        // ???親プロセスの前 ???
		list_add_tail(&p->run_list, &current->run_list);
        // 優先度キューも引き継ぐ
		p->array = current->array;
		p->array->nr_active++;
		nr_running_inc(rq);
	}
	task_rq_unlock(rq, &flags);
}
```

> また子プロセスを生成したとき、親プロセスは実行割り当て時間の半分を子プロセスに譲るようになっています。

do_fork -> sched_fork の中にコードがある

```c
/*
 * Perform scheduler related setup for a newly forked process p.
 * p is forked by current.
 */
void fastcall sched_fork(task_t *p, int clone_flags)

// ...

	/*
	 * Share the timeslice between parent and child, thus the
	 * total amount of pending timeslices in the system doesn't change,
	 * resulting in more scheduling fairness.
	 */
	local_irq_disable();
    // p が子プロセス current が親
    // 親プロセスのタイムスライスの半分( >> 1 ) を割り当て
    // システム全体でのタイムスライスの総量は変わらない
	p->time_slice = (current->time_slice + 1) >> 1;
	/*
	 * The remainder of the first timeslice might be recovered by
	 * the parent if the child exits early enough.
	 */
    // ???
	p->first_time_slice = 1;

    // 親のタイムスライスを半分
	current->time_slice >>= 1;
	p->timestamp = sched_clock();
	if (unlikely(!current->time_slice)) {
		/*
		 * This case is rare, it happens when the parent has only
		 * a single jiffy left from its timeslice. Taking the
		 * runqueue lock is not a problem.
		 */
		current->time_slice = 1;
		scheduler_tick();
	}
	local_irq_enable();
	put_cpu();
```