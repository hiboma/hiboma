
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
 