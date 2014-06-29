
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