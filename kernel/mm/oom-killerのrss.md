# OOM Killer の rss フィールド

 * OOM Killer が起動した際に、各プロセスの RSS の量が吐出される
 * RSS には、 CoW で共有しているものも含まれる
 * よって、RSS の総和と、RAM の総量が一致しない

## 検証用コード

適当に Ruby でこさえたもの

prefork サーバを擬似的に真似たマルチプロセススクリプト

 * 複数の子プロセスを生やす
 * 小プロセスと CoW で大きいデータを共有する
 * 親プロセスが OOM を起こす

```ruby
#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

datum = []
datum.push("@" * 500000000)

1.upto(20) do
  Process.fork {
    sleep 1000
  }
end

loop {
  datum.push("@" * 100000)
}
```

## OOM Killer のログ

#### CentOS 6.6

下記のようなログが出る

```
Mar  8 11:35:04 vagrant-centos65 kernel: Out of memory (oom_kill_allocating_task): Kill process 6608 (top) score 0 or sacrifice child
Mar  8 11:35:04 vagrant-centos65 kernel: Killed process 6608, UID 500, (top) total-vm:15028kB, anon-rss:308kB, file-rss:4kB
Mar  8 11:36:09 vagrant-centos65 kernel: ruby invoked oom-killer: gfp_mask=0x201da, order=0, oom_adj=0, oom_score_adj=0
Mar  8 11:36:09 vagrant-centos65 kernel: ruby cpuset=/ mems_allowed=0
Mar  8 11:36:09 vagrant-centos65 kernel: Pid: 6607, comm: ruby Tainted: G           --------------- H  2.6.32-431.el6.x86_64 #1
Mar  8 11:36:09 vagrant-centos65 kernel: Call Trace:
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff810d05b1>] ? cpuset_print_task_mems_allowed+0x91/0xb0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff81122960>] ? dump_header+0x90/0x1b0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff81123cef>] ? zone_watermark_ok+0x1f/0x30
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff81122de2>] ? oom_kill_process+0x82/0x2a0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff810d1651>] ? cpuset_mems_allowed_intersects+0x21/0x30
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff811232cc>] ? out_of_memory+0x2cc/0x3c0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8112fb3c>] ? __alloc_pages_nodemask+0x8ac/0x8d0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff81167a9a>] ? alloc_pages_current+0xaa/0x110
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8111fd57>] ? __page_cache_alloc+0x87/0x90
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8111f73e>] ? find_get_page+0x1e/0xa0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff81120cf7>] ? filemap_fault+0x1a7/0x500
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8114a084>] ? __do_fault+0x54/0x530
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8114a657>] ? handle_pte_fault+0xf7/0xb00
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8104eeb7>] ? pte_alloc_one+0x37/0x50
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff811832e9>] ? do_huge_pmd_anonymous_page+0xb9/0x3b0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8114b28a>] ? handle_mm_fault+0x22a/0x300
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8114f326>] ? vma_adjust+0x556/0x5e0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8104a8d8>] ? __do_page_fault+0x138/0x480
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8100bc4e>] ? invalidate_interrupt2+0xe/0x20
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8114f8fa>] ? vma_merge+0x29a/0x3e0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8114fd0b>] ? __vm_enough_memory+0x3b/0x190
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff81150d4c>] ? do_brk+0x26c/0x350
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8152d45e>] ? do_page_fault+0x3e/0xa0
Mar  8 11:36:09 vagrant-centos65 kernel: [<ffffffff8152a815>] ? page_fault+0x25/0x30
Mar  8 11:36:09 vagrant-centos65 kernel: Mem-Info:
Mar  8 11:36:09 vagrant-centos65 kernel: Node 0 DMA per-cpu:
Mar  8 11:36:09 vagrant-centos65 kernel: CPU    0: hi:    0, btch:   1 usd:   0
Mar  8 11:36:09 vagrant-centos65 kernel: CPU    1: hi:    0, btch:   1 usd:   0
Mar  8 11:36:09 vagrant-centos65 kernel: CPU    2: hi:    0, btch:   1 usd:   0
Mar  8 11:36:09 vagrant-centos65 kernel: CPU    3: hi:    0, btch:   1 usd:   0
Mar  8 11:36:09 vagrant-centos65 kernel: Node 0 DMA32 per-cpu:
Mar  8 11:36:09 vagrant-centos65 kernel: CPU    0: hi:  186, btch:  31 usd:  30
Mar  8 11:36:09 vagrant-centos65 kernel: CPU    1: hi:  186, btch:  31 usd:  49
Mar  8 11:36:09 vagrant-centos65 kernel: CPU    2: hi:  186, btch:  31 usd:   0
Mar  8 11:36:09 vagrant-centos65 kernel: CPU    3: hi:  186, btch:  31 usd:  30
Mar  8 11:36:09 vagrant-centos65 kernel: active_anon:366008 inactive_anon:67023 isolated_anon:96
Mar  8 11:36:09 vagrant-centos65 kernel: active_file:0 inactive_file:7 isolated_file:0
Mar  8 11:36:09 vagrant-centos65 kernel: unevictable:0 dirty:0 writeback:0 unstable:0
Mar  8 11:36:09 vagrant-centos65 kernel: free:13196 slab_reclaimable:1528 slab_unreclaimable:5821
Mar  8 11:36:09 vagrant-centos65 kernel: mapped:69 shmem:154 pagetables:6367 bounce:0
Mar  8 11:36:09 vagrant-centos65 kernel: Node 0 DMA free:8160kB min:340kB low:424kB high:508kB active_anon:3720kB inactive_anon:3844kB active_file:0kB inactive_file:0kB unevictable:0kB isolated(anon):0kB isolated(file):0kB present:15364kB mlocked:0kB dirty:0kB writeback:0kB mapped:0kB shmem:0kB slab_reclaimable:0kB slab_unreclaimable:16kB kernel_stack:0kB pagetables:12kB unstable:0kB bounce:0kB writeback_tmp:0kB pages_scanned:32 all_unreclaimable? yes
Mar  8 11:36:09 vagrant-centos65 kernel: lowmem_reserve[]: 0 1956 1956 1956
Mar  8 11:36:09 vagrant-centos65 kernel: Node 0 DMA32 free:44624kB min:44712kB low:55888kB high:67068kB active_anon:1460184kB inactive_anon:264376kB active_file:0kB inactive_file:28kB unevictable:0kB isolated(anon):384kB isolated(file):0kB present:2003776kB mlocked:0kB dirty:0kB writeback:0kB mapped:276kB shmem:616kB slab_reclaimable:6112kB slab_unreclaimable:23268kB kernel_stack:1304kB pagetables:25456kB unstable:0kB bounce:0kB writeback_tmp:0kB pages_scanned:224 all_unreclaimable? yes
Mar  8 11:36:09 vagrant-centos65 kernel: lowmem_reserve[]: 0 0 0 0
Mar  8 11:36:09 vagrant-centos65 kernel: Node 0 DMA: 4*4kB 4*8kB 1*16kB 1*32kB 2*64kB 0*128kB 1*256kB 1*512kB 1*1024kB 1*2048kB 1*4096kB = 8160kB
Mar  8 11:36:09 vagrant-centos65 kernel: Node 0 DMA32: 334*4kB 209*8kB 83*16kB 53*32kB 39*64kB 24*128kB 11*256kB 7*512kB 6*1024kB 2*2048kB 4*4096kB = 44624kB
Mar  8 11:36:09 vagrant-centos65 kernel: 17463 total pagecache pages
Mar  8 11:36:09 vagrant-centos65 kernel: 17243 pages in swap cache
Mar  8 11:36:09 vagrant-centos65 kernel: Swap cache stats: add 320556, delete 303313, find 5044/5906
Mar  8 11:36:09 vagrant-centos65 kernel: Free swap  = 0kB
Mar  8 11:36:09 vagrant-centos65 kernel: Total swap = 262136kB　
Mar  8 11:36:09 vagrant-centos65 kernel: 511983 pages RAM ★
Mar  8 11:36:09 vagrant-centos65 kernel: 43784 pages reserved
Mar  8 11:36:09 vagrant-centos65 kernel: 1168288 pages shared ★
Mar  8 11:36:09 vagrant-centos65 kernel: 389774 pages non-shared ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ pid ]   uid  tgid total_vm      rss cpu oom_adj oom_score_adj name
Mar  8 11:36:09 vagrant-centos65 kernel: [  330]     0   330     2710        1   1     -17         -1000 udevd
Mar  8 11:36:09 vagrant-centos65 kernel: [  840]     0   840     2280        2   1       0             0 dhclient
Mar  8 11:36:09 vagrant-centos65 kernel: [  905]     0   905     6899       24   2     -17         -1000 auditd
Mar  8 11:36:09 vagrant-centos65 kernel: [  924]     0   924    62270       89   0       0             0 rsyslogd
Mar  8 11:36:09 vagrant-centos65 kernel: [  947]    32   947     4744       16   3       0             0 rpcbind
Mar  8 11:36:09 vagrant-centos65 kernel: [  965]    29   965     5837        2   0       0             0 rpc.statd
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1038]     0  1038    78809       42   2       0             0 VBoxService
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1059]     0  1059    16554        1   0     -17         -1000 sshd
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1176]     0  1176    20211        2   1       0             0 master
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1183]    89  1183    20273       18   3       0             0 qmgr
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1186]     0  1186    29216       22   0       0             0 crond
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1207]     0  1207   122937        4   0       0             0 docker
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1309]     0  1309     1016       12   1       0             0 mingetty
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1313]     0  1313     1016        2   1       0             0 mingetty
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1317]     0  1317     1016        2   2       0             0 mingetty
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1323]     0  1323     1016        2   1       0             0 mingetty
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1327]     0  1327     1016        2   0       0             0 mingetty
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1329]     0  1329     1016        2   1       0             0 mingetty
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1330]     0  1330     1020        2   3       0             0 agetty
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1340]     0  1340     2709        1   0     -17         -1000 udevd
Mar  8 11:36:09 vagrant-centos65 kernel: [ 1341]     0  1341     2709        1   3     -17         -1000 udevd
Mar  8 11:36:09 vagrant-centos65 kernel: [ 3082]    89  3082    20231        2   1       0             0 pickup
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6552]     0  6552    24472        2   1       0             0 sshd
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6553]     0  6553    24472        2   1       0             0 sshd
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6556]   500  6556    24472       71   2       0             0 sshd
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6557]   500  6557    24472      102   1       0             0 sshd
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6558]   500  6558    27076        2   1       0             0 bash
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6559]   500  6559    27076       58   0       0             0 bash
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6607]   500  6607   479367   413106   0       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6610]   500  6610   127861    61600   2       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6611]   500  6611   127861    61600   3       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6612]   500  6612   127861    61600   1       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6613]   500  6613   127861    61600   2       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6614]   500  6614   127861    61600   3       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6615]   500  6615   127861    61600   1       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6616]   500  6616   127861    61600   2       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6617]   500  6617   127861    61600   3       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6618]   500  6618   127861    61600   1       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6619]   500  6619   127861    61600   2       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6620]   500  6620   127861    61600   3       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6621]   500  6621   127861    61600   1       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6622]   500  6622   127861    61600   2       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6623]   500  6623   127861    61600   3       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6624]   500  6624   127861    61600   1       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6625]   500  6625   127861    61600   2       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6626]   500  6626   127861    61600   1       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6627]   500  6627   127861    61600   2       0             0 ruby ★
Mar  8 11:36:09 vagrant-centos65 kernel: [ 6628]   500  6628   127861    61505   3       0             0 ruby ★
```

