# SHOW BINLOG EVENTS: Wrong offset or I/O error

次に書かれているバグを踏んでいる MySQL をデバッグした話になります。いろいろ調べてこのバグレポートを見つけました

 * https://gcc.gnu.org/bugzilla/show_bug.cgi?id=38562
 * http://bugs.mysql.com/bug.php?id=48357

```
A patch for this bug has been committed. After review, it may
be pushed to the relevant source trees for release in the next
version. You can access the patch from:

  http://lists.mysql.com/commits/89843

3195 Luis Soares	2009-11-09
      BUG#48357: SHOW BINLOG EVENTS: Wrong offset or I/O error
      
      In function log_event.cc:Query_log_event::write, there was a cast that
      was triggering undefined behavior. The offending cast is the
      following:
      
        write_str_with_code_and_len((char **)(&start),
                                    catalog, catalog_len, Q_CATALOG_NZ_CODE);
      
      This results in calling write_str_with_code_and_len with first
      argument pointing to a (char **) while "start" is itself a pointer to
      uchar (uchar *). Inside write_str_with_..., the content of start is
      then be updated:
      
        (*dst)+= len;
      
      The instruction above would cause the (*dst) pointer (ie, the "start"
      argument, from the caller point of view, and which actually points to
      uchar instead of pointing to char) to be updated so that it would
      increment catalog_len. However, this seems to break strict-aliasing
      rules ultimately causing the increment and assignment to behave
      unexpectedly.
      
      We fix this by removing the cast and by making the types match.
[12 Nov 2009 22:34] Omer Barnir
````

## バグを再現する環境

 * CentOS6.5 x86_64
  * MySQL は自前ビルドの MySQL-server-community-5.0.82
  * 過去にビルドされたもで gcc は `gcc-4.4.7-4.el6.x86_64`

以降、バグを含むバイナリを **バグバイナリ** 、再ビルドしたものを **修正バイナリ** として呼びます

## バグの再現

okkun が見つけてきたやつを、ちょっと手を加えて書いています

#### 1. バイナリログを出す設定にしておく

``` 
# /etc/my.cnf
log_bin=test-bin
```

バイナリログ意外の設定はバグの再現に影響しないため任意の記述で構いません

#### 2. テーブルを作る

```
CREATE TABLE `testtable` (
  `test_id` int(2) NOT NULL auto_increment,
  `create_date` datetime NOT NULL default '0000-00-00 00:00:00',
  `name` text,
  PRIMARY KEY  (`test_id`)
);
```

#### 3. 適当に INSERT する

```
# 目grep しやすいように @@@@@@ を混ぜてます
INSERT INTO `testtable` (`name`, `create_date`) VALUES ('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@', NOW()
```

#### 4. binlog が物故割れている

ここからがバグの症状

 * binlog のデータが壊れているため読み出せない
 * hexdump を取ると `use kowareru` じゃなくて `SYSTEMkowreu` になっている
   * クエリによってはもっと複雑な壊れかたをする

```
$ sudo mysqlbinlog /var/lib/mysql/test-bin.000001 
/*!40019 SET @@session.max_insert_delayed_threads=0*/;
/*!50003 SET @OLD_COMPLETION_TYPE=@@COMPLETION_TYPE,COMPLETION_TYPE=0*/;
DELIMITER /*!*/;
# at 4
#140630 15:09:33 server id 1  end_log_pos 98    Start: binlog v 4, server v 5.0.82-community-log created 140630 15:09:33 at startup
# Warning: this binlog was not closed properly. Most probably mysqld crashed writing it.
ROLLBACK/*!*/;
# at 98
#140630 15:09:55 server id 1  end_log_pos 126   Intvar
SET INSERT_ID=137/*!*/;
ERROR: Error in Log_event::read_log_event(): 'Found invalid event in binary log', data_len: 161, event_type: 2
DELIMITER ;
# End of log file
ROLLBACK /* added by mysqlbinlog */;
/*!50003 SET COMPLETION_TYPE=@OLD_COMPLETION_TYPE*/;

$ sudo hexdump -C /var/lib/mysql/test-bin.000001 
00000000  fe 62 69 6e 1d ff b0 53  0f 01 00 00 00 5e 00 00  |.bin...S.....^..|
00000010  00 62 00 00 00 01 00 04  00 35 2e 30 2e 38 32 2d  |.b.......5.0.82-|
00000020  63 6f 6d 6d 75 6e 69 74  79 2d 6c 6f 67 00 00 00  |community-log...|
00000030  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00000040  00 00 00 00 00 00 00 00  00 00 00 1d ff b0 53 13  |..............S.|
00000050  38 0d 00 08 00 12 00 04  04 04 04 12 00 00 4b 00  |8.............K.|
00000060  04 1a 33 ff b0 53 05 01  00 00 00 1c 00 00 00 7e  |..3..S.........~|
00000070  00 00 00 00 00 02 89 00  00 00 00 00 00 00 33 ff  |..............3.|
00000080  b0 53 02 01 00 00 00 a1  00 00 00 1f 01 00 00 00  |.S..............|
00000090  00 01 00 00 00 00 00 00  00 08 00 00 19 00 00 00  |................|
000000a0  40 00 00 01 00 00 00 00  00 00 00 00 06 03 04 08  |@...............|
000000b0  00 08 00 08 00 05 06 53  59 53 54 45 4d 6b 6f 77  |.......SYSTEMkow|
000000c0  61 72 65 72 75 00 49 4e  53 45 52 54 20 49 4e 54  |areru.INSERT INT|
000000d0  4f 20 60 74 65 73 74 74  61 62 6c 65 60 20 28 60  |O `testtable` (`|
000000e0  6e 61 6d 65 60 2c 20 60  63 72 65 61 74 65 5f 64  |name`, `create_d|
000000f0  61 74 65 60 29 20 56 41  4c 55 45 53 20 28 27 40  |ate`) VALUES ('@|
00000100  40 40 40 40 40 40 40 40  40 40 40 40 40 40 40 40  |@@@@@@@@@@@@@@@@|
00000110  40 40 40 40 40 40 40 40  40 40 40 40 27 2c 20 4e  |@@@@@@@@@@@@', N|
00000120  4f 57 28 29 29                                    |OW())|
00000125
```

再現手順とどういうバグなのかは okkun が全部まとめてくれていたのでかなり楽を出来た :sushi:

----

これ以降はどうやって冒頭のバグレポートに辿り着いたかを連ねています。後からまとめた物なので細部ははしょっています。すんなり調べられた訳じゃなくて いろいろハマって時間がかかっています

## strace でシステムコールを調べる

まずは問題のあるクエリの strace を取ってみてた

```
$ sudo gdb -p `sudo cat /var/lib/mysql/foo-bar.pid`
```

```
mysql> use kowareru;
mysql> INSERT INTO `testtable` (`name`, `create_date`) VALUES ('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@', NOW())
```

#### バグバイナリ

```
[pid 18263] read(27, "\3INSERT INTO `testtable` (`name`, `create_date`) VALUES ('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@', NOW())", 96) = 96
[pid 18263] rt_sigprocmask(SIG_BLOCK, ~[RTMIN RT_1], [HUP INT QUIT PIPE ALRM TERM TSTP], 8) = 0
[pid 18263] rt_sigprocmask(SIG_SETMASK, [HUP INT QUIT PIPE ALRM TERM TSTP], NULL, 8) = 0
[pid 18263] fcntl(27, F_SETFL, O_RDWR|O_NONBLOCK) = 0
[pid 18263] gettimeofday({1404098263, 181455}, NULL) = 0
[pid 18263] sched_setscheduler(18263, SCHED_OTHER, { 6 }) = -1 EINVAL (Invalid argument)
[pid 18263] gettimeofday({1404098263, 181601}, NULL) = 0
[pid 18263] pwrite(29, "\1\0-\0\376\200\0\0\0\17\235\32[Q\22\0\0\35\0@@@@@@@@@@@@@@@@@@@@@@@@@@@@@", 48, 5380) = 48
[pid 18263] gettimeofday({1404098263, 181987}, NULL) = 0
[pid 18263] write(11, "\327\326\260S\5\1\0\0\0\34\0\0\0\"\5\0\0\0\0\2\200\0\0\0\0\0\0\0\327\326\260S\2\1\0\0\0\241\0\0\0\303\5\0\0\0\0\2\0\0\0\0\0\0\0\10\0\0\31\0\0\0@\0\0\1\0\0\0\0
\0\0\0\0\6\3\4\10\0\10\0!\0\5\6SYSTEMkowareru\0INSERT INTO `testtable` (`name`, `create_date`) VALUES ('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@', NOW())", 195) = 195
```

#### 修正バイナリ

```
[pid 19004] read(27, "\3INSERT INTO `testtable` (`name`, `create_date`) VALUES ('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@', NOW())", 96) = 96
[pid 19004] rt_sigprocmask(SIG_BLOCK, ~[RTMIN RT_1], [HUP INT QUIT PIPE ALRM TERM TSTP], 8) = 0
[pid 19004] rt_sigprocmask(SIG_SETMASK, [HUP INT QUIT PIPE ALRM TERM TSTP], NULL, 8) = 0
[pid 19004] fcntl(27, F_SETFL, O_RDWR|O_NONBLOCK) = 0
[pid 19004] gettimeofday({1404098513, 629372}, NULL) = 0
[pid 19004] sched_setscheduler(19004, SCHED_OTHER, { 6 }) = -1 EINVAL (Invalid argument)
[pid 19004] gettimeofday({1404098513, 629624}, NULL) = 0
[pid 19004] gettimeofday({1404098513, 630857}, NULL) = 0
[pid 19004] write(11, "\321\327\260S\5\1\0\0\0\34\0\0\0~\0\0\0\0\0\2\204\0\0\0\0\0\0\0\321\327\260S\2\1\0\0\0\252\0\0\0(\1\0\0\0\0\2\0\0\0\0\0\0\0\10\0\0\"\0\0\0@\0\0\1\0\0\0\0\0\0\
0\0\6\3std\4\10\0\10\0!\0\5\6SYSTEMkowareru\0INSERT INTO `testtable` (`name`, `create_date`) VALUES ('@@@@@@@@@@@@@@@@@@@@@@@@@@@@@', NOW())", 198) = 198
```

 * クライアントから read(2) しているクエリは特に異常が無さそう
 * write(2) する際に `SYSTEM` が混入しているが、成否の違いがよく分からない
 * 書き込んでいる文字列の長さは違う

 ## ltrace でメモリの操作を調べる

strace はシステムコールを追う事はできるが、 システムコール以外、例えば MySQL がメモリをどう操作したか (malloc や memcpy 等) は追えない

ということで ltrace でトレースを取った

```
sudo ltrace -p `sudo cat /var/lib/mysql/foo-bar.pid`
```

#### バグバイナリ

ltrace から下記の出力が binlog の操作っぽいのを見つけた

```
# 一部省略しています

# 0x1b97c80 がヒープに確保しているバッファ

[pid 11915] memcpy(0x1b97c80, "\031)\260S\005\001", 19)                   
[pid 11915] memcpy(0x1b97c93, "\002O", 9)                                 
[pid 11915] memmove(0x7fdd5072618d, 0x8203ab, 3, 0, 0x1410000)            
[pid 11915] memmove(0x7fdd50726196, 0x86d9f9, 6, 524296, 0x1410000)       # SYSTEM の文字列をコピーしている
[pid 11915] memcpy(0x1b97c9c, "\031)\260S\002\001", 19)                   
[pid 11915] memcpy(0x1b97caf, "\001", 13)                                 
[pid 11915] memcpy(0x1b97cbc, "", 31)         # ここの長さが違う
[pid 11915] memcpy(0x1b97cdb, "kowareru", 9)                              
[pid 11915] memcpy(0x1b97ce4, "INSERT INTO `testtable` (`name`,"..., 95)  
```

#### 修正バイナリ

```
# 0x34b2220 がヒープに確保しているバッファ

[pid 12382] memcpy(0x34b2220, "\356)\260S\005\001", 19)                   
[pid 12382] memcpy(0x34b2233, "\002P", 9)                                 
[pid 12382] memmove(0x7fdfd56a428d, 0x959004, 3, 0x959004, 0x7e0000)      
[pid 12382] memcpy(0x7fdfd56a4291, "\b", 6)                               
[pid 12382] memmove(0x7fdfd56a4299, 0x9df2bf, 6, 0x9df2bf, 0x7e0000)      # SYSTEM の文字列をコピーしている
[pid 12382] memcpy(0x34b223c, "\356)\260S\002\001", 19)                   
[pid 12382] memcpy(0x34b224f, "\002", 13)                                 
[pid 12382] memcpy(0x34b225c, "", 34)          # ここの長さが違う
[pid 12382] memcpy(0x34b227e, "kowareru", 9)                              
[pid 12382] memcpy(0x34b2287, "INSERT INTO `testtable` (`name`,"..., 95)  
```

コピーしている値は違っていても、長さが同じである。ただし一カ所だけ memcpy している長さが違う場所がある

 * memcpy の長さが違う => アドレスがズレる
 * 意図しない文字列が混入する原因では?

として、gdb も使いつつで調査を進めました。

## gdb でソースを探す

 * ~~memcpy をしている箇所のコードが分からないので gdb で探しました~~
   * ltrace で Instruction Pointer を取る方法があった。後述
 * どこにブレークポイントしかけたらいいか分からないので適当に write(2) でアタリをつけて探した

```
$ sudo gdb -p `sudo cat /var/lib/mysql/foo-bar.pid`
(gdb) b write
Breakpoint 1 at 0x7f9b36fab6d0

Breakpoint 1, 0x00007f9b36fab6d0 in write () from /lib64/libpthread.so.0
(gdb) bt
#0  0x00007f9b36fab6d0 in write () from /lib64/libpthread.so.0
#1  0x000000000089cef8 in my_write (Filedes=11, Buffer=0x2135220 "\212\356\260S\005\001", Count=198, MyFlags=52) at my_write.c:38
#2  0x00000000008a462f in my_b_flush_io_cache (info=0xdd6bb8, need_append_buffer_lock=0) at mf_iocache.c:1750
#3  0x000000000066a84c in MYSQL_LOG::flush_and_sync (this=0xdd6a00) at log.cc:1818
#4  0x000000000066b065 in MYSQL_LOG::write (this=0xdd6a00, event_info=0x7f9b34945690) at log.cc:2001
#5  0x0000000000645eea in mysql_insert (thd=0x2976e00, table_list=0x7f9b20004ba8, fields=..., values_list=..., update_fields=..., update_values=..., duplic=DUP_ERROR, ignore=false)
    at sql_insert.cc:925
#6  0x00000000005cb50c in mysql_execute_command (thd=0x2976e00) at sql_parse.cc:3833
#7  0x00000000005d3119 in mysql_parse (thd=0x2976e00, inBuf=0x7f9b20004a70 "INSERT INTO `testtable` (`name`, `create_date`) VALUES ('", '@' <repeats 29 times>, "', NOW())", 
    length=95, found_semicolon=0x7f9b34946c10) at sql_parse.cc:6452
#8  0x00000000005c6122 in dispatch_command (command=COM_QUERY, thd=0x2976e00, 
    packet=0x2978fd1 "INSERT INTO `testtable` (`name`, `create_date`) VALUES ('", '@' <repeats 29 times>, "', NOW())", packet_length=96) at sql_parse.cc:1973
