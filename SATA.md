
## SATA のディスクを一杯生やす

Vagrantfile に下記の設定を入れておく

```ruby
config.vm.provider :virtualbox do |vb|
  1.upto(29).each do |i|
    file_to_disk = "./tmp/disk-#{i}.vdi"
    unless File.exist?(file_to_disk)
      vb.customize ["createhd", "--filename", file_to_disk, "--size", 1 * 1024]
    end
    vb.customize ['storageattach', :id, '--storagectl', 'SATA', '--port', i, '--device', 0, '--type', 'hdd', '--medium', file_to_disk, '--setuuid', '']
  end
end   
```

この通り /dev/sdb 〜 /dev/sdad まで生える

 * ブロックデバイスのメジャー番号が 8 と 65 に別れている
 * マイナー番号は 16 ずつ繰り上がっている
   * SCSI のパーティションが 16までしか切れない事に関係ある?

```
[vagrant@vagrant-centos65 ~]$ ls -ihal /dev/sd*
5942 brw-rw---- 1 root disk  8,   0 Mar 12 14:05 /dev/sda
5943 brw-rw---- 1 root disk  8,   1 Mar 12 14:05 /dev/sda1
5944 brw-rw---- 1 root disk  8,   2 Mar 12 14:05 /dev/sda2
6022 brw-rw---- 1 root disk 65, 160 Mar 12 14:05 /dev/sdaa
6025 brw-rw---- 1 root disk 65, 176 Mar 12 14:05 /dev/sdab
6028 brw-rw---- 1 root disk 65, 192 Mar 12 14:05 /dev/sdac
6031 brw-rw---- 1 root disk 65, 208 Mar 12 14:05 /dev/sdad
5947 brw-rw---- 1 root disk  8,  16 Mar 12 14:05 /dev/sdb
5950 brw-rw---- 1 root disk  8,  32 Mar 12 14:05 /dev/sdc
5953 brw-rw---- 1 root disk  8,  48 Mar 12 14:05 /dev/sdd
5956 brw-rw---- 1 root disk  8,  64 Mar 12 14:05 /dev/sde
5959 brw-rw---- 1 root disk  8,  80 Mar 12 14:05 /dev/sdf
5962 brw-rw---- 1 root disk  8,  96 Mar 12 14:05 /dev/sdg
5965 brw-rw---- 1 root disk  8, 112 Mar 12 14:05 /dev/sdh
5968 brw-rw---- 1 root disk  8, 128 Mar 12 14:05 /dev/sdi
5971 brw-rw---- 1 root disk  8, 144 Mar 12 14:05 /dev/sdj
5974 brw-rw---- 1 root disk  8, 160 Mar 12 14:05 /dev/sdk
5977 brw-rw---- 1 root disk  8, 176 Mar 12 14:05 /dev/sdl
5980 brw-rw---- 1 root disk  8, 192 Mar 12 14:05 /dev/sdm
5983 brw-rw---- 1 root disk  8, 208 Mar 12 14:05 /dev/sdn
5986 brw-rw---- 1 root disk  8, 224 Mar 12 14:05 /dev/sdo
5989 brw-rw---- 1 root disk  8, 240 Mar 12 14:05 /dev/sdp
5992 brw-rw---- 1 root disk 65,   0 Mar 12 14:05 /dev/sdq
5995 brw-rw---- 1 root disk 65,  16 Mar 12 14:05 /dev/sdr
5998 brw-rw---- 1 root disk 65,  32 Mar 12 14:05 /dev/sds
6001 brw-rw---- 1 root disk 65,  48 Mar 12 14:05 /dev/sdt
6004 brw-rw---- 1 root disk 65,  64 Mar 12 14:05 /dev/sdu
6007 brw-rw---- 1 root disk 65,  80 Mar 12 14:05 /dev/sdv
6010 brw-rw---- 1 root disk 65,  96 Mar 12 14:05 /dev/sdw
6013 brw-rw---- 1 root disk 65, 112 Mar 12 14:05 /dev/sdx
6016 brw-rw---- 1 root disk 65, 128 Mar 12 14:05 /dev/sdy
6019 brw-rw---- 1 root disk 65, 144 Mar 12 14:05 /dev/sdz
```

/var/log/messages にはこんなんログが並びまくる