ruby の rss の総計だすと、RAM の総量を超える

共有されている/いないページ数は、下記のログを見ると良いようだ

```
Mar  8 11:36:09 vagrant-centos65 kernel: 511983 pages RAM

Mar  8 11:36:09 vagrant-centos65 kernel: 1168288 pages shared ★
Mar  8 11:36:09 vagrant-centos65 kernel: 389774 pages non-shared ★
```

#### 3.19.1

 * 新しいカーネルを使ったら、 `nr_ptes` と `swapents` が増えている
 * それでも CoW で共有しているページ数は分からん

```
Mar  9 08:05:01 vagrant-centos65 kernel: Out of memory: Kill process 9772 (ruby) score 940 or sacrifice child
Mar  9 08:05:01 vagrant-centos65 kernel: Killed process 9787 (ruby) total-vm:511968kB, anon-rss:238956kB, file-rss:0kB
Mar  9 08:05:04 vagrant-centos65 kernel: ruby invoked oom-killer: gfp_mask=0x201da, order=0, oom_score_adj=0
Mar  9 08:05:04 vagrant-centos65 kernel: ruby cpuset=/ mems_allowed=0
Mar  9 08:05:04 vagrant-centos65 kernel: CPU: 3 PID: 9772 Comm: ruby Tainted: G            E  3.19.1 #1
Mar  9 08:05:04 vagrant-centos65 kernel: Hardware name: innotek GmbH VirtualBox/VirtualBox, BIOS VirtualBox 12/01/2006
Mar  9 08:05:04 vagrant-centos65 kernel: 0000000000000000 ffff88004d13f7d8 ffffffff814f9290 ffff88004c60f140
Mar  9 08:05:04 vagrant-centos65 kernel: ffff88004c60f140 ffff88004d13f818 ffffffff8113e781 ffff88007cfcbb18
Mar  9 08:05:04 vagrant-centos65 kernel: ffff88004c60f140 0000000000000000 0000000000000000 000000000008a7d3
Mar  9 08:05:04 vagrant-centos65 kernel: Call Trace:
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff814f9290>] dump_stack+0x48/0x60
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8113e781>] dump_header+0x81/0xd0
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8113ec83>] oom_kill_process+0x223/0x390
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff81231cd5>] ? security_capable_noaudit+0x15/0x20
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8105deb7>] ? has_capability_noaudit+0x17/0x20
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8113f0f7>] out_of_memory+0x307/0x380
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8114424d>] __alloc_pages_slowpath+0x80d/0x890
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff81144526>] __alloc_pages_nodemask+0x256/0x260
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff81188bd7>] ? alloc_pages_current+0xa7/0x170
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff81188bd7>] alloc_pages_current+0xa7/0x170
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8113aedf>] __page_cache_alloc+0xaf/0xc0
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8113c078>] filemap_fault+0x1b8/0x440
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff81168439>] __do_fault+0x39/0x90
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8116865d>] do_read_fault+0x1cd/0x2e0
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8116b9a0>] handle_pte_fault+0x1c0/0x220
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8104ec70>] ? pte_alloc_one+0x30/0x50
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff81167b70>] ? __pte_alloc+0x90/0x180
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8116bb73>] __handle_mm_fault+0x173/0x290
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8116bcd1>] handle_mm_fault+0x41/0xa0
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8104977c>] __do_page_fault+0x18c/0x510
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff81172114>] ? change_protection+0x14/0x30
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff81172263>] ? mprotect_fixup+0x133/0x200
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff8108bb5b>] ? pick_next_task_fair+0x15b/0x210
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff81049bdc>] do_page_fault+0xc/0x10
Mar  9 08:05:04 vagrant-centos65 kernel: [<ffffffff814fee42>] page_fault+0x22/0x30
Mar  9 08:05:04 vagrant-centos65 kernel: Mem-Info:
Mar  9 08:05:04 vagrant-centos65 kernel: Node 0 DMA per-cpu:
Mar  9 08:05:04 vagrant-centos65 kernel: CPU    0: hi:    0, btch:   1 usd:   0
Mar  9 08:05:04 vagrant-centos65 kernel: CPU    1: hi:    0, btch:   1 usd:   0
Mar  9 08:05:04 vagrant-centos65 kernel: CPU    2: hi:    0, btch:   1 usd:   0
Mar  9 08:05:04 vagrant-centos65 kernel: CPU    3: hi:    0, btch:   1 usd:   0
Mar  9 08:05:04 vagrant-centos65 kernel: Node 0 DMA32 per-cpu:
Mar  9 08:05:04 vagrant-centos65 kernel: CPU    0: hi:  186, btch:  31 usd:   2
Mar  9 08:05:04 vagrant-centos65 kernel: CPU    1: hi:  186, btch:  31 usd: 160
Mar  9 08:05:04 vagrant-centos65 kernel: CPU    2: hi:  186, btch:  31 usd:   0
Mar  9 08:05:04 vagrant-centos65 kernel: CPU    3: hi:  186, btch:  31 usd:  30
Mar  9 08:05:04 vagrant-centos65 kernel: active_anon:352945 inactive_anon:119249 isolated_anon:0
Mar  9 08:05:04 vagrant-centos65 kernel: active_file:8 inactive_file:28 isolated_file:0
Mar  9 08:05:04 vagrant-centos65 kernel: unevictable:0 dirty:0 writeback:0 unstable:0
Mar  9 08:05:04 vagrant-centos65 kernel: free:13182 slab_reclaimable:1736 slab_unreclaimable:8268
Mar  9 08:05:04 vagrant-centos65 kernel: mapped:200 shmem:141 pagetables:3466 bounce:0
Mar  9 08:05:04 vagrant-centos65 kernel: free_cma:0
Mar  9 08:05:04 vagrant-centos65 kernel: Node 0 DMA free:8088kB min:356kB low:444kB high:532kB active_anon:3436kB inactive_anon:3656kB active_file:20kB inactive_file:24kB unevictable:0kB isolated(anon):0kB isolated(file):0kB present:15992kB managed:15908kB mlocked:0kB dirty:0kB writeback:0kB mapped:12kB shmem:0kB slab_reclaimable:56kB slab_unreclaimable:284kB kernel_stack:32kB pagetables:200kB unstable:0kB bounce:0kB free_cma:0kB writeback_tmp:0kB pages_scanned:592 all_unreclaimable? yes
Mar  9 08:05:04 vagrant-centos65 kernel: lowmem_reserve[]: 0 1934 1934 1934
Mar  9 08:05:04 vagrant-centos65 kernel: Node 0 DMA32 free:44640kB min:44696kB low:55868kB high:67044kB active_anon:1408344kB inactive_anon:473340kB active_file:12kB inactive_file:0kB unevictable:0kB isolated(anon):0kB isolated(file):0kB present:2031552kB managed:1990956kB mlocked:0kB dirty:0kB writeback:0kB mapped:788kB shmem:564kB slab_reclaimable:6888kB slab_unreclaimable:32788kB kernel_stack:1904kB pagetables:13664kB unstable:0kB bounce:0kB free_cma:0kB writeback_tmp:0kB pages_scanned:4724 all_unreclaimable? yes
Mar  9 08:05:04 vagrant-centos65 kernel: lowmem_reserve[]: 0 0 0 0
Mar  9 08:05:04 vagrant-centos65 kernel: Node 0 DMA: 13*4kB (UEM) 10*8kB (UEM) 9*16kB (UEM) 1*32kB (U) 2*64kB (UM) 2*128kB (EM) 3*256kB (UEM) 3*512kB (UEM) 1*1024kB (E) 2*2048kB (MR) 0*4096kB = 8116kB
Mar  9 08:05:04 vagrant-centos65 kernel: Node 0 DMA32: 1416*4kB (UE) 800*8kB (UE) 362*16kB (UEM) 96*32kB (UEM) 29*64kB (UEM) 20*128kB (UEM) 18*256kB (UEM) 11*512kB (UM) 1*1024kB (U) 2*2048kB (MR) 1*4096kB (R) = 44800kB
Mar  9 08:05:04 vagrant-centos65 kernel: Node 0 hugepages_total=0 hugepages_free=0 hugepages_surp=0 hugepages_size=2048kB
Mar  9 08:05:04 vagrant-centos65 kernel: 749 total pagecache pages
Mar  9 08:05:04 vagrant-centos65 kernel: 461 pages in swap cache
Mar  9 08:05:04 vagrant-centos65 kernel: Swap cache stats: add 66170, delete 65709, find 213/367
Mar  9 08:05:04 vagrant-centos65 kernel: Free swap  = 0kB
Mar  9 08:05:04 vagrant-centos65 kernel: Total swap = 262140kB
Mar  9 08:05:04 vagrant-centos65 kernel: 511886 pages RAM
Mar  9 08:05:04 vagrant-centos65 kernel: 0 pages HighMem/MovableOnly
Mar  9 08:05:04 vagrant-centos65 kernel: 10170 pages reserved
Mar  9 08:05:04 vagrant-centos65 kernel: 0 pages hwpoisoned
Mar  9 08:05:04 vagrant-centos65 kernel: [ pid ]   uid  tgid total_vm      rss nr_ptes swapents oom_score_adj name
Mar  9 08:05:04 vagrant-centos65 kernel: [  308]     0   308     2765        0       8      177         -1000 udevd
Mar  9 08:05:04 vagrant-centos65 kernel: [  581]     0   581     2764        0       8      181         -1000 udevd
Mar  9 08:05:04 vagrant-centos65 kernel: [  583]     0   583     2764        0       8      177         -1000 udevd
Mar  9 08:05:04 vagrant-centos65 kernel: [  821]     0   821     2295        0       9      121             0 dhclient
Mar  9 08:05:04 vagrant-centos65 kernel: [  858]     0   858     6413        0      13       58         -1000 auditd
Mar  9 08:05:04 vagrant-centos65 kernel: [  874]     0   874    60749       66      21       67             0 rsyslogd
Mar  9 08:05:04 vagrant-centos65 kernel: [  901]    32   901     4759        6      13       49             0 rpcbind
Mar  9 08:05:04 vagrant-centos65 kernel: [  921]    29   921     5852        1      15      110             0 rpc.statd
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1001]     0  1001    16666        0      33      179         -1000 sshd
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1089]     0  1089    20333       17      42      210             0 master
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1100]    89  1100    20395        0      44      221             0 qmgr
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1106]     0  1106     5613       13      14      138             0 crond
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1120]     0  1120     1031        1       8       20             0 mingetty
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1122]     0  1122     1031        1       8       20             0 mingetty
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1124]     0  1124     1031        1       7       20             0 mingetty
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1126]     0  1126     1031        1       8       21             0 mingetty
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1128]     0  1128     1031        1       8       21             0 mingetty
Mar  9 08:05:04 vagrant-centos65 kernel: [ 1130]     0  1130     1031        1       7       20             0 mingetty
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9630]    89  9630    20353        0      41      218             0 pickup
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9633]     0  9633    24584        2      53      233             0 sshd
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9637]   500  9637    24584       35      50      203             0 sshd
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9638]   500  9638     3377        0      11       93             0 bash
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9712]     0  9712    24584        2      50      234             0 sshd
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9716]   500  9716    24584       43      50      196             0 sshd
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9717]   500  9717     3377        1      11       90             0 bash
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9772]   500  9772   545695   470615    1060    62734             0 ruby
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9773]     0  9773    20176        1      43      156             0 sudo
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9774]     0  9774     1537       15       9        9             0 tail
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9788]   500  9788   127992    59739     257    62582             0 ruby
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9789]   500  9789   127992    59739     257    62582             0 ruby
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9790]   500  9790   127992    59739     257    62582             0 ruby
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9791]   500  9791   127992    59739     257    62582             0 ruby
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9792]   500  9792   127992    59739     257    62582             0 ruby
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9793]   500  9793   127992    59739     257    62582             0 ruby
Mar  9 08:05:04 vagrant-centos65 kernel: [ 9794]   500  9794   127992    59641     257    62680             0 ruby
```

