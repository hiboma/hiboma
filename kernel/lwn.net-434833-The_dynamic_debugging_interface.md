# The dynamic debugging interface

 * https://lwn.net/Articles/434833/
 * 意訳だからね

## dynamic debugging interface

 * 2.6.39 でマイナーチェンジ
 * 今まで LWN でも取り上げてなかった仕組みについて説明よ

----

 #デバッグあるある 的な話

 * カーネルの挙動調べるのに print 埋めまくるよね
 * 大半の出力は興味無いもの
 * 大概はコメントアウトしておけるものだけど、 edit/rebuild/reboot するサイクルの時は必要な時がある
 * で、ランタイムで enable/disable する仕組みが幾多の開発者によって作られたのであった

## dynamic debugging interface で統一的なインタフェース

```c
    pr_debug(char *format, ...);
    dev_dbg(struct device *dev, char *format, ...);
```

上記のコードについて

 * CONFIG_DYNAMIC_DEBUG がセットされてない場合
   * printk + KERN_DEBUG になる
 * CONFIG_DYNAMIC_DEBUG がセットされている場合
   * 特別なデスクリプタをセットする
     * モジュール, function, ファイル名, 行数
   * ブート時にはオフになってる
   * でバッグメッセージが syslogd daemon にとんでっても出力されない

CentOS6.5 では CONFIG_DYNAMIC_DEBUG=y でビルドされている     

```     
[vagrant@vagrant-centos65 ~]$ grep CONFIG_DYNAMIC_DEBUG /boot/*
/boot/config-2.6.32-431.el6.x86_64:CONFIG_DYNAMIC_DEBUG=y
```     

## /sys/kernel/debug/dynamic_debug/control
 
 * `/sys/kernel/debug/dynamic_debug/control` に enable/disable したいデバッグ関数を write する

```c
        /* drivers/char/tpm/tpm_nsc.c#346 */
        dev_dbg(&pdev->dev, "NSC TPM detected\n");
```

↑のデバッグを取るには↓のように書く


```sh
    echo file tpm_nsc.c line 346 +p > .../dynamic_debug/control
```    

↓ みたいに書いても動くらしい

```sh
    echo file tpm_nsc.c line 346-373 +p > .../dynamic_debug/control
    echo file tpm_nsc.c function init_nsc +p > .../dynamic_debug/control
```

以下のデスクリプタ(site?)で enable/disable できるらしい

 * ファイル名
 * 行数
 * 関数名
 * `module name`
 * `format fmt` (一致するフォーマット)

read すると enable/disable 切り替えられる一覧でてくる

```
[vagrant@vagrant-centos65 ~]$ cat /sys//kernel/dynamic_debug/control 
# filename:lineno [module]function flags format
arch/x86/kernel/tboot.c:101 [tboot]tboot_probe - "tboot_size: 0x%x\012"
arch/x86/kernel/tboot.c:100 [tboot]tboot_probe - "tboot_base: 0x%08x\012"
arch/x86/kernel/tboot.c:99 [tboot]tboot_probe - "shutdown_entry: 0x%x\012"
arch/x86/kernel/tboot.c:98 [tboot]tboot_probe - "log_addr: 0x%08x\012"
arch/x86/kernel/tboot.c:97 [tboot]tboot_probe - "version: %d\012"
arch/x86/kernel/cpu/common.c:1241 [common]cpu_init - "Initializing CPU#%d\012"
arch/x86/kernel/cpu/perfctr-watchdog.c:249 [perfctr_watchdog]write_watchdog_counter - "setting %s to -0x%08Lx\012"
arch/x86/kernel/cpu/perfctr-watchdog.c:260 [perfctr_watchdog]write_watchdog_counter32 - "setting %s to -0x%08Lx\012"
arch/x86/kernel/acpi/boot.c:968 [boot]mp_config_acpi_legacy_irqs - "Bus #%d is ISA\012"
arch/x86/kernel/smpboot.c:1235 [smpboot]native_smp_cpus_done - "Boot done.\012"
arch/x86/kernel/smpboot.c:532 [smpboot]impress_friends - "Before bogocount - setting activated=1.\012"
arch/x86/kernel/smpboot.c:522 [smpboot]impress_friends - "Before bogomips.\012"
arch/x86/kernel/smpboot.c:972 [smpboot]native_cpu_up - "do_boot_cpu failed %d\012"
arch/x86/kernel/smpboot.c:957 [smpboot]native_cpu_up - "do_boot_cpu %d Already started\012"
arch/x86/kernel/smpboot.c:945 [smpboot]native_cpu_up - "++++++++++++++++++++=_---CPU UP  %u\012"
arch/x86/kernel/smpboot.c:895 [smpboot]do_boot_cpu - "CPU%d: has booted.\012"
arch/x86/kernel/smpboot.c:874 [smpboot]do_boot_cpu - "After Callout %d.\012"
arch/x86/kernel/smpboot.c:872 [smpboot]do_boot_cpu - "Before Callout %d.\012"
arch/x86/kernel/smpboot.c:847 [smpboot]do_boot_cpu - "Setting warm reset code and vector.\012"
/builddir/build/BUILD/kernel-2.6.32-431.el6/linux-2.6.32-431.el6.x86_64/arch/x86/include/asm/smpboot_hooks.h:21 [smpboot]smpboot_setup_warm_reset_vector - "3.\012"
```

## flags

 * **+p** で printk をオンにする
 * **-p** で printk をオフにする
 * **f** 出力に関数名を足す
 * **l** 出力に行数を足す
 * **m** 出力にモジュール名を足す
 * **t** 出力にスレッドIDを足す

**=plm** と書く事で マスクしたフラグを指定できる。 **-pflmt** で全部のフラグをクリアする

## ddebug_query

ブートパラメータに `ddebug_query` を入れとくと初期ブートプロセスのデバッグ出力を取れる

## 詳細

[Documentation/dynamic-debug-howto.txt](https://lwn.net/Articles/434856/) を読むと良い

## まとめ
 
2.6.30 からある仕組みけど、お手製のデバッグコードがまだある。 dynamic-debug を使おう！的な啓蒙でおしまい