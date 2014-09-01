# 2.3 ハードウェア割り込み処理

## 2.3.1 割り込みの種類

#### 割り込み Intterupt

![](http://sourceforge.jp/projects/linux-kernel-docs/wiki/2.3%E3%80%80ハードウェア割り込み処理/attach/fig2-1.png)

 * External Interruputs 外部デバイスの割り込み
   * ネットワークカード、端末装置、SCSIホストアダプタ
 * IPI = Inter Processor Interrupts プロセッサ間割り込み
   * smp_send_reschedule
     * 再スケジューリング要求を出すために他のCPUに割り込みをかける
     * send_IPI_mask でIPIを出す -> reschedule_interrupt で受け取る
   * invalidate_interrupt
     * TLB の破棄?
   * call_function_interrupt
 * タイマー割り込み
   * ローカルタイマー
     * APIC ? 
   * グローバルタイマー
 * NMI = Non Maskable Interrupts
   * ハードウェアの故障などの通知
   * EFLAGS の IFフラグをオフにしていても割り込まれる

/proc/interrupts で割り込みの統計を見る   

```
[vagrant@vagrant-centos65 ~]$ cat /proc/interrupts 
           CPU0       CPU1       CPU2       CPU3       
  0:        150          0          0          0   IO-APIC-edge      timer
  1:          7          0          0          0   IO-APIC-edge      i8042
  8:          0          0          0          0   IO-APIC-edge      rtc0
  9:          0          0          0          0   IO-APIC-fasteoi   acpi
 12:        108          0          0          0   IO-APIC-edge      i8042
 19:        725          0          0          0   IO-APIC-fasteoi   virtio0
 21:       3712          0          0          0   IO-APIC-fasteoi   ahci
NMI:          0          0          0          0   Non-maskable interrupts
LOC:      10836      12535      11710      11944   Local timer interrupts
SPU:          0          0          0          0   Spurious interrupts
PMI:          0          0          0          0   Performance monitoring interrupts
IWI:          0          0          0          0   IRQ work interrupts
RES:       4077       2796       1925       1347   Rescheduling interrupts
CAL:         57        128        148        147   Function call interrupts
TLB:        112        741        693        382   TLB shootdowns
TRM:          0          0          0          0   Thermal event interrupts
THR:          0          0          0          0   Threshold APIC interrupts
MCE:          0          0          0          0   Machine check exceptions
MCP:          3          3          3          3   Machine check polls
ERR:          0
MIS:          0
```

/proc/softirqs で softirq の統計を見る

```
[vagrant@vagrant-centos65 ~]$ cat /proc/softirqs 
                CPU0       CPU1       CPU2       CPU3       
      HI:          0          0          0          0
   TIMER:       9351      11755      10884      11256
  NET_TX:          0          0          0          0
  NET_RX:        753          0          0          0
   BLOCK:       3527         35          4         16
BLOCK_IOPOLL:          0          0          0          0
 TASKLET:          2          0          0          0
   SCHED:       2299       2782       2732       2746
 HRTIMER:         57         49         35         31
     RCU:      11816      12516      12003      12054
```

#### send_IPI 群

プロセッサ間割り込み Inter Processor Interrupts

 * 下のは IA64 だった ...
 * x86 だと arch/x86/kernel/apic/ 以下を見る必要がある?

```c
/*
 * Called with preemption disabled.
 */
static inline void
send_IPI_single (int dest_cpu, int op)
{
    // ipi_operation CPUキャッシュのアラインのために DEFINE_PER_CPU_SHARED_ALIGNED でごにょごにょ
    // dest_cpu の per_cpu に op ビットを立てる
	set_bit(op, &per_cpu(ipi_operation, dest_cpu));

    // 役割に応じて割り込みベクタの定数が複数設定されている
    //
    //     #define IA64_IPI_LOCAL_TLB_FLUSH	0xfc	/* SMP flush local TLB */
    //     #define IA64_IPI_RESCHEDULE		0xfd	/* SMP reschedule */
    //     #define IA64_IPI_VECTOR			0xfe	/* inter-processor interrupt vector */
    //
    // 外部割り込みを pending させながら IPI を送る?
    //
    //     IA64_IPI_DM_INT =       0x0,    /* pend an external interrupt */
    //
	platform_send_ipi(dest_cpu, IA64_IPI_VECTOR, IA64_IPI_DM_INT, 0);
}
```

 * send_IPI_mask cpumask で指定した CPU だけに IPI を飛ばす
 * send_IPI_all  全部の CPU に飛ばす
 * send_IPI_self , send_IPI_allbutself など

## 2.3.2 ハードウェア割り込み処理の動作例

![](http://sourceforge.jp/projects/linux-kernel-docs/wiki/2.3%E3%80%80ハードウェア割り込み処理/attach/fig2-2.png)

### 受信処理

#### 1. socket に read, recv, recvfrom, recvmsg を呼び TASK_INTERRUPTIBLE で待つ

#### PF_INET + TCP (tcp_proto + inet_stream_ops ) recvfrom の場合のスタック

recv_from からどんどん潜って行く

```
recv_from
sock_recvmsg
__sock_recvmsg
__sock_recvmsg_nosec
sock->ops->recvmsg
# ---- AF_INET 層 -----
inet_recvmsg
sk->sk_proto->recvmsg
# ---- TCP 層 -----
tcp_recvmsg
sk_wait_data
```

tcp_recvmsg を呼び出した場合

 * sk_wait_data で TASK_INTERRUPTIBLE で待つ
   * ***sk->sk_receive_queue*** が空か否かが待つ条件となる
```c
/**
 * sk_wait_data - wait for data to arrive at sk_receive_queue
 * @sk:    sock to wait on
 * @timeo: for how long
 *
 * Now socket state including sk->sk_err is changed only under lock,
 * hence we may omit checks after joining wait queue.
 * We check receive queue before schedule() only as optimization;
 * it is very likely that release_sock() added new data.
 */
int sk_wait_data(struct sock *sk, long *timeo)
{
	int rc;
	DEFINE_WAIT(wait);
    // prepare_to_wait で wait の準備をして schedule_timeout する前に skb_queue_empty で確認する
	prepare_to_wait(sk->sk_sleep, &wait, TASK_INTERRUPTIBLE);
	set_bit(SOCK_ASYNC_WAITDATA, &sk->sk_socket->flags);
    // schedule_timeout() でタイムアウト付きで スケジューリングする
	rc = sk_wait_event(sk, timeo, !skb_queue_empty(&sk->sk_receive_queue));
	clear_bit(SOCK_ASYNC_WAITDATA, &sk->sk_socket->flags);
	finish_wait(sk->sk_sleep, &wait);
	return rc;
}
EXPORT_SYMBOL(sk_wait_data);
```

#### PF_INET + UDP の場合

 * udp_recvmsg ->__skb_recv_datagram -> wait_for_packet
   * ***sk->sk_receive_queue*** が空か否かで待つ
   * prepare_to_wait_exclusive + TASK_INTERRUPTIBLE で待ち
   * signal_pending() でシグナルをハンドリング
   * schedule_timeout() でタイムアウト or 起床待ち
```c
/*
 * Wait for a packet..
 */
static int wait_for_packet(struct sock *sk, int *err, long *timeo_p)
{
	int error;
	DEFINE_WAIT_FUNC(wait, receiver_wake_function);

    // exclusive 指定なので 1プロセスずつ起床する
	prepare_to_wait_exclusive(sk->sk_sleep, &wait, TASK_INTERRUPTIBLE);

	/* Socket errors? */
	error = sock_error(sk);
	if (error)
		goto out_err;

	if (!skb_queue_empty(&sk->sk_receive_queue))
		goto out;

	/* Socket shut down? */
	if (sk->sk_shutdown & RCV_SHUTDOWN)
		goto out_noerr;

	/* Sequenced packets can come disconnected.
	 * If so we report the problem
	 */
	error = -ENOTCONN;
	if (connection_based(sk) &&
	    !(sk->sk_state == TCP_ESTABLISHED || sk->sk_state == TCP_LISTEN))
		goto out_err;

	/* handle signals */
	if (signal_pending(current))
		goto interrupted;

	error = 0;
	*timeo_p = schedule_timeout(*timeo_p);
out:
	finish_wait(sk->sk_sleep, &wait);
	return error;
interrupted:
	error = sock_intr_errno(*timeo_p);
out_err:
	*err = error;
	goto out;
out_noerr:
	*err = 0;
	error = 1;
	goto out;
}
```

#### 2. ハードウェアの動作なので分からん

 * ~~ネットワークカードの割り込みベクタは 19 ぽい~~
   * VirtualBox の virit-net だと 19 なだけ

#### 3. ハードウェア割り込みハンドラ

 * interrupt
 * common_interrupt
   * 割り込みベクタ (IRQ vector) を実行している時は 割込は disabled な状態
 * do_IRQ
 * handle_irq でデバイスドライバのハンドラに委譲される

interrupt の時点で割り込みを受けた CPU は決まっている? 

#### 4. ハードウェア割り込みハンドラからソフト割り込み発行

実装はデバイスドライバ依存

 * __netif_rx_schedule
   * __raise_softirq_irqoff(NET_RX_SOFTIRQ) で ソフト割り込み
 * VirtualBox は virio-net
   * virtnet_poll -> napi_schedule からも __raise_softirq_irqoff(NET_RX_SOFTIRQ) を呼ぶ

#### 5. net_rx_action

 * softirq ハンドラが起動するタイミングが分からない
   * => do_IRQ の irq_exit
 * process_backlog -> __skb_dequeue -> __netif_receive_skb ->  deliver_skb
   * struct packet_type のハンドラを呼んでプロトコルのハンドラへ委譲
   * TASK_INTERRUPTIBLE なプロセスを起床させる箇所が分からん

#### 6. プロセスが起床してシステムコール呼び出し元に戻る

## 2.3.3 ハードウェア割り込み管理データ構造

![](http://sourceforge.jp/projects/linux-kernel-docs/wiki/2.3%E3%80%80ハードウェア割り込み処理/attach/fig2-3.png)

## strct irq_desc

割り込みデスクリプタ

```c
/**
 * struct irq_desc - interrupt descriptor
 * @irq:		interrupt number for this descriptor
 * @timer_rand_state:	pointer to timer rand state struct
 * @kstat_irqs:		irq stats per cpu
 * @irq_2_iommu:	iommu with this irq
 * @handle_irq:		highlevel irq-events handler [if NULL, __do_IRQ()]
 * @chip:		low level interrupt hardware access
 * @msi_desc:		MSI descriptor
 * @handler_data:	per-IRQ data for the irq_chip methods
 * @chip_data:		platform-specific per-chip private data for the chip
 *			methods, to allow shared chip implementations
 * @action:		the irq action chain
 * @status:		status information
 * @depth:		disable-depth, for nested irq_disable() calls
 * @wake_depth:		enable depth, for multiple set_irq_wake() callers
 * @irq_count:		stats field to detect stalled irqs
 * @last_unhandled:	aging timer for unhandled count
 * @irqs_unhandled:	stats field for spurious unhandled interrupts
 * @lock:		locking for SMP
 * @affinity_notify:	context for notification of affinity changes
 * @affinity:		IRQ affinity on SMP
 * @node:		node index useful for balancing
 * @pending_mask:	pending rebalanced interrupts
 * @threads_active:	number of irqaction threads currently running
 * @wait_for_threads:	wait queue for sync_irq to wait for threaded handlers
 * @dir:		/proc/irq/ procfs entry
 * @name:		flow handler name for /proc/interrupts output
 */
struct irq_desc {
	unsigned int		irq;
	struct timer_rand_state *timer_rand_state;
	unsigned int            *kstat_irqs;
#ifdef CONFIG_INTR_REMAP
	struct irq_2_iommu      *irq_2_iommu;
#endif
	irq_flow_handler_t	handle_irq;
	struct irq_chip		*chip;
	struct msi_desc		*msi_desc;
	void			*handler_data;
	void			*chip_data;
	struct irqaction	*action;	/* IRQ action list */
	unsigned int		status;		/* IRQ status */

	unsigned int		depth;		/* nested irq disables */
	unsigned int		wake_depth;	/* nested wake enables */
	unsigned int		irq_count;	/* For detecting broken IRQs */
	unsigned long		last_unhandled;	/* Aging timer for unhandled count */
	unsigned int		irqs_unhandled;
	spinlock_t		lock;
#ifdef CONFIG_SMP
	cpumask_var_t		affinity;
	const struct cpumask	*affinity_hint;
	struct irq_affinity_notify *affinity_notify;
	unsigned int		node;
#ifdef CONFIG_GENERIC_PENDING_IRQ
	cpumask_var_t		pending_mask;
#endif
#endif
	atomic_t		threads_active;
	wait_queue_head_t       wait_for_threads;
#ifdef CONFIG_PROC_FS
	struct proc_dir_entry	*dir;
#endif
	const char		*name;
} ____cacheline_internodealigned_in_smp;
```

## 2.3.4 ハードウェア割り込みハンドラの登録

 * request_irq, free_irq については下記でまとめている
   * https://github.com/hiboma/kernel_module_scratch/tree/master/request_irq

## 2.3.5 ハードウェア割り込みの制御

 * CPUレベルで禁止
   * local_ の prefix がついているもの。SMP? (APIC)
 * 割り込みコントローラーで禁止

## local_irq_enable, local_irq_disable の中身

![](http://sourceforge.jp/projects/linux-kernel-docs/wiki/2.3%E3%80%80ハードウェア割り込み処理/attach/fig2-4.png)

```c
#define local_irq_enable() \
	do { trace_hardirqs_on(); raw_local_irq_enable(); } while (0)
#define local_irq_disable() \
	do { raw_local_irq_disable(); trace_hardirqs_off(); } while (0)
```

```c
static inline void raw_local_irq_disable(void)
{
	native_irq_disable();
}

static inline void raw_local_irq_enable(void)
{
	native_irq_enable();
}
```

cli, sti で ローカルCPU の EFLAGS の IFビットを操作

```c
static inline void native_irq_disable(void)
{
	asm volatile("cli": : :"memory");
}

static inline void native_irq_enable(void)
{
	asm volatile("sti": : :"memory");
}
```

## local_irq_save

```c
#define local_irq_save(flags)				\
	do {						\
		typecheck(unsigned long, flags);	\
		raw_local_irq_save(flags);		\
		trace_hardirqs_off();			\
	} while (0)
```

```c
#define raw_local_irq_save(flags)				\
	do { (flags) = __raw_local_irq_save(); } while (0)
```

__raw_local_save_flags で EFLAGS をコピーしてから raw_local_irq_disable で 割り込みを禁止する

```c
/*
 * For spinlocks, etc:
 */
static inline unsigned long __raw_local_irq_save(void)
{
	unsigned long flags = __raw_local_save_flags();

	raw_local_irq_disable();

	return flags;
}
```

local_save_flags も __raw_local_save_flags で EFLAGS の状態を取ってる

```c
static inline unsigned long __raw_local_save_flags(void)
{
	return native_save_fl();
}
```

 * pushf 命令で EFLAGS をスタックに退避 して pop して返している
 * 直接 EFLAGS を取る事はできないから?
```c
static inline unsigned long native_save_fl(void)
{
	unsigned long flags;

	/*
	 * "=rm" is safe here, because "pop" adjusts the stack before
	 * it evaluates its effective address -- this is part of the
	 * documented behavior of the "pop" instruction.
	 */
	asm volatile("# __raw_save_flags\n\t"
		     "pushf ; pop %0"
		     : "=rm" (flags)
		     : /* no input */
		     : "memory");

	return flags;
}
```

## local_irq_restore

```c
#define local_irq_restore(flags)			\
	do {						\
		typecheck(unsigned long, flags);	\
		if (raw_irqs_disabled_flags(flags)) {	\
			raw_local_irq_restore(flags);	\
			trace_hardirqs_off();		\
		} else {				\
			trace_hardirqs_on();		\
			raw_local_irq_restore(flags);	\
		}					\
	} while (0)
#else /* !CONFIG_TRACE_IRQFLAGS_SUPPORT */
```

```c
static inline void raw_local_irq_restore(unsigned long flags)
{
	native_restore_fl(flags);
}
```

スタックに push した内容を popf で EFLAGSレジスタに読み込むことで復帰

```c
static inline void native_restore_fl(unsigned long flags)
{
	asm volatile("push %0 ; popf"
		     : /* no output */
		     :"g" (flags)
		     :"memory", "cc");
}
```

## disable_irq

指定したIRQに対する割り込みを禁止する。割り込みが実行中であれば完了を同期的に待つ

```c
/**
 *	disable_irq - disable an irq and wait for completion
 *	@irq: Interrupt to disable
 *
 *	Disable the selected interrupt line.  Enables and Disables are
 *	nested.
 *	This function waits for any pending IRQ handlers for this interrupt
 *	to complete before returning. If you use this function while
 *	holding a resource the IRQ handler may need you will deadlock.
 *
 *	This function may be called - with care - from IRQ context.
 */
void disable_irq(unsigned int irq)
{
	struct irq_desc *desc = irq_to_desc(irq);

	if (!desc)
		return;

	disable_irq_nosync(irq);

    // desc->action が true なら IRQ実行中? ここで待つのかな?
	if (desc->action)
		synchronize_irq(irq);
}
EXPORT_SYMBOL(disable_irq);

void disable_irq_nosync(unsigned int irq)
{
	__disable_irq(irq);
}
EXPORT_SYMBOL(disable_irq_nosync);
```

synchronize_irq の中身

 * cpu_relax (nop命令を呼ぶ)
 * ビジーループで検査
 * struct irq_desc の .status から IRQ_INPROGRESS フラグが落ちるまで続く

```c
/**
 *	synchronize_irq - wait for pending IRQ handlers (on other CPUs)
 *	@irq: interrupt number to wait for
 *
 *	This function waits for any pending IRQ handlers for this interrupt
 *	to complete before returning. If you use this function while
 *	holding a resource the IRQ handler may need you will deadlock.
 *
 *	This function may be called - with care - from IRQ context.
 */
void synchronize_irq(unsigned int irq)
{
	struct irq_desc *desc = irq_to_desc(irq);
	unsigned int status;

	if (!desc)
		return;

	do {
		unsigned long flags;

		/*
		 * Wait until we're out of the critical section.  This might
		 * give the wrong answer due to the lack of memory barriers.
		 */
		while (desc->status & IRQ_INPROGRESS)
			cpu_relax();

		/* Ok, that indicated we're done: double-check carefully. */
		spin_lock_irqsave(&desc->lock, flags);
		status = desc->status;
		spin_unlock_irqrestore(&desc->lock, flags);

		/* Oops, that failed? */
	} while (status & IRQ_INPROGRESS);

	/*
	 * We made sure that no hardirq handler is running. Now verify
	 * that no threaded handlers are active.
	 */
    // ?
	wait_event(desc->wait_for_threads, !atomic_read(&desc->threads_active));
}
EXPORT_SYMBOL(synchronize_irq);
```

disable_irq で 割り込みが禁止される方法は irq_desc->chip ( struct irq_chip ) の .disable の実装による

```c
void __disable_irq(struct irq_desc *desc, unsigned int irq, bool suspend)
{
	if (suspend) {
		/* kABI WARNING! We cannot change IRQF_TIMER to include
		   IRQF_NO_SUSPEND. So test for both bits here. */
		if (!desc->action ||
		    (desc->action->flags & (IRQF_TIMER|IRQF_NO_SUSPEND)))
			return;
		desc->status |= IRQ_SUSPENDED;
	}

	if (!desc->depth++) {
		desc->status |= IRQ_DISABLED;
		desc->chip->disable(irq);
	}
}
```

struct irq_chip の中身。ハードウェア割り込みチップデスクリプタとな

```c
/**
 * struct irq_chip - hardware interrupt chip descriptor
 *
 * @name:		name for /proc/interrupts
 * @startup:		start up the interrupt (defaults to ->enable if NULL)
 * @shutdown:		shut down the interrupt (defaults to ->disable if NULL)
 * @enable:		enable the interrupt (defaults to chip->unmask if NULL)
 * @disable:		disable the interrupt (defaults to chip->mask if NULL)
 * @ack:		start of a new interrupt
 * @mask:		mask an interrupt source
 * @mask_ack:		ack and mask an interrupt source
 * @unmask:		unmask an interrupt source
 * @eoi:		end of interrupt - chip level
 * @end:		end of interrupt - flow level
 * @set_affinity:	set the CPU affinity on SMP machines
 * @retrigger:		resend an IRQ to the CPU
 * @set_type:		set the flow type (IRQ_TYPE_LEVEL/etc.) of an IRQ
 * @set_wake:		enable/disable power-management wake-on of an IRQ
 *
 * @bus_lock:		function to lock access to slow bus (i2c) chips
 * @bus_sync_unlock:	function to sync and unlock slow bus (i2c) chips
 *
 * @release:		release function solely used by UML
 * @typename:		obsoleted by name, kept as migration helper
 */
struct irq_chip {
	const char	*name;
	unsigned int	(*startup)(unsigned int irq);
	void		(*shutdown)(unsigned int irq);
	void		(*enable)(unsigned int irq);
	void		(*disable)(unsigned int irq);

	void		(*ack)(unsigned int irq);
	void		(*mask)(unsigned int irq);
	void		(*mask_ack)(unsigned int irq);
	void		(*unmask)(unsigned int irq);
	void		(*eoi)(unsigned int irq);

	void		(*end)(unsigned int irq);
	int		(*set_affinity)(unsigned int irq,
					const struct cpumask *dest);
	int		(*retrigger)(unsigned int irq);
	int		(*set_type)(unsigned int irq, unsigned int flow_type);
	int		(*set_wake)(unsigned int irq, unsigned int on);

	void		(*bus_lock)(unsigned int irq);
	void		(*bus_sync_unlock)(unsigned int irq);

	/* Currently used only by UML, might disappear one day.*/
#ifdef CONFIG_IRQ_RELEASE_METHOD
	void		(*release)(unsigned int irq, void *dev_id);
#endif
	/*
	 * For compatibility, ->typename is copied into ->name.
	 * Will disappear.
	 */
	const char	*typename;
};
```

### global_irq_cli

 * 2.6で廃止
   * どのCPUでも割り込みハンドラが実行されないことが保証
 * オーバーヘッドが大きい
 * スピンロックに書き換え

## 2.3.6 ハードウェア割り込みハンドラの起動

> Intel x86で割り込み発生時にdo_IRQ関数が呼び出されるようにするには、IDT（Interrupt Descriptor Table）と呼ばれるテーブルを適切に初期化しておく必要があります。

## 割り込みの初期化コード

x86
 * リアルモードだと 割り込みベクタ と呼ぶ
 * プロテクトモード IDT Interrupt Descriptor Table と呼ぶ

```asm
// linux-2.6.32-431.el6.x86_64/arch/x86/kernel/entry_32.S

/*
 * Build the entry stubs and pointer table with some assembler magic.
 * We pack 7 stubs into a single 32-byte chunk, which will fit in a
 * single cache line on all modern x86 implementations.
 */
.section .init.rodata,"a"
ENTRY(interrupt)
.text
	.p2align 5
	.p2align CONFIG_X86_L1_CACHE_SHIFT        // L1キャッシュに載るようにアライン?
ENTRY(irq_entries_start)                      // IRQ 割り込みベクタを定義するぞう
	RING0_INT_FRAME
vector=FIRST_EXTERNAL_VECTOR
.rept (NR_VECTORS-FIRST_EXTERNAL_VECTOR+6)/7  // ベクタの数分繰り返し
	.balign 32
  .rept	7
    .if vector < NR_VECTORS
      .if vector <> FIRST_EXTERNAL_VECTOR
	CFI_ADJUST_CFA_OFFSET -4
      .endif
1:	pushl $(~vector+0x80)	/* Note: always in signed byte range */
	CFI_ADJUST_CFA_OFFSET 4
      .if ((vector-FIRST_EXTERNAL_VECTOR)%7) <> 6
	jmp 2f
      .endif
      .previous
	.long 1b
      .text
vector=vector+1
    .endif
  .endr
2:	jmp common_interrupt                      // どの割り込みベクタも common_interrupt に jmp
.endr
END(irq_entries_start)

.previous
END(interrupt)
.previous
```

common_interrupt は do_IRQ への橋渡し

```asm
/*
 * the CPU automatically disables interrupts when executing an IRQ vector,
 * so IRQ-flags tracing has to follow that:
 */
	.p2align CONFIG_X86_L1_CACHE_SHIFT
common_interrupt:
	addl $-0x80,(%esp)	/* Adjust vector into the [-256,-1] range */
	SAVE_ALL              // 汎用レジスタの退避
	TRACE_IRQS_OFF
	movl %esp,%eax
	call do_IRQ
	jmp ret_from_intr
ENDPROC(common_interrupt)
	CFI_ENDPROC
```

### 例外 Exception

> このほか、割り込みによく似たものとして「例外」があります。割り込みが外的要因であるのに対し、CPUの動作自体によって引き起こされた事象の場合を「例外」と呼びます。

 * CPU内部で発生した事象
   * 0 除算, 数値演算例外, ページフォルト, ...
 * フォルト
 * トラップ
 * アボート

[例外と割り込み](https://github.com/hiboma/hiboma/blob/master/linux-0.0.1.md#例外割り込み) で復習しよう

`grep ^ENTRY arch/x86/kernel/` で割り込みベクタと例外の一覧を見る

#### 32bit

```asm
entry_32.S:ENTRY(ret_from_fork)
entry_32.S:ENTRY(resume_userspace)
entry_32.S:ENTRY(resume_kernel)n
entry_32.S:ENTRY(ia32_sysenter_target)         // sysenter でのシステムコール呼び出し?
entry_32.S:ENTRY(system_call)                  // 0x80 でのシステムコール呼び出し
entry_32.S:ENTRY(iret_exc)
entry_32.S:ENTRY(interrupt)                    // common_interrupt -> do_IRQ
entry_32.S:ENTRY(irq_entries_start)
entry_32.S:ENTRY(name)				
entry_32.S:ENTRY(coprocessor_error)
entry_32.S:ENTRY(simd_coprocessor_error)
entry_32.S:ENTRY(device_not_available)         // デバイス使用不可能例外
entry_32.S:ENTRY(native_iret)
entry_32.S:ENTRY(native_irq_enable_sysexit)
entry_32.S:ENTRY(overflow)
entry_32.S:ENTRY(bounds)
entry_32.S:ENTRY(invalid_op)
entry_32.S:ENTRY(coprocessor_segment_overrun)
entry_32.S:ENTRY(invalid_TSS)
entry_32.S:ENTRY(segment_not_present)
entry_32.S:ENTRY(stack_segment)
entry_32.S:ENTRY(alignment_check)
entry_32.S:ENTRY(divide_error)
entry_32.S:ENTRY(machine_check)
entry_32.S:ENTRY(spurious_interrupt_bug)
entry_32.S:ENTRY(kernel_thread_helper)
entry_32.S:ENTRY(xen_sysenter_target)
entry_32.S:ENTRY(xen_hypervisor_callback)
entry_32.S:ENTRY(xen_do_upcall)
entry_32.S:ENTRY(xen_failsafe_callback)
entry_32.S:ENTRY(mcount)
entry_32.S:ENTRY(ftrace_caller)
entry_32.S:ENTRY(mcount)
entry_32.S:ENTRY(ftrace_graph_caller)
entry_32.S:ENTRY(page_fault)                   // ページフォルト
entry_32.S:ENTRY(debug)
entry_32.S:ENTRY(nmi)                          // NMI 
entry_32.S:ENTRY(int3)                         // ブレークポイント
entry_32.S:ENTRY(general_protection)
```

#### 64bit 

```asm
entry_64.S:ENTRY(mcount)
entry_64.S:ENTRY(ftrace_caller)
entry_64.S:ENTRY(mcount)
entry_64.S:ENTRY(ftrace_graph_caller)
entry_64.S:ENTRY(native_usergs_sysret64)
entry_64.S:ENTRY(save_args)
entry_64.S:ENTRY(save_rest)
entry_64.S:ENTRY(save_paranoid)
entry_64.S:ENTRY(ret_from_fork)
entry_64.S:ENTRY(system_call)
entry_64.S:ENTRY(system_call_after_swapgs)
entry_64.S:ENTRY(\label)
entry_64.S:ENTRY(ptregscall_common)
entry_64.S:ENTRY(stub_execve)
entry_64.S:ENTRY(stub_rt_sigreturn)
entry_64.S:ENTRY(interrupt)
entry_64.S:ENTRY(irq_entries_start)
entry_64.S:ENTRY(native_iret)
entry_64.S:ENTRY(retint_kernel)
entry_64.S:ENTRY(\sym)
entry_64.S:ENTRY(\sym)
entry_64.S:ENTRY(\sym)
entry_64.S:ENTRY(\sym)
entry_64.S:ENTRY(\sym)
entry_64.S:ENTRY(\sym)
entry_64.S:ENTRY(native_load_gs_index)
entry_64.S:ENTRY(kernel_thread)
entry_64.S:ENTRY(child_rip)
entry_64.S:ENTRY(kernel_execve)
entry_64.S:ENTRY(call_softirq)
entry_64.S:ENTRY(xen_do_hypervisor_callback)   # do_hypervisor_callback(struct *pt_regs)
entry_64.S:ENTRY(xen_failsafe_callback)
entry_64.S:ENTRY(paranoid_exit)
entry_64.S:ENTRY(error_entry)
entry_64.S:ENTRY(error_exit)
entry_64.S:ENTRY(nmi)
entry_64.S:ENTRY(ignore_sysret)
```

## do_IRQ

 * struct irq_desc 割り込みデスクリプタ
 * struct irqaction
   * irqaction->handler() が 割り込みハンドラ

```c
fastcall unsigned int do_IRQ(struct pt_regs *regs)
{
        // EAX 下位 8 ビットに IRQ番号が入ってる?
        // 上位ビットは関係無い
        int irq = regs->orig_eax & 0xff; // ――<1>
        // プリエンプション禁止
        // add_preempt_count(HARDIRQ_OFFSET)
        irq_enter(); // ――<2>
        __do_IRQ(irq, regs);
        irq_exit(); // ――<3>
        return 1;
}

fastcall unsigned int __do_IRQ(unsigned int irq, struct pt_regs *regs)
{
        // irq_desc はグローバル変数の配列
        // irq インデックスにして irq_desc_t を求める
        irq_desc_t *desc = irq_desc + irq; ――<4>
        struct irqaction * action;
        unsigned int status;

        kstat_this_cpu.irqs[irq]++;
        // ? CPUごとに発生?
        // 排他制御がいらない
        if (CHECK_IRQ_PER_CPU(desc->status)) {

                irqreturn_t action_ret;
                // ACK を返す実装があるか否か
                if (desc->handler->ack)
                        desc->handler->ack(irq);
                action_ret = handle_IRQ_event(irq, regs, desc->action); ――<5>
                // IRQ 終わり
                desc->handler->end(irq);
                return 1;
        }

        spin_lock(&desc->lock);
        // ACK を出して 割り込み可能であることをコントローラに伝える
        // ただし 同じIRQ の割り込みは発生しない
        if (desc->handler->ack)
                desc->handler->ack(irq); ――<6>

        status = desc->status & ~(IRQ_REPLAY | IRQ_WAITING);

        // 割り込み保留のフラグ
        status |= IRQ_PENDING; ――<7>

        action = NULL;

        // IRQ を実行可能かどうか?
        if (likely(!(status & (IRQ_DISABLED | IRQ_INPROGRESS)))) {
                // IRQ_PENDING を外して、 割り込み実行中の IRQ_INPROGRESS を立てる
                action = desc->action;
                status &= ~IRQ_PENDING;
                // IRQ を実行可能に入る
                status |= IRQ_INPROGRESS; ――<8>
        }
        // IRQ デスクリプタい IRQ_PENDING をたてておく
        // desc はグローバルにシェアされているので要 spin_lock
        desc->status = status; ――<9>

        // 別の CPU で IRQ を実行中なので 任せて終わる
        // IRQ_PENDING の有無で判定できる
        if (unlikely(!action)) ――<10>
                goto out;

        // 他の CPU が IRQ_INPROGRESS を立てる可能性があるので
        // 全部終わるまでループ
        for (;;) {
                irqreturn_t action_ret;

                spin_unlock(&desc->lock);

                action_ret = handle_IRQ_event(irq, regs, action); ――<11>

                spin_lock(&desc->lock);
                if (!noirqdebug)
                        note_interrupt(irq, desc, action_ret, regs);

                // ペンディングされている IRQ がいるので、再度ループしてやっつける
                if (likely(!(desc->status & IRQ_PENDING))) ――<12>
                        break;
                desc->status &= ~IRQ_PENDING;
        }
        desc->status &= ~IRQ_INPROGRESS; ――<13>

out:
        desc->handler->end(irq); ――<14>
        spin_unlock(&desc->lock);

        return 1;
}

fastcall int handle_IRQ_event(unsigned int irq, struct pt_regs *regs, struct irqaction *action)
{
        int ret, retval = 0, status = 0;

        // 割り込みハンドラ実行中でも 割り込みを受け付ける = SA_INTERRUPT
        if (!(action->flags & SA_INTERRUPT))
                local_irq_enable(); ――<20>

        do {
                // irqaction のハンドラ実行
                // request_irq で登録されたハンドラ
                ret = action->handler(irq, action->dev_id, regs);――<21>
                if (ret == IRQ_HANDLED)
                        status |= action->flags;
                retval |= ret;
                // IRQ を share している場合?
                action = action->next;
        } while (action);

        if (status & SA_SAMPLE_RANDOM)
                add_interrupt_randomness(irq);――<22>
        local_irq_disable();――<23>

        return retval;
}
```