#9  0x00000000005c52bf in do_command (thd=0x2976e00) at sql_parse.cc:1654
#10 0x00000000005c4274 in handle_one_connection (arg=0x2976e00) at sql_parse.cc:1246
#11 0x00007f9b36fa49d1 in start_thread () from /lib64/libpthread.so.0
#12 0x00007f9b3661db6d in clone () from /lib64/libc.so.6
```

上記ログの `MYSQL_LOG::write` 付近のソースを読みつつ、最終的に `Query_log_event::write` に辿り着いた

 * バッファに `SYSTEMkowreu` が書き出される箇所をステップ実行探した
 * memcpy しか手がかりが無いのでどう探したら効率が良いのか、TODO

Query_log_event::write は次の通り 

```c++
/* 長いのでコメント部分は削った */

bool Query_log_event::write(IO_CACHE* file)
{
  uchar buf[QUERY_HEADER_LEN + MAX_SIZE_LOG_EVENT_STATUS];
  uchar *start, *start_of_status;
  ulong event_length;

  if (!query)
    return 1;                                   // Something wrong with event

  int4store(buf + Q_THREAD_ID_OFFSET, slave_proxy_id);
  int4store(buf + Q_EXEC_TIME_OFFSET, exec_time);
  buf[Q_DB_LEN_OFFSET] = (char) db_len;
  int2store(buf + Q_ERR_CODE_OFFSET, error_code);

  start_of_status= start= buf+QUERY_HEADER_LEN;
  if (flags2_inited)
  {
    *start++= Q_FLAGS2_CODE;
    int4store(start, flags2);
    start+= 4;
  }
  if (sql_mode_inited)
  {
    *start++= Q_SQL_MODE_CODE;
    int8store(start, (ulonglong)sql_mode);
    start+= 8;
  }
  if (catalog_len) // i.e. this var is inited (false for 4.0 events)
  {
    write_str_with_code_and_len((char **)(&start),
                                catalog, catalog_len, Q_CATALOG_NZ_CODE);
  }
  if (auto_increment_increment != 1)
  {
    *start++= Q_AUTO_INCREMENT;
    int2store(start, auto_increment_increment);
    int2store(start+2, auto_increment_offset);
    start+= 4;
  }
  if (charset_inited)
  {
    *start++= Q_CHARSET_CODE;
    memcpy(start, charset, 6);
    start+= 6;
  }
  if (time_zone_len)
  {
    /* In the TZ sys table, column Name is of length 64 so this should be ok */
    DBUG_ASSERT(time_zone_len <= MAX_TIME_ZONE_NAME_LENGTH);
    write_str_with_code_and_len((char **)(&start),
                                time_zone_str, time_zone_len, Q_TIME_ZONE_CODE);
  }
  if (lc_time_names_number)
  {
    DBUG_ASSERT(lc_time_names_number <= 0xFFFF);
    *start++= Q_LC_TIME_NAMES_CODE;
    int2store(start, lc_time_names_number);
    start+= 2;
  }
  if (charset_database_number)
  {
    DBUG_ASSERT(charset_database_number <= 0xFFFF);
    *start++= Q_CHARSET_DATABASE_CODE;
    int2store(start, charset_database_number);
    start+= 2;
  }
  if (table_map_for_update)
  {
    *start++= Q_TABLE_MAP_FOR_UPDATE_CODE;
    int8store(start, table_map_for_update);
    start+= 8;
  }

  /* Store length of status variables */
  status_vars_len= (uint) (start-start_of_status);
  DBUG_ASSERT(status_vars_len <= MAX_SIZE_LOG_EVENT_STATUS);
  int2store(buf + Q_STATUS_VARS_LEN_OFFSET, status_vars_len);

  /*
    Calculate length of whole event
    The "1" below is the \0 in the db's length
  */
  event_length= (uint) (start-buf) + get_post_header_size_for_derived() + db_len + 1 + q_len;

  return (write_header(file, event_length) ||
          my_b_safe_write(file, (byte*) buf, QUERY_HEADER_LEN) ||
          write_post_header_for_derived(file) ||
          my_b_safe_write(file, (byte*) start_of_status,
                          (uint) (start-start_of_status)) ||
          my_b_safe_write(file, (db) ? (byte*) db : (byte*)"", db_len + 1) ||
          my_b_safe_write(file, (byte*) query, q_len)) ? 1 : 0;
}
```

## gdb でステップ実行

`Query_log_event::write` まで絞り込めたので、ltrace で見つけた memcpy の長さの違い (31 と 34) がどこで生じているのか gdb のステップ実行と `display` を使っておった

#### バグバイナリ

ソースを読んだ感じだと `display start - start_of_status` が memcpy の長さに相当しているようだったので、この数値を追ってみる事にした

```c
          my_b_safe_write(file, (byte*) start_of_status,
                          (uint) (start-start_of_status)) ||
