## TODO

 * /proc/sys/vm/dirty_background_ratio
 * /proc/sys/vm/dirty_ratio

どこで参照されてんの?

 * int allow_signal(int sig)
   * kernel thread にシグナル飛ばせる refs http://kernelnewbies.org/Simple_UDP_Server
   * signal_pending(current)
 * daemonize
 * debugfs

## /cgroup/cpuset.cpus のファイルインタフェース

```c
static struct cftype files[] = {
	{
		.name = "cpus",
		.read = cpuset_common_file_read,       // read
		.write_string = cpuset_write_resmask,  // write
		.max_write_len = (100U + 6 * NR_CPUS),
		.private = FILE_CPULIST,
	},
```

update_cpumask で struct cpuset の .cpus_allowd をセットする

トップレベルの cpuset 。変更できない

```c
static struct cpuset top_cpuset = {
	.flags = ((1 << CS_CPU_EXCLUSIVE) | (1 << CS_MEM_EXCLUSIVE)),
};
```

下記の用にしておくと CPU の数をみなくても全部のCPUを割り当てできる ...

```
cat /cgroup/cpuset.cpus > /cgroup/namahage_app_1/cpuset.cpus
```

## とある I/O error

``` 
 Mar 18 13:27:44 ***** kernel: ata6.00: exception Emask 0x0 SAct 0x3f SErr 0x0 action 0x0
Mar 18 13:27:44 ***** kernel: ata6.00: irq_stat 0x40000008
Mar 18 13:27:44 ***** kernel: ata6.00: cmd 60/08:00:d7:01:64/00:00:11:00:00/40 tag 0 ncq 4096 in
Mar 18 13:27:44 ***** kernel:          res 41/40:00:da:01:64/00:00:11:00:00/40 Emask 0x409 (media error) <F>
Mar 18 13:27:44 ***** kernel: ata6.00: status: { DRDY ERR }
Mar 18 13:27:44 ***** kernel: ata6.00: error: { UNC }
Mar 18 13:27:44 ***** kernel: ata6.00: configured for UDMA/133
Mar 18 13:27:44 ***** kernel: ata6: EH complete
Mar 18 13:27:44 ***** kernel: SCSI device sdf: 1953525168 512-byte hdwr sectors (1000205 MB)
Mar 18 13:27:44 ***** kernel: sdf: Write Protect is off
Mar 18 13:27:44 ***** kernel: SCSI device sdf: drive cache: write back

----

Mar 18 14:01:31 ***** kernel: ata6.00: exception Emask 0x0 SAct 0x7 SErr 0x0 action 0x0
Mar 18 14:01:31 ***** kernel: ata6.00: irq_stat 0x40000008
Mar 18 14:01:31 ***** kernel: ata6.00: cmd 60/08:00:d7:01:64/00:00:11:00:00/40 tag 0 ncq 4096 in
Mar 18 14:01:31 ***** kernel:          res 41/40:00:da:01:64/00:00:11:00:00/40 Emask 0x409 (media error) <F>
Mar 18 14:01:31 ***** kernel: ata6.00: status: { DRDY ERR }
Mar 18 14:01:31 ***** kernel: ata6.00: error: { UNC }
Mar 18 14:01:31 ***** kernel: ata6.00: configured for UDMA/133
Mar 18 14:01:31 ***** kernel: sd 5:0:0:0: Unhandled sense code
Mar 18 14:01:31 ***** kernel: sd 5:0:0:0: SCSI error: return code = 0x08000002
Mar 18 14:01:31 ***** kernel: Result: hostbyte=DID_OK driverbyte=DRIVER_SENSE,SUGGEST_OK
Mar 18 14:01:31 ***** kernel: sdf: Current [descriptor]: sense key: Medium Error
Mar 18 14:01:31 ***** kernel:     Add. Sense: Unrecovered read error - auto reallocate failed
Mar 18 14:01:31 ***** kernel: 
Mar 18 14:01:31 ***** kernel: Descriptor sense data with sense descriptors (in hex):
Mar 18 14:01:31 ***** kernel:         72 03 11 04 00 00 00 0c 00 0a 80 00 00 00 00 00 
Mar 18 14:01:31 ***** kernel:         11 64 01 da 
Mar 18 14:01:31 ***** kernel: EXT3-fs error (device dm-0): ext3_get_inode_loc: <6>ata6: EH complete
Mar 18 14:01:31 ***** kernel: SCSI device sdf: 1953525168 512-byte hdwr sectors (1000205 MB)
Mar 18 14:01:31 ***** kernel: sdf: Write Protect is off
Mar 18 14:01:31 ***** kernel: SCSI device sdf: drive cache: write back
Mar 18 14:01:31 ***** kernel: unable to read inode block - inode=384516154, block=769032195
Mar 18 14:01:31 ***** kernel: EXT3-fs error (device dm-0): ext3_get_inode_loc: unable to read inode block - inode=384516130, block=769032195

——

Mar 18 14:34:59 ***** kernel: ata6.00: cmd 60/08:00:d7:01:64/00:00:11:00:00/40 tag 0 ncq 4096 in
Mar 18 14:34:59 ***** kernel:          res 41/40:00:da:01:64/00:00:11:00:00/40 Emask 0x409 (media error) <F>
Mar 18 14:34:59 ***** kernel: ata6.00: status: { DRDY ERR }
Mar 18 14:34:59 ***** kernel: ata6.00: error: { UNC }
Mar 18 14:34:59 ***** kernel: ata6.00: configured for UDMA/133
Mar 18 14:34:59 ***** kernel: sd 5:0:0:0: Unhandled sense code
Mar 18 14:34:59 ***** kernel: sd 5:0:0:0: SCSI error: return code = 0x08000002
Mar 18 14:34:59 ***** kernel: Result: hostbyte=DID_OK driverbyte=DRIVER_SENSE,SUGGEST_OK
Mar 18 14:34:59 ***** kernel: sdf: Current [descriptor]: sense key: Medium Error
Mar 18 14:34:59 ***** kernel:     Add. Sense: Unrecovered read error - auto reallocate failed
Mar 18 14:34:59 ***** kernel: 
Mar 18 14:34:59 ***** kernel: Descriptor sense data with sense descriptors (in hex):
Mar 18 14:34:59 ***** kernel:         72 03 11 04 00 00 00 0c 00 0a 80 00 00 00 00 00 
Mar 18 14:34:59 ***** kernel:         11 64 01 da 
Mar 18 14:34:59 ***** kernel: ata6: EH complete
Mar 18 14:34:59 ***** kernel: EXT3-fs error (device dm-0): ext3_get_inode_loc: <2>EXT3-fs error (device dm-0): ext3_get_inode_loc: unable to read inode block - inode=384516154, block=769032195
Mar 18 14:34:59 ***** kernel: Aborting journal on device dm-0.
Mar 18 14:34:59 ***** kernel: unable to read inode block - inode=384516130, block=769032195
Mar 18 14:34:59 ***** kernel: SCSI device sdf: 1953525168 512-byte hdwr sectors (1000205 MB)
Mar 18 14:34:59 ***** kernel: sdf: Write Protect is off
Mar 18 14:34:59 ***** kernel: SCSI device sdf: drive cache: write back
Mar 18 14:34:59 ***** kernel: ext3_abort called.
Mar 18 14:34:59 ***** kernel: EXT3-fs error (device dm-0): ext3_journal_start_sb: Detected aborted journal
Mar 18 14:34:59 ***** kernel: Remounting filesystem read-only
```

