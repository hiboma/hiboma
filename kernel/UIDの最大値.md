以前調べた社内資料をサルベージ

----

# Linux 32bit/64bit  での uidの上限値はいくつ? 型は? 

## 結論 

x86の32bit/64bitのlibcでは uid_t は unsigned int として扱われる。ただし、

 - stat(1)で ( 1 << 32 ) - 1 みたいな大きい値の uidを出力するとオーバーフローする環境がある
   - stat(1)がuid_tをsigned int として扱ってるから
    - CentOS4.6/32bitだとオーバーフロー => coreutilsのバグだと思います
    - CentOS5.2/64bit では正常に出力された 

ということで実践的には uid_t は signed int として見ておけば よいんではないかということでFA? ( そんなにアカウント作らないyo!)

(ただし上記のstatの例のように、他のライブラリが型を正しく扱ってない場合はどうなるか分からない)

## 以下は調査過程でのメモ 

#### ＠ Linux client.local 2.6.9-78.0.13.plus.c4 #1 Tue Jan 20 22:01:16 EST 2009 i686 i686 i386 GNU/Linux 

32bitでは uid_t = unsgined int としてヘッダに定義されている

```
/usr/include/sys/types.h:typedef __uid_t uid_t;
/usr/include/bits/types.h:__STD_TYPE __UID_T_TYPE __uid_t;      /* Type of user identifications.  */
/usr/include/bits/typesizes.h:#define __UID_T_TYPE              __U32_TYPE
/usr/include/bits/types.h:#define __U32_TYPE            unsigned int
```

####  ＠ Linux build.**.local 2.6.18-92.el5xen #1 SMP Tue Jun 10 19:20:18 EDT 2008 x86_64 x86_64 x86_64 GNU/Linux === 

64bitでも uid_t = unsgined int としてヘッダに定義されている

```
typedef __uid_t uid_t;
/usr/include/bits/types.h:__STD_TYPE __UID_T_TYPE __uid_t;	/* Type of user identifications.  */
/usr/include/bits/types.h:__STD_TYPE __UID_T_TYPE __uid_t;	/* Type of user identifications.  */
/usr/include/bits/typesizes.h:#define __UID_T_TYPE		__U32_TYPE
/usr/include/bits/types.h:#define __U32_TYPE		unsigned int
```

### coreutils/src/stat.c 

 - CentOS4.6が使ってるcoreutils/statのソース
  - st_uidを "%d" (signed int )として出力しているので、31bitより大きい値で オーバーフローする

```c
// coreutils-5.2.1/src/stat.c
485     case 'u':
486       strcat (pformat, "d"); // d  ... signed int までしか出せない
487       printf (pformat, statbuf->st_uid);
488       break;
```

 - CentOS5.2が使ってるcoreuitls/statのソース
  - st_uidlを "%lu"(unsigned long int )として出力しているので 32bitの値も扱える

```c
//coreutils-5.92/src/stat.c
463     case 'u':
464       xstrcat (pformat, buf_len, "lu"); // lu .. unsigned long int 
465       printf (pformat, (unsigned long int) statbuf->st_uid); // キャストしている
466       break;
```

## 実際にシェルでテストした結果

 - CentOS4.6/32bitだとcoreutilsは uidを signed int として扱う。
  -  1 << 31 より大きい値で オーバーフローする

```sh
# 2 ** 31 でオーバーフロー
chown 2147483648 /tmp/hiboma2
stat /tmp/hiboma2 | grep  Uid
Access: (0644/-rw-r--r--)  Uid: (-2147483648/ UNKNOWN)   Gid: (    0/    root)

# ( 2 ** 31 ) - 1  までなら正常に出力できる
chown 2147483647 /tmp/hiboma2
stat /tmp/hiboma2 | grep  Uid
Access: (0644/-rw-r--r--)  Uid: (2147483647/ hiboma2)   Gid: (    0/    root)
```

 - CentOS5/64bit

```sh
sudo chown 4294967295 /tmp/hoge
stat /tmp/hoge                 
Access: (0644/-rw-r--r--)  Uid: (4294967294/nfsnobody)   Gid: (  513/foo)
```

## 課題

下記に書いてある事はカーネルの実装の話なので、ユーザー空間のみ扱う際には意識する必要の無い話です。ので、読み飛ばしておkです。