```

バグバイナリではアドレスの長さが途中 19 => 17 に後退している。ポインタを増減させる操作しかしてないのに長さが減っていて怪しい

```
# dispaly を使うと、ステップを実行するたびに式を評価してくれる
(gdb) display start - start_of_status
1: start - start_of_status = 0
(gdb) n

// 中略...

1203        start+= 4;
1: start - start_of_status = 0
(gdb)
1205      if (sql_mode_inited)
1: start - start_of_status = 5
(gdb)
1207        *start++= Q_SQL_MODE_CODE;
1: start - start_of_status = 5
(gdb)
1208        int8store(start, (ulonglong)sql_mode);
1: start - start_of_status = 6
(gdb)

// ...

(gdb)
1211      if (catalog_len) // i.e. this var is inited (false for 4.0 events)
1: start - start_of_status = 14
(gdb)
1214                                    catalog, catalog_len, Q_CATALOG_NZ_CODE);
1: start - start_of_status = 14
(gdb)
1234      if (auto_increment_increment != 1)
1: start - start_of_status = 19
(gdb)

// ...

(gdb)
1244        memcpy(start, charset, 6);
1: start - start_of_status = 17
(gdb)
1245        start+= 6;
1: start - start_of_status = 17
(gdb)
1247      if (time_zone_len)
1: start - start_of_status = 23
(gdb)
1252                                    time_zone_str, time_zone_len, Q_TIME_ZONE_CODE);
1: start - start_of_status = 23
(gdb)
1254      if (lc_time_names_number)
1: start - start_of_status = 31
(gdb)