## IO-APIC-* と XT-PIC-XT

```
[vagrant@vagrant-centos65 ~]$ cat /proc/interrupts 
           CPU0       CPU1       CPU2       CPU3
  0:        170          0          0          0   IO-APIC-edge      timer
  1:          7          0          0          0   IO-APIC-edge      i8042
  8:          0          0          0          0   IO-APIC-edge      rtc0
  9:          0          0          0          0   IO-APIC-fasteoi   acpi
 12:        108          0          0          0   IO-APIC-edge      i8042
 19:        421          0          0          0   IO-APIC-fasteoi   eth0
 20:         50          0          0          0   IO-APIC-fasteoi   vboxguest
 21:       1790          0          0          0   IO-APIC-fasteoi   ahci
```

```
[vagrant@vagrant-centos65 ~]$ cat /proc/interrupts 
           CPU0       
  0:        164    XT-PIC-XT        timer
  1:          8    XT-PIC-XT        i8042
  2:          0    XT-PIC-XT        cascade
  4:          1    XT-PIC-XT      
  8:          0    XT-PIC-XT        rtc0
  9:         60    XT-PIC-XT        acpi, vboxguest
 10:        252    XT-PIC-XT        virtio0
 11:      15208    XT-PIC-XT        ahci
 12:        136    XT-PIC-XT        i8042
```

