# 2.3 ハードウェア割り込み処理

## 2.3.1 割り込みの種類

#### 割り込み Intterupt

![](http://sourceforge.jp/projects/linux-kernel-docs/wiki/2.3%E3%80%80ハードウェア割り込み処理/attach/fig2-1.png)

 * External Interruputs 外部デバイスの割り込み
   * ネットワークカード、端末装置、SCSIホストアダプタ
 * IPI = Inter Processor Interrupts プロセッサ間割り込み
 * タイマー割り込み
   * ローカルタイマー
     * APIC ? 
   * グローバルタイマー
 * NMI = Non Maskable Interrupts
   * ハードウェアの故障などの通知
p
#### 例外 Exception

> このほか、割り込みによく似たものとして「例外」があります。割り込みが外的要因であるのに対し、CPUの動作自体によって引き起こされた事象の場合を「例外」と呼びます。

 * CPU内部で発生した事象
   * 0 除算, 数値演算例外, ページフォルト, ...
 * フォルト
 * トラップ
 * アボート

[例外と割り込み](https://github.com/hiboma/hiboma/blob/master/linux-0.0.1.md#例外割り込み) で復習しよう

#### `grep ^ENTRY arch/x86/kernel/` で例外の一覧を取れる

32bit

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

64bit 

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