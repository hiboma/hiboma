
```c
Query_log_event::Query_log_event(THD* thd_arg, const char* query_arg,
				 ulong query_length, bool using_trans,
				 bool suppress_use, THD::killed_state killed_status_arg)
  :Log_event(thd_arg,
             ((thd_arg->tmp_table_used || thd_arg->thread_specific_used) ? 
	        LOG_EVENT_THREAD_SPECIFIC_F : 0) |
	      (suppress_use ? LOG_EVENT_SUPPRESS_USE_F : 0),
	     using_trans),
   data_buf(0), query(query_arg), catalog(thd_arg->catalog),
   db(thd_arg->db), q_len((uint32) query_length),
   thread_id(thd_arg->thread_id),
   /* save the original thread id; we already know the server id */
   slave_proxy_id(thd_arg->variables.pseudo_thread_id),
   flags2_inited(1), sql_mode_inited(1), charset_inited(1),
   sql_mode(thd_arg->variables.sql_mode),
   auto_increment_increment(thd_arg->variables.auto_increment_increment),
   auto_increment_offset(thd_arg->variables.auto_increment_offset),
   lc_time_names_number(thd_arg->variables.lc_time_names->number),
   charset_database_number(0),
   table_map_for_update((ulonglong)thd_arg->table_map_for_update)
{
  time_t end_time;

  DBUG_EXECUTE_IF("debug_lock_before_query_log_event",
                  DBUG_SYNC_POINT("debug_lock.before_query_log_event", 10););

  if (killed_status_arg == THD::KILLED_NO_VALUE)
    killed_status_arg= thd_arg->killed;
  error_code=
    (killed_status_arg == THD::NOT_KILLED) ? thd_arg->net.last_errno :
    ((thd_arg->system_thread & SYSTEM_THREAD_DELAYED_INSERT) ? 0 :
     thd->killed_errno());
  
  time(&end_time);
  exec_time = (ulong) (end_time  - thd->start_time);
  catalog_len = (catalog) ? (uint32) strlen(catalog) : 0;
  /* status_vars_len is set just before writing the event */
  db_len = (db) ? (uint32) strlen(db) : 0;
  if (thd_arg->variables.collation_database != thd_arg->db_charset)
    charset_database_number= thd_arg->variables.collation_database->number;
  
  /*
    If we don't use flags2 for anything else than options contained in
    thd->options, it would be more efficient to flags2=thd_arg->options
    (OPTIONS_WRITTEN_TO_BINLOG would be used only at reading time).
    But it's likely that we don't want to use 32 bits for 3 bits; in the future
    we will probably want to reclaim the 29 bits. So we need the &.
  */
  flags2= (uint32) (thd_arg->options & OPTIONS_WRITTEN_TO_BIN_LOG);
  DBUG_ASSERT(thd->variables.character_set_client->number < 256*256);
  DBUG_ASSERT(thd->variables.collation_connection->number < 256*256);
  DBUG_ASSERT(thd->variables.collation_server->number < 256*256);
  int2store(charset, thd_arg->variables.character_set_client->number);
  int2store(charset+2, thd_arg->variables.collation_connection->number);
  int2store(charset+4, thd_arg->variables.collation_server->number);
  if (thd_arg->time_zone_used)
  {
    /*
      Note that our event becomes dependent on the Time_zone object
      representing the time zone. Fortunately such objects are never deleted
      or changed during mysqld's lifetime.
    */
    time_zone_len= thd_arg->variables.time_zone->get_name()->length();
    time_zone_str= thd_arg->variables.time_zone->get_name()->ptr();
  }
  else
    time_zone_len= 0;
  DBUG_PRINT("info",("Query_log_event has flags2: %lu  sql_mode: %lu",
                     (ulong) flags2, sql_mode));
}
```

Q_TIME_ZONE_CODE

```
(gdb) bt
#0  0x00007f1162a646d0 in write () from /lib64/libpthread.so.0
#1  0x000000000079640d in my_write (Filedes=10, Buffer=0x7f1130009a80 "\025T\256S\005\001", Count=185, MyFlags=52) at my_write.c:38
#2  0x0000000000799499 in my_b_flush_io_cache (info=0xc58dd8, need_append_buffer_lock=<value optimized out>) at mf_iocache.c:1750
#3  0x00000000005d0728 in MYSQL_LOG::flush_and_sync (this=<value optimized out>) at log.cc:1818
#4  0x00000000005d3ff3 in MYSQL_LOG::write (this=0xc58ce0, event_info=<value optimized out>) at log.cc:2001
#5  0x00000000005be44f in mysql_insert (thd=0x354e190, table_list=0x7f113000dbe0, fields=..., values_list=..., update_fields=..., update_values=..., duplic=DUP_ERROR, ignore=false)
    at sql_insert.cc:925
#6  0x000000000056a235 in mysql_execute_command (thd=0x354e190) at sql_parse.cc:3833
#7  0x000000000056f33e in mysql_parse (thd=0x354e190, inBuf=<value optimized out>, length=<value optimized out>, found_semicolon=0x7f11374d9c40) at sql_parse.cc:6452
#8  0x0000000000570ac9 in dispatch_command (command=COM_QUERY, thd=0x354e190, packet=<value optimized out>, packet_length=<value optimized out>) at sql_parse.cc:1973
#9  0x0000000000571a15 in do_command (arg=<value optimized out>) at sql_parse.cc:1654
#10 handle_one_connection (arg=<value optimized out>) at sql_parse.cc:1246
#11 0x00007f1162a5d9d1 in start_thread () from /lib64/libpthread.so.0
#12 0x00007f11620d6b6d in clone () from /lib64/libc.so.6
```