## sched_setaffinity にして無限ループ

 * ゲストOSでCPUアフィニティをセットしてもホストOSで使われるCPUは固定だった
 * ただのプロセスだしね

```c
#if 0
#!/bin/bash
CFLAGS="-O2 -std=gnu99 -W -Wall -fPIE -D_FORTIFY_SOURCE=2"
o=`basename $0`
o=".${o%.*}"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sched.h>

int main(int argc, char *argv[])
{
	int cpu = 0;
	cpu_set_t set;

	if (argc == 2)
		cpu = atoi(argv[1]);

	CPU_SET(cpu, &set);
	if(sched_setaffinity(getpid(), sizeof(cpu_set_t), &set) < 0) {
		perror("sched_setaffinity");
		exit(EXIT_FAILURE);
	}

	printf("sched_setaffinity %d\n", cpu);
	for(;;) { }

	exit(0);
```

## tmpfs -oremount,size=*M

tmpfs は remount する際に現使用量(ブロック数, inode数)よりも size を小さくすることはできない

```
[vagrant@vagrant-centos65 ~]$ df -h
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           100M   53M   48M  53% /dev/shm

[vagrant@vagrant-centos65 ~]$ sudo mount -t tmpfs -oremount,size=10M tmpfs /dev/shm
mount: /dev/shm not mounted already, or bad option
```

strace の結果 は mount(2) で EINVAL

```
[pid  1899] mount("tmpfs", "/dev/shm", 0x7f4227a1d980, MS_MGC_VAL|MS_REMOUNT, "size=10M") = -1 EINVAL (Invalid argument)
```

mm/shmem.c で下記の様に実装されている

```c
static int shmem_remount_fs(struct super_block *sb, int *flags, char *data)
	struct shmem_sb_info *sbinfo = SHMEM_SB(sb);
	struct shmem_sb_info config = *sbinfo;
	unsigned long inodes;
	int error = -EINVAL;

    // マウントオプションをパース
	config.mpol = NULL;
	if (shmem_parse_options(data, &config, true))
		return error;

	spin_lock(&sbinfo->stat_lock);
	inodes = sbinfo->max_inodes - sbinfo->free_inodes;

    // 使用しているブロック数とマウントオプションで指定したブロック数の比較
    // 左辺が大きければ true かな
	if (percpu_counter_compare(&sbinfo->used_blocks, config.max_blocks) > 0)
		goto out;

    // inode数の比較
	if (config.max_inodes < inodes)
		goto out;

//....

out:
	spin_unlock(&sbinfo->stat_lock);
	return error;
}
```

RAMベースのファイルシステムなので、remount の際に勝手に切り詰める訳にはいかんということだろう

## vagrant sendfile

期待した通りに動かん