// ...

(gdb)
1142    bool Query_log_event::write(IO_CACHE* file)
1: start - start_of_status = 31
(gdb)
```

#### 修正バイナリ

```
1199      if (flags2_inited)
1: start - start_of_status = 0
(gdb)
1201        *start++= Q_FLAGS2_CODE;
1: start - start_of_status = 0
(gdb)
1202        int4store(start, flags2);
1: start - start_of_status = 1
(gdb)
1203        start+= 4;
1: start - start_of_status = 1
(gdb)
1205      if (sql_mode_inited)
1: start - start_of_status = 5
(gdb)
1207        *start++= Q_SQL_MODE_CODE;
1: start - start_of_status = 5
(gdb)
1208        int8store(start, (ulonglong)sql_mode);
1: start - start_of_status = 6
(gdb)
1209        start+= 8;
1: start - start_of_status = 6
(gdb)
1211      if (catalog_len) // i.e. this var is inited (false for 4.0 events)
1: start - start_of_status = 14
(gdb)
1214                                    catalog, catalog_len, Q_CATALOG_NZ_CODE);
1: start - start_of_status = 14
(gdb)
1234      if (auto_increment_increment != 1)
1: start - start_of_status = 19
(gdb)
1241      if (charset_inited)
1: start - start_of_status = 19
(gdb)
1243        *start++= Q_CHARSET_CODE;
1: start - start_of_status = 19
(gdb)
1244        memcpy(start, charset, 6);
1: start - start_of_status = 20
(gdb)
1245        start+= 6;
1: start - start_of_status = 20
(gdb)
1247      if (time_zone_len)
1: start - start_of_status = 26
(gdb)
1250        DBUG_ASSERT(time_zone_len <= MAX_TIME_ZONE_NAME_LENGTH);
1: start - start_of_status = 26
(gdb)
1252                                    time_zone_str, time_zone_len, Q_TIME_ZONE_CODE);
1: start - start_of_status = 26
(gdb)
1254      if (lc_time_names_number)
1: start - start_of_status = 34
(gdb)
1261      if (charset_database_number)
1: start - start_of_status = 34
(gdb)
1268      if (table_map_for_update)
1: start - start_of_status = 34
(gdb)
1289      status_vars_len= (uint) (start-start_of_status);
1: start - start_of_status = 34
(gdb)
1290      DBUG_ASSERT(status_vars_len <= MAX_SIZE_LOG_EVENT_STATUS);
1: start - start_of_status = 34
(gdb)
1291      int2store(buf + Q_STATUS_VARS_LEN_OFFSET, status_vars_len);
1: start - start_of_status = 34
(gdb)
1297      event_length= (uint) (start-buf) + get_post_header_size_for_derived() + db_len + 1 + q_len;
1: start - start_of_status = 34
(gdb)
1305              my_b_safe_write(file, (byte*) query, q_len)) ? 1 : 0;
1: start - start_of_status = 34
(gdb)
1301              write_post_header_for_derived(file) ||
1: start - start_of_status = 34
(gdb)
1305              my_b_safe_write(file, (byte*) query, q_len)) ? 1 : 0;
1: start - start_of_status = 34
(gdb)
1306    }
```

### disassemble しての比較

gdb で`$rip` (Instruction Pointer) を取れば命令のアドレスを取れる。

```
(gdb) p $rip
$6 = (void (*)(void)) 0x672175 <Query_log_event::write(IO_CACHE*)+967>
```

バイナリを objdump して $rip が一致する行を頑張って探す

```
  672142:       74 3d                   je     672181 <_ZN15Query_log_event5writeEP11st_io_cache+0x3d3>
  672144:       48 8b 45 b0             mov    -0x50(%rbp),%rax
  672148:       c6 00 04                movb   $0x4,(%rax)        #     *start++= Q_CHARSET_CODE;
  67214b:       48 83 c0 01             add    $0x1,%rax
  67214f:       48 89 45 b0             mov    %rax,-0x50(%rbp)
  672153:       48 8b 85 68 fd ff ff    mov    -0x298(%rbp),%rax
  67215a:       48 8d 88 a8 00 00 00    lea    0xa8(%rax),%rcx
  672161:       48 8b 45 b0             mov    -0x50(%rbp),%rax
  672165:       ba 06 00 00 00          mov    $0x6,%edx
  67216a:       48 89 ce                mov    %rcx,%rsi
  67216d:       48 89 c7                mov    %rax,%rdi
  672170:       e8 bb 14 e8 ff          callq  4f3630 <memcpy@plt>
  672175:       48 8b 45 b0             mov    -0x50(%rbp),%rax
  672179:       48 83 c0 06             add    $0x6,%rax         #     start+= 6;
  67217d:       48 89 45 b0             mov    %rax,-0x50(%rbp)
  672181:       48 8b 85 68 fd ff ff    mov    -0x298(%rbp),%rax
  672188:       8b 80 b0 00 00 00       mov    0xb0(%rax),%eax
  67218e:       85 c0                   test   %eax,%eax