```
Mar 12 14:05:59 vagrant-centos65 kernel: scsi 28:0:0:0: Direct-Access     ATA      VBOX HARDDISK    1.0  PQ: 0 ANSI: 5
Mar 12 14:05:59 vagrant-centos65 kernel: ata30: SATA link up 3.0 Gbps (SStatus 123 SControl 300)
Mar 12 14:05:59 vagrant-centos65 kernel: ata30.00: ATA-6: VBOX HARDDISK, 1.0, max UDMA/133
Mar 12 14:05:59 vagrant-centos65 kernel: ata30.00: 2097152 sectors, multi 128: LBA48 NCQ (depth 31/32)
Mar 12 14:05:59 vagrant-centos65 kernel: ata30.00: configured for UDMA/133
Mar 12 14:05:59 vagrant-centos65 kernel: scsi 29:0:0:0: Direct-Access     ATA      VBOX HARDDISK    1.0  PQ: 0 ANSI: 5

//...

Mar 12 14:05:59 vagrant-centos65 kernel: sd 0:0:0:0: [sda] 16777216 512-byte logical blocks: (8.58 GB/8.00 GiB)
Mar 12 14:05:59 vagrant-centos65 kernel: sd 0:0:0:0: [sda] Write Protect is off
Mar 12 14:05:59 vagrant-centos65 kernel: sd 0:0:0:0: [sda] Write cache: enabled, read cache: enabled, doesn't support DPO or FUA
Mar 12 14:05:59 vagrant-centos65 kernel: sda: sda1 sda2

// ...

Mar 12 14:05:59 vagrant-centos65 kernel: unknown partition table
Mar 12 14:05:59 vagrant-centos65 kernel: sd 18:0:0:0: [sds] Attached SCSI disk
Mar 12 14:05:59 vagrant-centos65 kernel: sd 29:0:0:0: [sdad] 2097152 512-byte logical blocks: (1.07 GB/1.00 GiB)
Mar 12 14:05:59 vagrant-centos65 kernel: sd 29:0:0:0: [sdad] Write Protect is off
Mar 12 14:05:59 vagrant-centos65 kernel: sd 29:0:0:0: [sdad] Write cache: enabled, read cache: enabled, doesn't support DPO or FUA
Mar 12 14:05:59 vagrant-centos65 kernel: sdad:

Mar 12 14:05:59 vagrant-centos65 kernel: sd 0:0:0:0: Attached scsi generic sg0 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 1:0:0:0: Attached scsi generic sg1 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 2:0:0:0: Attached scsi generic sg2 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 3:0:0:0: Attached scsi generic sg3 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 4:0:0:0: Attached scsi generic sg4 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 5:0:0:0: Attached scsi generic sg5 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 6:0:0:0: Attached scsi generic sg6 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 7:0:0:0: Attached scsi generic sg7 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 8:0:0:0: Attached scsi generic sg8 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 9:0:0:0: Attached scsi generic sg9 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 10:0:0:0: Attached scsi generic sg10 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 11:0:0:0: Attached scsi generic sg11 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 12:0:0:0: Attached scsi generic sg12 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 13:0:0:0: Attached scsi generic sg13 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 14:0:0:0: Attached scsi generic sg14 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 15:0:0:0: Attached scsi generic sg15 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 16:0:0:0: Attached scsi generic sg16 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 17:0:0:0: Attached scsi generic sg17 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 18:0:0:0: Attached scsi generic sg18 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 19:0:0:0: Attached scsi generic sg19 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 20:0:0:0: Attached scsi generic sg20 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 21:0:0:0: Attached scsi generic sg21 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 22:0:0:0: Attached scsi generic sg22 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 23:0:0:0: Attached scsi generic sg23 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 24:0:0:0: Attached scsi generic sg24 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 25:0:0:0: Attached scsi generic sg25 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 26:0:0:0: Attached scsi generic sg26 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 27:0:0:0: Attached scsi generic sg27 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 28:0:0:0: Attached scsi generic sg28 type 0
Mar 12 14:05:59 vagrant-centos65 kernel: sd 29:0:0:0: Attached scsi generic sg29 type 0
```

```c
/**
 *	sd_format_disk_name - format disk name
 *	@prefix: name prefix - ie. "sd" for SCSI disks
 *	@index: index of the disk to format name for
 *	@buf: output buffer
 *	@buflen: length of the output buffer
 *
 *	SCSI disk names starts at sda.  The 26th device is sdz and the
 *	27th is sdaa.  The last one for two lettered suffix is sdzz
 *	which is followed by sdaaa.
 *
 *	This is basically 26 base counting with one extra 'nil' entry
 *	at the beggining from the second digit on and can be
 *	determined using similar method as 26 base conversion with the
 *	index shifted -1 after each digit is computed.
 *
 *	CONTEXT:
 *	Don't care.
 *
 *	RETURNS:
 *	0 on success, -errno on failure.
 */
static int sd_format_disk_name(char *prefix, int index, char *buf, int buflen)
{
	const int base = 'z' - 'a' + 1;
	char *begin = buf + strlen(prefix);
	char *end = buf + buflen;
	char *p;
	int unit;

	p = end - 1;
	*p = '\0';
	unit = base;
	do {
		if (p == begin)
			return -EINVAL;
		*--p = 'a' + (index % unit);
		index = (index / unit) - 1;
	} while (index >= 0);

	memmove(begin, p, end - p);
	memcpy(buf, prefix, strlen(prefix));

	return 0;
}
```