```c
ssize_t sf_reg_splice_read(struct file *in, loff_t *ppos,
                                 struct pipe_inode_info *pipe, size_t len,
                                 unsigned int flags)
{
        int ret;
        struct dentry *dentry = in->f_path.dentry;
        struct inode *inode = dentry->d_inode;
        struct sf_inode_info *sf_i = GET_INODE_INFO(inode);
        struct timespec oldmtime;

        oldmtime.tv_sec  = inode->i_mtime.tv_sec;
        oldmtime.tv_nsec = inode->i_mtime.tv_nsec;

        printk("@%s %d %s\n", __FUNCTION__, sf_i->force_restat, in->f_dentry->d_name.name);
        printk("%s oldmtime %ld %ld\n", __FUNCTION__, oldmtime.tv_sec, oldmtime.tv_nsec);
        printk("%s inode    %ld %ld\n", __FUNCTION__, inode->i_mtime.tv_sec, inode->i_mtime.tv_nsec);
        printk("%s %lu\n", __FUNCTION__, dentry->d_time);
        ret = sf_inode_revalidate(dentry);
        if (ret)
            return ret;

        printk("%s oldmtime %ld %ld\n", __FUNCTION__, oldmtime.tv_sec, oldmtime.tv_nsec);
        printk("%s inode    %ld %ld\n", __FUNCTION__, inode->i_mtime.tv_sec, inode->i_mtime.tv_nsec);
        printk("%s %lu\n", __FUNCTION__, dentry->d_time);
        if (timespec_compare(&oldmtime, &inode->i_mtime) < 0) {
            printk("%s invlaidate \n", __FUNCTION__);
            invalidate_mapping_pages(in->f_mapping, 0, -1);
        }
        return generic_file_splice_read(in, ppos, pipe, len, flags);
}
```

## スタックポインタと __builtin_frame_address

```
 35 #define CURRENT_STACK_FRAME     __builtin_frame_address (0)
```

## rsync の io timeout

```
io timeout after 3604 seconds -- exiting
rsync error: timeout in data send/receive (code 30) at io.c(200) [receiver=3.0.6]
rsync: connection unexpectedly closed (697 bytes received so far) [generator]
rsync error: error in rsync protocol data stream (code 12) at io.c(600) [generator=3.0.6]
```

check_timeout で io_timeout が使われる

 * 最後の read
 * 最後の write

でそれぞれの時刻と time(NULL) が比較される

```c
// last_io_in  最後に write した time(NULL)
// last_io_out 最後に read  した time(NULL

static void check_timeout(void)
{
        time_t t, chk; 

        if (!io_timeout || ignore_timeout)
                return;

        t = time(NULL);

        if (!last_io_in)
                last_io_in = t; 

        chk = MAX(last_io_out, last_io_in);
        if (t - chk >= io_timeout) {
                if (am_server || am_daemon)
                        exit_cleanup(RERR_TIMEOUT);
                rprintf(FERROR, "[%s] io timeout after %d seconds -- exiting\n",
                        who_am_i(), (int)(t-chk));
                exit_cleanup(RERR_TIMEOUT);
        }    
}
```

 * check_timeout が 使われている箇所
   * writefd_unbuffered
   * read_line
   * read_timeout
 * いずれも select(2) を呼び出した後に check_timeout を見ている
   * select_timeout は io_timeout の半分の数値
   * select(2) がタイムアウトを繰り返して last_io_in, last_io_out が更新されていないと check_timeout() で死ぬ様子

io_timeout は --timeout で指定した値である

```c
  {"timeout",          0,  POPT_ARG_INT,    &io_timeout, 0, 0, 0 },
```

io_timeout, select_timeout は set_io_timeout でセットされる

```
void set_io_timeout(int secs)
{
        io_timeout = secs;
        allowed_lull = (io_timeout + 1) / 2;

        // select(2) のタイムアウト
        if (!io_timeout || allowed_lull > SELECT_TIMEOUT)
                select_timeout = SELECT_TIMEOUT;
        else
                select_timeout = allowed_lull;

        if (read_batch)
                allowed_lull = 0;
}
```

#### おまけ

keepalive なんてのもあるらしい