```

```
(gdb) p $rip
$1 = (void (*)(void)) 0x5d98d3 <Query_log_event::write(IO_CACHE*)+1171>
(gdb) 
```

```
  5d98c9:       e9 c3 fc ff ff          jmpq   5d9591 <_ZN15Query_log_event5writeEP11st_io_cache+0x151>
  5d98ce:       66 90                   xchg   %ax,%ax             
  5d98d0:       c6 00 04                movb   $0x4,(%rax)          #  
  5d98d3:       8b 8b a8 00 00 00       mov    0xa8(%rbx),%ecx      # 
  5d98d9:       48 8d 50 01             lea    0x1(%rax),%rdx       # 
  5d98dd:       48 89 94 24 38 02 00    mov    %rdx,0x238(%rsp)     # 
  5d98e4:       00 
  5d98e5:       89 48 01                mov    %ecx,0x1(%rax)       # 
  5d98e8:       0f b7 83 ac 00 00 00    movzwl 0xac(%rbx),%eax     
  5d98ef:       66 89 42 04             mov    %ax,0x4(%rdx)
  5d98f3:       4c 8b b4 24 38 02 00    mov    0x238(%rsp),%r14     # 
  5d98fa:       00 
  5d98fb:       49 8d 7e 06             lea    0x6(%r14),%rdi       # 
  5d98ff:       49 89 fe                mov    %rdi,%r14
  5d9902:       48 89 bc 24 38 02 00    mov    %rdi,0x238(%rsp)
  5d9909:       00 