# rss を出すのはどこか? 統計をダンプするコードから追う

dump_tasks で、ペペっと統計を出している

```c
/**
 * dump_tasks - dump current memory state of all system tasks
 * @mem: current's memory controller, if constrained
 * @nodemask: nodemask passed to page allocator for mempolicy ooms
 *
 * Dumps the current memory state of all eligible tasks.  Tasks not in the same
 * memcg, not in the same cpuset, or bound to a disjoint set of mempolicy nodes
 * are not shown.
 * State information includes task's pid, uid, tgid, vm size, rss, cpu, oom_adj
 * value, oom_score_adj value, and name.
 *
 * Call with tasklist_lock read-locked.
 */
static void dump_tasks(const struct mem_cgroup *mem, const nodemask_t *nodemask)
{
	struct task_struct *p;
	struct task_struct *task;

	pr_info("[ pid ]   uid  tgid total_vm      rss cpu oom_adj oom_score_adj name\n");
	for_each_process(p) {
		if (oom_unkillable_task(p, mem, nodemask))
			continue;

		task = find_lock_task_mm(p);
		if (!task) {
			/*
			 * This is a kthread or all of p's threads have already
			 * detached their mm's.  There's no need to report
			 * them; they can't be oom killed anyway.
			 */
			continue;
		}

		pr_info("[%5d] %5d %5d %8lu %8lu %3u     %3d         %5d %s\n",
			task->pid, task_uid(task), task->tgid,
			task->mm->total_vm, get_mm_rss(task->mm),
			task_cpu(task), task->signal->oom_adj,
			task->signal->oom_score_adj, task->comm);
		task_unlock(task);
	}
}
```