```
bool mysql_insert(THD *thd,TABLE_LIST *table_list,
                  List<Item> &fields,
                  List<List_item> &values_list,
                  List<Item> &update_fields,
                  List<Item> &update_values,
                  enum_duplicates duplic,
```

```
        if (mysql_bin_log.write(&qinfo) && transactional_table)
```

```
/*
  Query_log_event::Query_log_event()
  This is used by the SQL slave thread to prepare the event before execution.
*/

Query_log_event::Query_log_event(const char* buf, uint event_len,
                                 const Format_description_log_event *description_event,
                                 Log_event_type event_type)
  :Log_event(buf, description_event), data_buf(0), query(NullS),
   db(NullS), catalog_len(0), status_vars_len(0),
   flags2_inited(0), sql_mode_inited(0), charset_inited(0),
   auto_increment_increment(1), auto_increment_offset(1),
   time_zone_len(0), lc_time_names_number(0), charset_database_number(0),
   table_map_for_update(0)
{
// ...

    case Q_TIME_ZONE_CODE:
    {
      if (get_str_len_and_pointer(&pos, &time_zone_str, &time_zone_len, end))
      {
        DBUG_PRINT("info", ("Q_TIME_ZONE_CODE: query= 0"));
        query= 0;
        DBUG_VOID_RETURN;
      }
      break;
    }


//...
  if (time_zone_len)
    copy_str_and_move(&time_zone_str, &start, time_zone_len);

  /* A 2nd variable part; this is common to all versions */ 
  memcpy((char*) start, end, data_len);          // Copy db and query
  start[data_len]= '\0';              // End query with \0 (For safetly)
  db= (char *)start;
  query= (char *)(start + db_len + 1);
  q_len= data_len - db_len -1;
  DBUG_VOID_RETURN;
}
```

### strace でシステムコールを調べる

バグ版バイナリ

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

修正版バイナリ

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

### ltrace でメモリの操作を調べる

strace はシステムコールを追う事はできるが、 mysql がメモリをどう操作したかは追えない

```
sudo ltrace -p `sudo cat /var/lib/mysql/customer-db001.heteml.dev.pid`
```

バグ版バイナリ

```
[pid 11915] memcpy(0x1b97c80, "\031)\260S\005\001", 19)                   
[pid 11915] memcpy(0x1b97c93, "\002O", 9)                                 
[pid 11915] memmove(0x7fdd5072618d, 0x8203ab, 3, 0, 0x1410000)            
[pid 11915] memmove(0x7fdd50726196, 0x86d9f9, 6, 524296, 0x1410000)       
[pid 11915] memcpy(0x1b97c9c, "\031)\260S\002\001", 19)                   
[pid 11915] memcpy(0x1b97caf, "\001", 13)                                 
[pid 11915] memcpy(0x1b97cbc, "", 31)         # ここの長さが違う
[pid 11915] memcpy(0x1b97cdb, "kowareru", 9)                              
[pid 11915] memcpy(0x1b97ce4, "INSERT INTO `testtable` (`name`,"..., 95)  
```

修正版バイナリ

```
[pid 12382] memcpy(0x34b2220, "\356)\260S\005\001", 19)                   
[pid 12382] memcpy(0x34b2233, "\002P", 9)                                 
[pid 12382] memmove(0x7fdfd56a428d, 0x959004, 3, 0x959004, 0x7e0000)      
[pid 12382] memcpy(0x7fdfd56a4291, "\b", 6)                               
[pid 12382] memmove(0x7fdfd56a4299, 0x9df2bf, 6, 0x9df2bf, 0x7e0000)      
[pid 12382] memcpy(0x34b223c, "\356)\260S\002\001", 19)                   
[pid 12382] memcpy(0x34b224f, "\002", 13)                                 
[pid 12382] memcpy(0x34b225c, "", 34)          # ここの長さが違う
[pid 12382] memcpy(0x34b227e, "kowareru", 9)                              
[pid 12382] memcpy(0x34b2287, "INSERT INTO `testtable` (`name`,"..., 95)  
```

コピーしている値は違っていても、長さが同じ。ただし一カ所だけ memcpy している長さが違う場所がある

 * memcpy の長さが違う
 * アドレスがズレている
 * 意図しない文字列が混入する原因では?

とアタりをつけた

### gdb でステップ実行

31 と 34 の違いを追うために gdb の `display` を使った

バグ版バイナリではアドレスの長さが途中 19 => 17 に後退している。ポインタを増減させる操作しかしてないのに長さが減っていて怪しい

```
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

 * 修正バイナリとバグ版バイナリとで命令が全然違う
   * バグ版は memcpy の呼び出しが無い