```

 * 修正バイナリとバグバイナリとで命令が全然違う
   * バグは memcpy の呼び出しが無い

## SHOW BINLOG EVENTS: Wrong offset or I/O error

バイナリを見てて詰みゲー感が出てきたので、 Query_log_event::write でググっていたら冒頭のバグレポートのページに辿り着いた

SHOW BINLOG EVENTS 知っていればもっと早く気がついたかも?

## mysql-test のテストスイート

```
cp /usr/sbin/mysqld ~/rpmbuild/BUILD/mysql-5.0.82/sql
cd ~/rpmbuild/BUILD/mysql-5.0.82/mysql-test
./mtr t/binlog.t
``

----

# メモ

調査後に気がついたメモ

## ltrace で Instruction Pointer を表示、gdb でソースを探す 

ltrace に `-i` を渡すとライブラリを呼び出す際の Instruction Pointer を出力できる

```
[pid 28991] [0x5d7985] strlen("std")                                                                            = 3
[pid 28991] [0x5d799b] strlen("kowareru")                                                                       = 8
[pid 28991] [0x5d3b64] pthread_mutex_lock(0xc58ce8, 0x7fd34c90e640, 0, 48, 0)                                   = 0
[pid 28991] [0x7997a2] memcpy(0x298f520, "\303\311\262S\005\001", 19)                                           = 0x298f520
[pid 28991] [0x7997a2] memcpy(0x298f533, "\002\262", 9)                                                         = 0x298f533
[pid 28991] [0x5d9821] memmove(0x7fd34c90e18d, 0x8203ab, 3, 0, 0x1490000)                                       = 0x7fd34c90e18d
[pid 28991] [0x5d98b5] memmove(0x7fd34c90e196, 0x29afdf8, 6, 786444, 0x1490000)                                 = 0x7fd34c90e196
[pid 28991] [0x7997a2] memcpy(0x298f53c, "\303\311\262S\002\001", 19)                                           = 0x298f53c
[pid 28991] [0x7997a2] memcpy(0x298f54f, "\001", 13)                                                            = 0x298f54f
[pid 28991] [0x7997a2] memcpy(0x298f55c, "", 31)                                                                = 0x298f55c
[pid 28991] [0x7997a2] memcpy(0x298f57b, "kowareru", 9)                                                         = 0x298f57b
[pid 28991] [0x7997a2] memcpy(0x298f584, "INSERT INTO `testtable` (`name`, `create_date`) VALUES ('@@@@@@@@@@@@@@@@@@@fdksajlk@@@@@@@@@@', NOW())", 103) = 0x298f584
[pid 28991] [0x79640d] write(10, "\303\311\262S\005\001", 203)                                                  = 203
```