```c
void maybe_send_keepalive(void)
{
        if (time(NULL) - last_io_out >= allowed_lull) {
                if (!iobuf_out || !iobuf_out_cnt) {
                        if (protocol_version < 29)
                                send_msg(MSG_DATA, "", 0, 0);
                        else if (protocol_version >= 30)
                                send_msg(MSG_NOOP, "", 0, 0);
                        else {
                                write_int(sock_f_out, cur_flist->used);
                                write_shortint(sock_f_out, ITEM_IS_NEW);
                        }    
                }    
                if (iobuf_out)
                        io_flush(NORMAL_FLUSH);
        }    
}
```

## nagios/plugins/check_disk.c

inode の空き容量表示が分かりにくい奴

```
$ yumdownloader --source nagios-plugins
$ rpm -ivh nagios-plugins-1.4.16-10.el6.src.rpm
$ cd ~/rpmbuild/SOURCES
$ tar xvfz nagios-plugins-1.4.16.tar.gz
```

```c
  preamble = strdup (" - free space:");
```

```c
      // dfree_pct 空き容量のパーセンテージ
      asprintf (&output, "%s %s %.0f %s (%.0f%%",
                output,
                (!strcmp(me->me_mountdir, "none") || display_mntp) ? me->me_devname : me->me_mountdir,
                path->dfree_units,
                units,
                path->dfree_pct);
      if (path->dused_inodes_percent < 0) {
        asprintf(&output, "%s inode=-);", output);
      } else {
        asprintf(&output, "%s inode=%.0f%%);", output, path->dfree_inodes_percent );
      }
```

asprintf 知らなかった。便利そうだ

## mkdir EEXISTS で返す箇所を探す

mkdir(2) は mkdirat(2) のラッパー

```c
SYSCALL_DEFINE2(mkdir, const char __user *, pathname, int, mode)
{
	return sys_mkdirat(AT_FDCWD, pathname, mode);
}
```

lookup_create が -EEXISTS を返すケースがある

```c
SYSCALL_DEFINE3(mkdirat, int, dfd, const char __user *, pathname, int, mode)
{
	int error = 0;
	char * tmp;
	struct dentry *dentry;
	struct nameidata nd;

	error = user_path_parent(dfd, pathname, &nd, &tmp);
	if (error)
		goto out_err;

   // ここを潜る
	dentry = lookup_create(&nd, 1);
	error = PTR_ERR(dentry);
	if (IS_ERR(dentry))
		goto out_unlock;
```

lookup_create で dentry をルックアップして d_inode を持ってたら EEXISTS を返す

```c
/**
 * lookup_create - lookup a dentry, creating it if it doesn't exist
 * @nd: nameidata info
 * @is_dir: directory flag
 *
 * Simple function to lookup and return a dentry and create it
 * if it doesn't exist.  Is SMP-safe.
 *
 * Returns with nd->path.dentry->d_inode->i_mutex locked.
 */
struct dentry *lookup_create(struct nameidata *nd, int is_dir)
{
   // デフォのエラー
	struct dentry *dentry = ERR_PTR(-EEXIST);

	mutex_lock_nested(&nd->path.dentry->d_inode->i_mutex, I_MUTEX_PARENT);
	/*
	 * Yucky last component or no last component at all?
	 * (foo/., foo/.., /////)
	 */
	if (nd->last_type != LAST_NORM)
		goto fail;
	nd->flags &= ~LOOKUP_PARENT;
	nd->flags |= LOOKUP_CREATE | LOOKUP_EXCL;
	nd->intent.open.flags = O_EXCL;

	/*
	 * Do the final lookup.
	 */
	dentry = lookup_hash(nd);
	if (IS_ERR(dentry))
		goto fail;

    // dentry の d_inode がある = 存在するinode の場合は EEXISTS を返す
	if (dentry->d_inode)
		goto eexist;
	/*
	 * Special case - lookup gave negative, but... we had foo/bar/
	 * From the vfs_mknod() POV we just have a negative dentry -
	 * all is fine. Let's be bastards - you had / on the end, you've
	 * been asking for (non-existent) directory. -ENOENT for you.
	 */
	if (unlikely(!is_dir && nd->last.name[nd->last.len])) {
		dput(dentry);
		dentry = ERR_PTR(-ENOENT);
	}
	return dentry;
eexist:
	dput(dentry);
	dentry = ERR_PTR(-EEXIST);
fail:
	return dentry;
}
EXPORT_SYMBOL_GPL(lookup_create);
```

