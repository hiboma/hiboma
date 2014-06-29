
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