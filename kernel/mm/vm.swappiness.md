## vm.swappiness = 0 でも swap out するケース

 * page cache が少なくて slab cache (dentry cache, inode cache) がめちゃくちゃあるケース
 * free が watermark low ギリギリ

の際に RSS をどかんと確保するプロセスがあらわれれると、 reclaim が起こり swap out を起こすケースがある

#### Vagrant の環境を作る

swapfile を適当な場所に作って置きます

```
sudo dd if=/dev/zero of=/swapfile bs=1024k count=256
sudo chown root:root /swapfile
sudo chmod 0600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
sudo swapoff /swapfile && sudo swapon /swapfile;
```

ところで環境は CentOS6.5

#### negative dentry を作りまくる

下記のようなワンライナーで negative dentry を大量に作れます

```sh
$ perl -e 'foreach (1 .. 10000000) { $s = rand($_); unlink "/tmp/$s" }
```

gdentry が増えているのが slabtop で確認できる

```
[vagrant@vagrant-centos65 ~]$ slabtop

 Active / Total Objects (% used)    : 8414409 / 8422978 (99.9%)
 Active / Total Slabs (% used)      : 422531 / 422538 (100.0%)
 Active / Total Caches (% used)     : 101 / 184 (54.9%)
 Active / Total Size (% used)       : 1589026.02K / 1590849.98K (99.9%)
 Minimum / Average / Maximum Object : 0.02K / 0.19K / 4096.00K

  OBJS ACTIVE  USE OBJ SIZE  SLABS OBJ/SLAB CACHE SIZE NAME
8336560 8336523  99%    0.19K 416828       20   1667312K dentry
 16016  15882  99%    0.03K    143      112       572K size-32
  9086   8127  89%    0.06K    154       59       616K size-64
  8473   6417  75%    0.10K    229       37       916K buffer_head
  7116   6895  96%    0.98K   1779        4      7116K ext4_inode_cache
  7102   7018  98%    0.07K    134       53       536K selinux_inode_security
  5940   5876  98%    0.14K    220       27       880K sysfs_dir_cache
  4368   4346  99%    0.58K    728        6      2912K inode_cache
```

sar で dentunusd ( negative dentry ) が増えているのが確認できる

```
[vagrant@vagrant-centos65 ~]$ sar -v 1 
Linux 2.6.32-504.el6.x86_64 (vagrant-centos65.vagrantup.com)    07/09/2015      _x86_64_        (4 CPU)

03:46:40 PM dentunusd   file-nr  inode-nr    pty-nr
03:46:41 PM   8331293       704      5935         5
03:46:42 PM   8331293       704      5935         5
```

Slab (SReclaimable) が多いのが /proc/meminfo でも確認できる

```
[vagrant@vagrant-centos65 ~]$ cat /proc/meminfo
MemTotal:        1872864 kB
MemFree:           65976 kB
Buffers:           10968 kB
Cached:            13220 kB
SwapCached:            0 kB
Active:            12908 kB
Inactive:          29008 kB
Active(anon):       3112 kB
Inactive(anon):    16620 kB
Active(file):       9796 kB
Inactive(file):    12388 kB
Unevictable:           0 kB
Mlocked:               0 kB
SwapTotal:        262140 kB
SwapFree:         262140 kB
Dirty:                28 kB
Writeback:             0 kB
AnonPages:         17736 kB
Mapped:             6100 kB
Shmem:              2000 kB
Slab:            1727880 kB ★
SReclaimable:    1705260 kB ★
SUnreclaim:        22620 kB
KernelStack:        1088 kB
PageTables:         4200 kB
NFS_Unstable:          0 kB
Bounce:                0 kB
WritebackTmp:          0 kB
CommitLimit:     1198572 kB
Committed_AS:      92588 kB
VmallocTotal:   34359738367 kB
VmallocUsed:       19296 kB
VmallocChunk:   34359712316 kB
HardwareCorrupted:     0 kB
AnonHugePages:         0 kB
HugePages_Total:       0
HugePages_Free:        0
HugePages_Rsvd:        0
HugePages_Surp:        0
Hugepagesize:       2048 kB
DirectMap4k:        8128 kB
DirectMap2M:     2039808 kB
```

## vm.vfs_cache_pressure=100

![vm vfs-cache_pressure 0-slab](https://cloud.githubusercontent.com/assets/172456/8613693/9cc5df34-271c-11e5-9487-7d611d1a7865.gif)

## vm.vfs_cache_pressure=10

![vm vfs_cache_pressure 10-slab](https://cloud.githubusercontent.com/assets/172456/8613691/966da982-271c-11e5-89ae-e43ab7e79a5d.gif)

## vm.vfs_cache_pressure=1000

![vm vfs_cache_pressure 1000-slab](https://cloud.githubusercontent.com/assets/172456/8613690/95ae1c70-271c-11e5-92be-89b26a777817.gif)

## reclaim の処理

do_try_to_free_pages

 * shrink_zones  => vm.swappiness
   * shrink_mem_cgroup_zone
     * shrink_list (LRU .. anon, file)
       * shrink_active_list
       * shrink_inactive_list
         * shrink_page_list
           * sc->may_writepage = 1 なら
             * dirty な page をpageout する
 * shrink_slab =>  vm.vfs_cache_pressure
    * dcache_shrinker
      * prune_dcache
        * dentry キャッシュを消す
    * icache_shrinker
      * prune_icache
        * inode キャッシュを消す
 * sc->nr_reclaimed >= sc->nr_to_reclaim
   * 欲しい分だけ reclaim したので終わり
 * total_scanned > writeback_threshold
   * sc->may_writepage = 1
 * shrink_zones を繰り返す

 