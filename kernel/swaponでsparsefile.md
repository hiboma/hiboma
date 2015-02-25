# swapon で sparse file

元ネタはこちら、http://d.hatena.ne.jp/iww/20140215/sparse

## vagrant でテスト

上記ブログと同じ手順を実行した

```c
[vagrant@vagrant-centos65 ~]$ sudo dd if=/dev/zero of=/sparse bs=1 count=1 seek=4294967295
1+0 records in
1+0 records out
1 byte (1 B) copied, 3.4408e-05 s, 29.1 kB/s
[vagrant@vagrant-centos65 ~]$ sudo cp --sparse=always /sparse /perfectsparse
[vagrant@vagrant-centos65 ~]$ df
Filesystem           1K-blocks      Used Available Use% Mounted on
/dev/sda1              7635048   5893100   1354108  82% /
tmpfs                   936460         0    936460   0% /dev/shm
vagrant              487712924 244537188 243175736  51% /vagrant
tmp_vagrant-puppet-2_manifests
                     487712924 244537188 243175736  51% /tmp/vagrant-puppet-2/manifests
tmp_vagrant-puppet-3_manifests
                     487712924 244537188 243175736  51% /tmp/vagrant-puppet-3/manifests
[vagrant@vagrant-centos65 ~]$ sudo mkswap /perfectsparse
mkswap: /perfectsparse: warning: don't erase bootbits sectors
        on whole disk. Use -f to force.
Setting up swapspace version 1, size = 4194300 KiB
no label, UUID=04bbf596-8a58-49c5-8690-dd4aefb99dc4
[vagrant@vagrant-centos65 ~]$ sudo mkswap -f /perfectsparse
Setting up swapspace version 1, size = 4194300 KiB
no label, UUID=aab24cc6-0a66-4454-87b0-de0a244a4cfa
[vagrant@vagrant-centos65 ~]$ sudo swapon /perfectsparse
swapon: /perfectsparse: skipping - it appears to have holes.
[vagrant@vagrant-centos65 ~]$ sudo swapon -f /perfectsparse
swapon: /perfectsparse: skipping - it appears to have holes.
```

## swapon: /perfectsparse: skipping - it appears to have holes.

上記の warning は、どのように出されているか? ソースを追うと下記のような感じ

```c
        # wget http://vault.centos.org/6.6/os/Source/SPackages/util-linux-ng-2.17.2-12.18.el6.src.rpm
        # vim mount/swapon.c 

        /* test for holes by LBT */
        if (S_ISREG(st.st_mode)) {
                if (st.st_blocks * 512 < st.st_size) {
                        warnx(_("%s: skipping - it appears to have holes."),
                                special);
                        goto err;
                }
                devsize = st.st_size;
        }


        fd = open(special, O_RDONLY);
        if (fd == -1) {
                warn(_("%s: open failed"), special);
                goto err;
        }

        if (S_ISBLK(st.st_mode) && blkdev_get_size(fd, &devsize)) {
                warn(_("%s: get size failed"), special);
                goto err;
        }

        hdr = swap_get_header(fd, &sig, &pagesize);
        if (!hdr) {
                warn(_("%s: read swap header failed"), special);
                goto err;
        }
```

 * ブロック数 × ブロックサイズ と、ファイルサイズを比較している
 * ブロックサイズが 512 でハードコードだけど、これはどこに合わせている?
   * swap のブロックは必ず 512 バイトなのかな?