ip (rip, eip) を取れれば gdb でブレークポイントを設定できる。問題の memcpy を実行している `0x7997a2` をブレークポイントにしてみよう

```
(gdb) b *0x7997a2
Breakpoint 1 at 0x7997a2: file mf_iocache.c, line 1618.
(gdb) c
Continuing.
[Switching to Thread 0x7fd34c910700 (LWP 28991)]

Breakpoint 1, 0x00000000007997a2 in my_b_safe_write (info=0xc58dd8, Buffer=<value optimized out>, Count=19) at mf_iocache.c:1618
(gdb) bt
#0  0x00000000007997a2 in my_b_safe_write (info=0xc58dd8, Buffer=<value optimized out>, Count=19) at mf_iocache.c:1618
#1  0x00000000005d8baa in Log_event::write_header (this=0x7fd34c90e4e0, file=0xc58dd8, event_data_length=<value optimized out>) at log_event.cc:658
#2  0x00000000005d91dd in Intvar_log_event::write (this=<value optimized out>, file=0xc58dd8) at log_event.cc:3648
#3  0x00000000005d3ed5 in MYSQL_LOG::write (this=0xc58ce0, event_info=0x7fd34c90e640) at log.cc:1965
#4  0x00000000005be44f in mysql_insert (thd=0x2998190, table_list=0x7fd348004af0, fields=..., values_list=..., update_fields=..., update_values=..., duplic=DUP_ERROR, ignore=false)
    at sql_insert.cc:925
#5  0x000000000056a235 in mysql_execute_command (thd=0x2998190) at sql_parse.cc:3833
#6  0x000000000056f33e in mysql_parse (thd=0x2998190, inBuf=<value optimized out>, length=<value optimized out>, found_semicolon=0x7fd34c90fc40) at sql_parse.cc:6452
#7  0x0000000000570ac9 in dispatch_command (command=COM_QUERY, thd=0x2998190, packet=<value optimized out>, packet_length=<value optimized out>) at sql_parse.cc:1973
#8  0x0000000000571a15 in do_command (arg=<value optimized out>) at sql_parse.cc:1654
#9  handle_one_connection (arg=<value optimized out>) at sql_parse.cc:1246
#10 0x00007fd3785fb9d1 in start_thread () from /lib64/libpthread.so.0
#11 0x00007fd377c74b6d in clone () from /lib64/libc.so.6
```

 * ip にブレークポイントを貼る場合はアドレスに * を付ける
 * ブレークポイントに達したら backtrace をとればどこから呼び出されているか分かって便利!!!

これが分かっていればもっと楽に解決できた ...
