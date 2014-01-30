
## vagrant で シリアルコンソール

 * Vagrantfile

```ruby
  config.vm.provider :virtualbox do |vb|
    # vb.gui = true
    # http://en.wikipedia.org/wiki/COM_(hardware_interface)
    # I/O port と IRQ
    vb.customize ["modifyvm", :id, "--uart1", "0x3F8", "4"]
    vb.customize ["modifyvm", :id, "--uartmode1", "server", "/tmp/machine1.sock"]
  end
```

 * ゲストOSの /etc/grub/conf をちょちょいといじる

```
console=tty console=ttyS0,9600
```

ホストOS (Mac) から以下のコマンドで繋げる

```
nc -U /tmp/machine1.sock
```

## Vagrant のネットワークアダプタを変える

 * CentOS6.5のデフォルトのアダプタは virio-net (準仮想化ネットワーク) に調整されていた
   * 意図して変える場合

```ruby
    vb.customize ["modifyvm", :id, "--nictype1", "82540EM"]
```

 * /proc/interrupts で eth0 からの割り込みの様子を確認できる。
   * I/O APIC がまず割り込みを受けてることが分かる?

```
[vagrant@vagrant-centos65 ~]$ fgrep eth0 /proc/interrupts
 19:        796          0   IO-APIC-fasteoi   eth0
```

http://vboxmania.net/content/ネットワーク設定 当たりを参照するとよろし

## APIC

 * ___Local APIC___
   * CPUごとの割り込みコントローラー
 * ___I/O APIC___
   * 外部デバイスに繋がった割り込みコントローラー。Local APIC に割り込みを転送(リダイレクションする)
 * APIC + I/O APIC = マルチAPICシステム
 * SMPアーキテクチャ
   * 複数のCPUに割り込みを分配する必要がある
   * プロセッサ間割り込み (InterProcessor Interrput = IPI) を生成できる
     * 送り元 `CPU => ローカルAPIC == バス ==> ローカルAPIC => ターゲットCPU`

/var/log/messages に I/O APIC を割り込みのルーティング(転送?) に使用するとのログがでる

```
Jan 28 12:40:21 vagrant-centos65 kernel: ACPI: Using IOAPIC for interrupt routing
```

I/O APIC から Local APIC への割り込みの分配が均等に行われることを指すのだろうか?

```
Jan 28 12:40:21 vagrant-centos65 kernel: Setting APIC routing to flat.
Jan 28 12:40:21 vagrant-centos65 kernel: Setting APIC routing to flat.
```

I/O APIC を使わないと SMP が無効になったとのログがでる

```
Jan 28 12:34:27 vagrant-centos65 kernel: SMP: Allowing 1 CPUs, 0 hotplug CPUs
Jan 28 12:34:27 vagrant-centos65 kernel: SMP alternatives: switching to UP code
Jan 28 12:34:27 vagrant-centos65 kernel: Freeing SMP alternatives: 36k freed
Jan 28 12:34:27 vagrant-centos65 kernel: SMP motherboard not detected.
Jan 28 12:34:27 vagrant-centos65 kernel: SMP disabled
```

IO APIC にもいろいろ種類がある様子

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

