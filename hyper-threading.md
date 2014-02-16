Amazon Linux のマイクロインスタンスを複数作ったらどうも /proc/cpuinfo の出力が違うというネタ

## 何が違うのか

具体的な違いは ___physical id, cpu cores, siblings___ などの行が出力されるかどうかの違いでした

 * とあるインスタンス

```
$ cat /proc/cpuinfo 
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 23
model name	: Intel(R) Xeon(R) CPU           E5430  @ 2.66GHz
stepping	: 10
microcode	: 0xa07
cpu MHz		: 2660.000
cache size	: 6144 KB
fpu		: yes
fpu_exception	: yes
cpuid level	: 13
wp		: yes
flags		: fpu de tsc msr pae cx8 sep cmov pat clflush mmx fxsr sse sse2 ss ht syscall nx lm constant_tsc up rep_good nopl pni ssse3 cx16 sse4_1 hypervisor lahf_lm
bogomips	: 5320.00
clflush size	: 64
cache_alignment	: 64
address sizes	: 38 bits physical, 48 bits virtual
power management:
```

 * とあるインスタンス2

```
$ cat /proc/cpuinfo 
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 44
model name	: Intel(R) Xeon(R) CPU           E5645  @ 2.40GHz
stepping	: 2
microcode	: 0x10
cpu MHz		: 2000.070
cache size	: 12288 KB
physical id	: 0
siblings	: 1
core id		: 0
cpu cores	: 1
apicid		: 0
initial apicid	: 4
fpu		: yes
fpu_exception	: yes
cpuid level	: 11
wp		: yes
flags		: fpu de tsc msr pae cx8 sep cmov pat clflush mmx fxsr sse sse2 ss ht syscall nx lm constant_tsc up rep_good nopl nonstop_tsc pni pclmulqdq ssse3 cx16 pcid sse4_1 sse4_2 popcnt aes hypervisor lahf_lm
bogomips	: 4000.14
clflush size	: 64
cache_alignment	: 64
address sizes	: 40 bits physical, 48 bits virtual
power management:
```

違う

## 結論

結論を先に言うと

 *  それぞれのインスタンスのホストOSのCPUが異なっている
 * CPUがハイパースレッディングをサポートしているかどうか

の二つの影響でした。 ___physical id, siblings, core id, cpu cores, apicid, initial apicid___ の行はハイパースレッディングが有効な場合に出力されます。

## ソース

とまぁ 疑問は解決したのですが、どういう仕組みになってるのかソースも追いかけてみました。参照したバージョンはバニラカーネルの 3.2.27 です。

## /proc/cpuinfo の該当部分を出力するソース

"cpu cores:" で grep すると procfs に出力するコードが引っかかります。

 * arch/x86/kernel/cpu/proc.c
 
```c
/*
 *      Get CPU information for use by the procfs.
 */
static void show_cpuinfo_core(struct seq_file *m, struct cpuinfo_x86 *c, 
                              unsigned int cpu)
{
#ifdef CONFIG_SMP
        if (c->x86_max_cores * smp_num_siblings > 1) {
                seq_printf(m, "physical id\t: %d\n", c->phys_proc_id);
                seq_printf(m, "siblings\t: %d\n",
                           cpumask_weight(cpu_core_mask(cpu)));
                seq_printf(m, "core id\t\t: %d\n", c->cpu_core_id);
                seq_printf(m, "cpu cores\t: %d\n", c->booted_cores);
                seq_printf(m, "apicid\t\t: %d\n", c->apicid);
                seq_printf(m, "initial apicid\t: %d\n", c->initial_apicid);
        }   
#endif
}
```

`if ( c->x86_max_cores * smp_num_sibling > 1` が肝となる条件ですが、何を指す変数かよく分かりません。
とにもかくにもハイパースレッディングが有効な場合は、ここの結果が 1 以上になるようです。

## c->x86_max_cores の初期化

`c->x86_max_cores` は `intel_num_cpu_cores()` で初期化されています。

*
arch/x86/kernel/cpu/intel.c 
```c
                c->x86_max_cores = intel_num_cpu_cores(c);
```

```c
/*
 * find out the number of processor cores on the die
 */
static int __cpuinit intel_num_cpu_cores(struct cpuinfo_x86 *c) 
{
        unsigned int eax, ebx, ecx, edx;

        if (c->cpuid_level < 4)
                return 1;

        /* Intel has a non-standard dependency on %ecx for this CPUID level. */
        cpuid_count(4, 0, &eax, &ebx, &ecx, &edx);
        if (eax & 0x1f)
                return (eax >> 26) + 1;
        else
                return 1;
}
```

`cpuid_count()` を呼び出していますが、これはインラインアセンブラで `cpuid` という命令を呼び出す実装になっています。


## cpuid 命令とは

cpuid の使い方の仕様は Intel のマニュアルに書いてあります。CPUの情報を取る命令のようです。

 * http://www.intel.com/content/dam/www/public/us/en/documents/application-notes/processor-identification-cpuid-instruction-note.pdf
 * http://www.intel.co.jp/content/dam/www/public/ijkk/jp/ja/documents/developer/Processor_Identification_071405_i.pdf
   * 2005年と古いけど日本語

`eax = 4` を指定して cpuid を呼び出すと、 eax の 31~26bit に ダイ上のプロセッサ・コアの数(マルチコア) が 入ると書いてありました。

`c->x86_max_cores`  は 物理コア数を指す変数と分かりました。

## smp_num_siblings の初期化

`smp_num_siblings` は arch/x86/kernel/cpu/common.c の `detect_ht()` の中で初期化されます。

```c
void __cpuinit detect_ht(struct cpuinfo_x86 *c)
{
        /* 略 */

       // eax = 1 で cpuid命令 を呼ぶ
        cpuid(1, &eax, &ebx, &ecx, &edx);

        // ebx のレジスタ 23~16 bit に Hyper Threading の数が入ってる
        smp_num_siblings = (ebx & 0xff0000) >> 16;

        if (smp_num_siblings == 1) {
                printk_once(KERN_INFO "CPU0: Hyper-Threading is disabled\n");
                goto out;
        }

        if (smp_num_siblings <= 1)
                goto out;

        /* 略 */

       // ハイパースレッディングで1コアあたりの並列数を出す? 
        smp_num_siblings = smp_num_siblings / c->x86_max_cores;

        /* 略 */
}
```

Inetel のリファレンスには `eax = 1` にして cpuid を呼び出すと ebx の 23-16bitに 論理プロセッサの数 が入ると書いてあります。(ただし、CPUがハイパースレッディングに対応している場合にのみ取れる数値とのこと)

cpuid で論理プロセッサの数を取得した後、 `smp_num_siblings` を 物理コア数 `c->x86_max_cores` で除算しています。これによって `smp_num_siblings`  は 物理コア1個あたりが論理CPUとして何個に見えるか、を指す数字として扱われていると分かりました。


## まとめ

 * c->x86_max_cores は物理コアの数
 * smp_num_siblings はハイパースレッディングによる1物理コアあたりの論理CPUの数
 * c->x86_max_cores * smp_num_siblings > 1 であれば ハイパースレッディングが有効である、と見なせる

というまとめになります。

## 課題

ここまでまとめておいたところで、AWSのインスタンスは64bitなのに、Intelのリファレンスは IA-32 (32bit)のアーキテクチャの説明だった気がつきました。とほほ。

## 参考にしたブログ

 * http://d.hatena.ne.jp/ruicc/20090212/1234455865
 * http://piro791.blog.so-net.ne.jp/2008-09-30-3
 * http://open-groove.net/linux/cpu-core-hyper-threading/