rss は `get_mm_rss(task->mm)` で出している

```
#define get_mm_rss(mm)					\
	(get_mm_counter(mm, file_rss) + get_mm_counter(mm, anon_rss))

// get_mm_counter は atomic 型のフィールドを読み出すマクロ
#define get_mm_counter(mm, member) ((unsigned long)atomic_long_read(&(mm)->_##member))
```

get_mm_rss が読みだしているのは mm_struct の _anon_rss, _file_rss である

```c
struct mm_struct {

//...

	/* Special counters, in some configurations protected by the
	 * page_table_lock, in other configurations by being atomic.
	 */
	mm_counter_t _file_rss;
	mm_counter_t _anon_rss;
	mm_counter_t _swap_usage;
```

get_mm_rss は /proc/<pid>/status でも使われてるよ。 VmRSS と同じ値

```c
void task_mem(struct seq_file *m, struct mm_struct *mm)
{
	unsigned long data, text, lib, swap;
	unsigned long hiwater_vm, total_vm, hiwater_rss, total_rss;

	/*
	 * Note: to minimize their overhead, mm maintains hiwater_vm and
	 * hiwater_rss only when about to *lower* total_vm or rss.  Any
	 * collector of these hiwater stats must therefore get total_vm
	 * and rss too, which will usually be the higher.  Barriers? not
	 * worth the effort, such snapshots can always be inconsistent.
	 */
	hiwater_vm = total_vm = mm->total_vm;
	if (hiwater_vm < mm->hiwater_vm)
		hiwater_vm = mm->hiwater_vm;
	hiwater_rss = total_rss = get_mm_rss(mm); // ★
	if (hiwater_rss < mm->hiwater_rss)
		hiwater_rss = mm->hiwater_rss;

	data = mm->total_vm - mm->shared_vm - mm->stack_vm;
	text = (PAGE_ALIGN(mm->end_code) - (mm->start_code & PAGE_MASK)) >> 10;
	lib = (mm->exec_vm << (PAGE_SHIFT-10)) - text;
	swap = get_mm_counter(mm, swap_usage);
	seq_printf(m,
		"VmPeak:\t%8lu kB\n"
		"VmSize:\t%8lu kB\n"
		"VmLck:\t%8lu kB\n"
		"VmHWM:\t%8lu kB\n"
		"VmRSS:\t%8lu kB\n"
		"VmData:\t%8lu kB\n"
		"VmStk:\t%8lu kB\n"
		"VmExe:\t%8lu kB\n"
		"VmLib:\t%8lu kB\n"
		"VmPTE:\t%8lu kB\n"
		"VmSwap:\t%8lu kB\n",
		hiwater_vm << (PAGE_SHIFT-10),
		(total_vm - mm->reserved_vm) << (PAGE_SHIFT-10),
		mm->locked_vm << (PAGE_SHIFT-10),
		hiwater_rss << (PAGE_SHIFT-10),
		total_rss << (PAGE_SHIFT-10),
		data << (PAGE_SHIFT-10),
		mm->stack_vm << (PAGE_SHIFT-10), text, lib,
		(PTRS_PER_PTE*sizeof(pte_t)*mm->nr_ptes) >> 10,
		swap << (PAGE_SHIFT-10));
}
```