dentry->d_inode の有無だけ見てるので、dentry が指しているのがファイルディレクトリ、またその他かは問わず EEXISTS になるのが分かる

## nscd のアレ

 * http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=616171
 * http://man7.org/linux/man-pages/man5/nscd.conf.5.html max_threads
   * https://bugzilla.redhat.com/show_bug.cgi?id=706571

```c
#define _GNU_SOURCE
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#define BUFLEN 4096

int
main(void)
{
    struct group grp, *grpp;
    char buf[BUFLEN];
    int i;

    setgrent();
    while (1) {
        i = getgrent_r(&grp, buf, BUFLEN, &grpp);
        if (i)
            break;
        printf("%s (%d):", grpp->gr_name, grpp->gr_gid);
        for (i = 0; ; i++) {
            if (grpp->gr_mem[i] == NULL)
                break;
            printf(" %s", grpp->gr_mem[i]);
        }
        printf("\n");
    }
    endgrent();
    exit(EXIT_SUCCESS);
}
```

## free のバッファ

 * free で表示されるバッファは /proc/meminfo の Buffers の数値
 * Buffers の数値は fs/proc/meminfo.c の [si_meminfo](http://lxr.free-electrons.com/ident?v=2.6.32&i=si_meminfo) で {val->bufferram = nr_blockdev_pages();` で代入される
 * nr_blockdev_pages
   * block_device 型ファイルのアドレス空間にマッピングされたページ数 = Buffers = バッファのサイズ
   * ブロックデバイスは all_bdevs のリストに繋がってる

```c
long nr_blockdev_pages(void)
{
	struct block_device *bdev;
	long ret = 0;
	spin_lock(&bdev_lock);
	list_for_each_entry(bdev, &all_bdevs, bd_list) {
		ret += bdev->bd_inode->i_mapping->nrpages;
	}
	spin_unlock(&bdev_lock);
	return ret;
}
```

```c
struct block_device {
        dev_t                   bd_dev;  /* not a kdev_t - it's a search key */
        struct inode *          bd_inode;       /* will die */
        struct super_block *    bd_super;
        int                     bd_openers;
        struct mutex            bd_mutex;       /* open/close mutex */
        struct list_head        bd_inodes;
        void *                  bd_holder;
        int                     bd_holders;
#ifdef CONFIG_SYSFS
        struct list_head        bd_holder_list;
#endif
        struct block_device *   bd_contains;
        unsigned                bd_block_size;
        struct hd_struct *      bd_part;
        /* number of times partitions within this device have been opened. */
        unsigned                bd_part_count;
        int                     bd_invalidated;
        struct gendisk *        bd_disk;
        struct list_head        bd_list;
        /*
         * Private data.  You must have bd_claim'ed the block_device
         * to use this.  NOTE:  bd_claim allows an owner to claim
         * the same device multiple times, the owner must take special
         * care to not mess up bd_private for that case.
         */
        unsigned long           bd_private;

        /* The counter of freeze processes */
        int                     bd_fsfreeze_count;
        /* Mutex for freeze */
        struct mutex            bd_fsfreeze_mutex;
};
```

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

 * /var/log/dmesg

```
console [ttyS0] enabled
serial8250: ttyS0 at I/O 0x3f8 (irq = 4) is a 16550A
00:05: ttyS0 at I/O 0x3f8 (irq = 4) is a 16550A
```

drivers/serial/8250.c がドライバだろうか?

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
