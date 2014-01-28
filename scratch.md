
## APIC

 * Local APIC
   * CPUごとの割り込みコントローラー
 * I/O APIC
   * 外部デバイスに繋がった割り込みコントローラー。Local APIC に割り込みを転送(リダイレクションする)
 * APIC + I/O APIC = マルチAPICシステム
 * SMPアーキテクチャ
   * 複数のCPUに割り込みを分配する


### TSC Time Stamp Counter

 * [access.redhat.com 15.1. ハードウェアクロック](https://access.redhat.com/site/documentation/ja-JP/Red_Hat_Enterprise_MRG/2/html/Realtime_Reference_Guide/chap-Realtime_Reference_Guide-Timestamping.html)
   * クロックソース
 * http://msmania.wordpress.com/tag/rdtsc/
   * プロセッサごとに用意されてるレジスタ
   * 高速な理由

> それが、RDTSC (=Read Time Stamp Counter) 命令です。詳細は IA-32 の仕様書に書いてありますが、RDTSC を実行すると、1 命令で Tick 値を取得することができます。
> しかも単位はクロック単位です。Pentium 以降の IA-32 アーキテクチャーでは、プロセッサーごとに TSC (=Time Stamp Counter) という 64bit カウンターが MSR (マシン固有レジスタ) に含まれており、RDTSC はこれを EDX:EAX レジスターにロードする命令です。

```
/**
 * setup_local_APIC - setup the local APIC
 */
void __cpuinit setup_local_APIC(void)
```

 * SMPを無効にする場合 I/O APIC のセットアップがスキップされる

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
 