## 2.1 割り込み処理とは

> 伝統的なUNIXの方式を採用せず

> 2.6では、古いデバイスドライバに対応するために残されていた旧式の機能も削られ

>　入出力処理中のプロセスは、割り込みによって、入出力完了が通知されるまで実行権を手放します。対話型プロセスの場合は、端末から入力割り込みがあるまで、待機状態を続けます。

 * wait_on_buffer
 * n_tty_read
 * poll_schedule_timeout

```
[vagrant@vagrant-centos65 ~]$ cat /proc/interrupts 
           CPU0       
  0:        168   IO-APIC-edge      timer
  1:          7   IO-APIC-edge      i8042
  4:         95   IO-APIC-edge      serial
  8:          0   IO-APIC-edge      rtc0
  9:          0   IO-APIC-fasteoi   acpi
 12:        108   IO-APIC-edge      i8042
 19:       4851   IO-APIC-fasteoi   virtio0
 20:       1961   IO-APIC-fasteoi   vboxguest
 21:      26797   IO-APIC-fasteoi   ahci
NMI:          0   Non-maskable interrupts
LOC:      57663   Local timer interrupts
SPU:          0   Spurious interrupts
PMI:          0   Performance monitoring interrupts
IWI:          0   IRQ work interrupts
RES:          0   Rescheduling interrupts
CAL:          0   Function call interrupts
TLB:          0   TLB shootdowns
TRM:          0   Thermal event interrupts
THR:          0   Threshold APIC interrupts
MCE:          0   Machine check exceptions
MCP:         10   Machine check polls
ERR:          0
MIS:          0
```
 