調べたのはlibcのヘッダだけなので、カーネル内部のことには踏み込んでいない。ので、カーネルの方で気になった事を課題として。

カーネルの内部では

```c
// include/asm-i386/posix_types.h
typedef unsigned short  __kernel_uid_t;
typedef unsigned short  __kernel_old_uid_t;
typedef unsigned int    __kernel_uid32_t;

// include/asm-x86_64/posix_types.h
typedef unsigned int    __kernel_uid_t;
typedef unsigned short  __kernel_uid16_t;
typedef __kernel_uid_t __kernel_uid32_t;
typedef unsigned short __kernel_old_uid_t;
```

という風にuid_tの型が複数ある。互換性とかそんな感じ？

 - ext3のstruct inode の uidを入れておくプロパティの型が

```c
__le16  i_uid;          /* Low 16 bits of Owner Uid */
```

とあって、型が＿＿le16( リトルエンディアンの16bit) なんだけど、 ここの扱いはどうなるんだろ?

### 課題の調査

* 4/27追記

 - ext3_inodeのUIDが16bitか、32bitかの情報はsuper_blockが保持している
  - test_opt (inode->i_sb, NO_UID32)
  - 32bitなら16bitでUIDを分割して保持する
 - ディスクからreadするとき、writeする時にバイトオーダーの変換

ディスクのinodeの情報を読み取るメソッド

```c

2491 void ext3_read_inode(struct inode * inode){
/* ... */
2509         // UIDの下位16バイトのバイトオーダーの変換
2510         inode->i_uid = (uid_t)le16_to_cpu(raw_inode->i_uid_low);
2511         inode->i_gid = (gid_t)le16_to_cpu(raw_inode->i_gid_low);
2512         if(!(test_opt (inode->i_sb, NO_UID32))) {
2513                 // 16bitシフトして、UIDの上位16bit分を加算する
2514                 inode->i_uid |= le16_to_cpu(raw_inode->i_uid_high) << 16;
2515                 inode->i_gid |= le16_to_cpu(raw_inode->i_gid_high) << 16;
2516         }
```

ディスクのinodeの情報を更新するメソッド

```c
2617 static int ext3_do_update_inode(handle_t *handle,
2618                                 struct inode *inode,
2619                                 struct ext3_iloc *iloc)
2620 {
2621         struct ext3_inode *raw_inode = ext3_raw_inode(iloc);
2622         struct ext3_inode_info *ei = EXT3_I(inode);
2623         struct buffer_head *bh = iloc->bh;
2624         int err = 0, rc, block;
2625 
2626         /* For fields not not tracking in the in-memory inode,
2627          * initialise them to zero for new inodes. */
2628         if (ei->i_state & EXT3_STATE_NEW)
2629                 memset(raw_inode, 0, EXT3_SB(inode->i_sb)->s_inode_size);
2630 
2631         raw_inode->i_mode = cpu_to_le16(inode->i_mode);
2632         if(!(test_opt(inode->i_sb, NO_UID32))) {
2633                 // UIDが32bit表現の環境
2634                 // 下位16bitoを保存
2635                 raw_inode->i_uid_low = cpu_to_le16(low_16_bits(inode->i_uid));
2636                 raw_inode->i_gid_low = cpu_to_le16(low_16_bits(inode->i_gid));
2637 /*
2638  * Fix up interoperability with old kernels. Otherwise, old inodes get
2639  * re-used with the upper 16 bits of the uid/gid intact
2640  */
2641                 if(!ei->i_dtime) {
2642                         // 上位16bitを保存
2643                         raw_inode->i_uid_high =
2644                                 cpu_to_le16(high_16_bits(inode->i_uid));
2645                         raw_inode->i_gid_high =
2646                                 cpu_to_le16(high_16_bits(inode->i_gid));
2647                 } else {
2648                         raw_inode->i_uid_high = 0;
2649                         raw_inode->i_gid_high = 0;
2650                 }
2651         } else {
2652                 raw_inode->i_uid_low =
2653                         cpu_to_le16(fs_high2lowuid(inode->i_uid));
2654                 raw_inode->i_gid_low =
2655                         cpu_to_le16(fs_high2lowgid(inode->i_gid));
2656                 raw_inode->i_uid_high = 0;
2657                 raw_inode->i_gid_high = 0;
2658         }
```