## _anon_rss, _file_rss のインクリメント/デクリメント

以下の関数群を使う

```c
#if USE_SPLIT_PTLOCKS
/*
 * The mm counters are not protected by its page_table_lock,
 * so must be incremented atomically.
 */
#define set_mm_counter(mm, member, value) atomic_long_set(&(mm)->_##member, value)
#define get_mm_counter(mm, member) ((unsigned long)atomic_long_read(&(mm)->_##member))
#define add_mm_counter(mm, member, value) atomic_long_add(value, &(mm)->_##member)
#define inc_mm_counter(mm, member) atomic_long_inc(&(mm)->_##member)
#define dec_mm_counter(mm, member) atomic_long_dec(&(mm)->_##member)
```

## inc_mm_counter

```c
inc_mm_counter   1679 mm/memory.c      	inc_mm_counter(mm, file_rss);
inc_mm_counter   2358 mm/memory.c      				inc_mm_counter(mm, anon_rss);
inc_mm_counter   2362 mm/memory.c      			inc_mm_counter(mm, anon_rss);
inc_mm_counter   2805 mm/memory.c      	inc_mm_counter(mm, anon_rss);
inc_mm_counter   2947 mm/memory.c      	inc_mm_counter(mm, anon_rss);
inc_mm_counter   3102 mm/memory.c      			inc_mm_counter(mm, anon_rss);
inc_mm_counter   3105 mm/memory.c      			inc_mm_counter(mm, file_rss);
inc_mm_counter   1089 mm/rmap.c        			inc_mm_counter(mm, swap_usage);
inc_mm_counter    903 mm/swapfile.c    	inc_mm_counter(vma->vm_mm, anon_rss);
```

