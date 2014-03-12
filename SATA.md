
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