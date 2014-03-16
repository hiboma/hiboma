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

#### 割り込みベクタの初期化コード   

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

#### 例外 Exception

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

## 2.3.2 ハードウェア割り込み処理の動作例

![](http://sourceforge.jp/projects/linux-kernel-docs/wiki/2.3%E3%80%80ハードウェア割り込み処理/attach/fig2-2.png)

### 受信処理

#### 1. socket に read, recv, recvfrom, recvmsg を呼び TASK_INTERRUPTIBLE で待つ

#### PF_INET + TCP (tcp_proto + inet_stream_ops ) recvfrom の場合のスタック

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

ネットワークカードの割り込みベクタは 19 ぽい

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

VirtualBox は virio-net  

#### 5. net_rx_action

 * softirq ハンドラが起動するタイミングが分からない
 * process_backlog -> __skb_dequeue -> __netif_receive_skb ->  deliver_skb
   * struct packet_type のハンドラを呼んでプロトコルのハンドラへ委譲
   * TASK_INTERRUPTIBLE なプロセスを起床させる箇所が分からん

#### 6. プロセスが起床してシステムコール呼び出し元に戻る
 