## __do_fault

ページフォルト時に、 inc_mm_counter で、インクリメントしている

```c
/*
 * __do_fault() tries to create a new page mapping. It aggressively
 * tries to share with existing pages, but makes a separate copy if
 * the FAULT_FLAG_WRITE is set in the flags parameter in order to avoid
 * the next page fault.
 *
 * As this is called only for pages that do not currently exist, we
 * do not need to flush old virtual caches or the TLB.
 *
 * We enter with non-exclusive mmap_sem (to exclude vma changes,
 * but allow concurrent faults), and pte neither mapped nor locked.
 * We return with mmap_sem still held, but pte unmapped and unlocked.
 */
static int __do_fault(struct mm_struct *mm, struct vm_area_struct *vma,
		unsigned long address, pmd_t *pmd,
		pgoff_t pgoff, unsigned int flags, pte_t orig_pte)

//...

	/*
	 * This silly early PAGE_DIRTY setting removes a race
	 * due to the bad i386 page protection. But it's valid
	 * for other architectures too.
	 *
	 * Note that if FAULT_FLAG_WRITE is set, we either now have
	 * an exclusive copy of the page, or this is a shared mapping,
	 * so we can make it writable and dirty to avoid having to
	 * handle that later.
	 */
	/* Only go through if we didn't race with anybody else... */
	if (likely(pte_same(*page_table, orig_pte))) {
		flush_icache_page(vma, page);
		entry = mk_pte(page, vma->vm_page_prot);
		if (flags & FAULT_FLAG_WRITE)
			entry = maybe_mkwrite(pte_mkdirty(entry), vma);
		if (anon) {
			inc_mm_counter(mm, anon_rss); // ★
			page_add_new_anon_rmap(page, vma, address);
		} else {
			inc_mm_counter(mm, file_rss); // ★
			page_add_file_rmap(page);
			if (flags & FAULT_FLAG_WRITE) {
				dirty_page = page;
				get_page(dirty_page);
			}
		}
```