#### TSC Time Stamp Counter

 * [access.redhat.com 15.1. ハードウェアクロック](https://access.redhat.com/site/documentation/ja-JP/Red_Hat_Enterprise_MRG/2/html/Realtime_Reference_Guide/chap-Realtime_Reference_Guide-Timestamping.html)
   * クロックソース
 * http://msmania.wordpress.com/tag/rdtsc/
   * プロセッサごとに用意されてるレジスタ
   * 高速な理由

> それが、RDTSC (=Read Time Stamp Counter) 命令です。詳細は IA-32 の仕様書に書いてありますが、RDTSC を実行すると、1 命令で Tick 値を取得することができます。
> しかも単位はクロック単位です。Pentium 以降の IA-32 アーキテクチャーでは、プロセッサーごとに TSC (=Time Stamp Counter) という 64bit カウンターが MSR (マシン固有レジスタ) に含まれており、RDTSC はこれを EDX:EAX レジスターにロードする命令です。

/var/log/messages に TSC の同期を試みるログが出る

```
Jan 28 12:40:21 vagrant-centos65 kernel: TSC synchronization [CPU#0 -> CPU#1]:
Jan 28 12:40:21 vagrant-centos65 kernel: Measured 1826989 cycles TSC warp between CPUs, turning off TSC clock.
Jan 28 12:40:21 vagrant-centos65 kernel: Marking TSC unstable due to check_tsc_sync_source failed
```

```
/**
 * setup_local_APIC - setup the local APIC
 */
void __cpuinit setup_local_APIC(void)
```

SMPを無効にする場合 I/O APIC のセットアップがスキップされる

```c
void arch_disable_smp_support(void)
{
#ifdef CONFIG_PCI
	noioapicquirk = 1;
	noioapicreroute = -1;
#endif
	skip_ioapic_setup = 1;
}
```

```c
void __init setup_IO_APIC(void)
{

	/*
	 * calling enable_IO_APIC() is moved to setup_local_APIC for BP
	 */
	io_apic_irqs = nr_legacy_irqs ? ~PIC_IRQS : ~0UL;

	apic_printk(APIC_VERBOSE, "ENABLING IO-APIC IRQs\n");
	/*
         * Set up IO-APIC IRQ routing.
         */
	x86_init.mpparse.setup_ioapic_ids();

	sync_Arb_IDs();
	setup_IO_APIC_irqs();
	init_IO_APIC_traps();
	if (nr_legacy_irqs)
		check_timer();
}
```

## プロセッサの数を取る

```
export MAKEFLAGS="-j $( getconf _NPROCESSORS_ONLN )"
```

もじゃの人から拝借。便利

## vagrant ssh-config を Tempfile に書き出して ssh -F で vagrant に接続

```ruby
ssh_config = Tempfile.new('nukofs-ssh-config')
ssh_config.write(`vagrant ssh-config`)
ssh_config.close
at_exit { ssh_config.unlink } 

guard 'shell' do 
  watch("nukofs.c") do
    puts "Building module ..."
    `time ssh -F #{ssh_config.path} default -- sudo /vagrant/script/make-and-make-test.sh`
  end 
end
```

 * 2-3秒しか変わらんかった。 make/テストケースの実行 が短いと快適かもしれない
 * make/テストの時間が長くなってきたら対して差を感じないはず

## ext4 の unlink と journal

```
# cat /proc/19439/stack
[<ffffffffa00144c8>] __jbd2_log_wait_for_space+0xc8/0x1b0 [jbd2]
[<ffffffffa000ff3d>] start_this_handle+0x10d/0x480 [jbd2]
[<ffffffffa0010495>] jbd2_journal_start+0xb5/0x100 [jbd2]
[<ffffffffa0051236>] ext4_journal_start_sb+0x56/0xe0 [ext4]
[<ffffffffa0041f9d>] ext4_unlink+0x9d/0x2b0 [ext4]
[<ffffffff8118fe60>] vfs_unlink+0xa0/0xf0
[<ffffffff81192205>] do_unlinkat+0xf5/0x1b0
[<ffffffff811922d6>] sys_unlink+0x16/0x20
[<ffffffff8100b288>] tracesys+0xd9/0xde
[<ffffffffffffffff>] 0xffffffffffffffff
``` 

## udevadm

```
# udevadm info --query=all --name=/dev/sda
P: /devices/platform/host0/session1/target0:0:0/0:0:0:0/block/sda
N: sda
W: 38
S: block/8:0
S: disk/by-id/*
S: disk/by-path/*:*.com.amazon:*
E: UDEV_LOG=3
E: DEVPATH=/devices/platform/host0/session1/target0:0:0/0:0:0:0/block/sda
E: MAJOR=8
E: MINOR=0
E: DEVNAME=/dev/sda
E: DEVTYPE=disk
E: SUBSYSTEM=block
E: ID_SCSI=1
E: ID_VENDOR=Amazon
E: ID_VENDOR_ENC=Amazon\x20\x20
E: ID_MODEL=Storage_Gateway
E: ID_MODEL_ENC=Storage\x20Gateway\x20
E: ID_REVISION=1.0
E: ID_TYPE=disk
E: ID_SERIAL_RAW=*
E: ID_SERIAL=*
E: ID_SERIAL_SHORT=*
E: ID_SCSI_SERIAL=*
E: ID_BUS=scsi
E: ID_PATH=*.com.amazon:*
E: ID_PART_TABLE_TYPE=gpt
E: DEVLINKS=/dev/block/8:0 /dev/disk/by-id/scsi-* /dev/disk/by-path/*.com.amazon:*
```

[refs](http://docs.oracle.com/cd/E39368_01/e48214/ch07s04.html)

### todo

 * remount とブロック
   * lock_kernel();
   * sb_down
 * syn flooding
 * SCSI のドライブレター