## do_wp_page

共有されている、CoW なページに書き込む場合

```c
/*
 * This routine handles present pages, when users try to write
 * to a shared page. It is done by copying the page to a new address
 * and decrementing the shared-page counter for the old page.
 *
 * Note that this routine assumes that the protection checks have been
 * done by the caller (the low-level page fault routine in most cases).
 * Thus we can safely just mark it writable once we've done any necessary
 * COW.
 *
 * We also mark the page dirty at this point even though the page will
 * change only once the write actually happens. This avoids a few races,
 * and potentially makes it more efficient.
 *
 * We enter with non-exclusive mmap_sem (to exclude vma changes,
 * but allow concurrent faults), with pte both mapped and locked.
 * We return with mmap_sem still held, but pte unmapped and unlocked.
 */
static int do_wp_page(struct mm_struct *mm, struct vm_area_struct *vma,
		unsigned long address, pte_t *page_table, pmd_t *pmd,
		spinlock_t *ptl, pte_t orig_pte)
{

//...

	/*
	 * Re-check the pte - we dropped the lock
	 */
	page_table = pte_offset_map_lock(mm, pmd, address, &ptl);
	if (likely(pte_same(*page_table, orig_pte))) {
		if (old_page) {
			if (!PageAnon(old_page)) {
				dec_mm_counter(mm, file_rss); // ★
				inc_mm_counter(mm, anon_rss); // ★
				trace_mm_filemap_cow(mm, address);
			}
		} else {
			inc_mm_counter(mm, anon_rss); // ★
			trace_mm_anon_cow(mm, address);
		}
```