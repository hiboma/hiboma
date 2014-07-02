

 * my_b_safe_write

## メモ

 * いろんな Event が定義されていて、それぞれに write メソッドが用意されてる
   * Query_log_event
   * Load_log_event
   * Log_event
   * Rotate_log_event
   * Create_file_log_event ...

```c
enum Log_event_type
{
  /*
    Every time you update this enum (when you add a type), you have to
    fix Format_description_log_event::Format_description_log_event().
  */
  UNKNOWN_EVENT= 0,
  START_EVENT_V3= 1,
  QUERY_EVENT= 2,
  STOP_EVENT= 3,
  ROTATE_EVENT= 4,
  INTVAR_EVENT= 5,
  LOAD_EVENT= 6,
  SLAVE_EVENT= 7,
  CREATE_FILE_EVENT= 8,
  APPEND_BLOCK_EVENT= 9,
  EXEC_LOAD_EVENT= 10,
  DELETE_FILE_EVENT= 11,
  /*
    NEW_LOAD_EVENT is like LOAD_EVENT except that it has a longer
    sql_ex, allowing multibyte TERMINATED BY etc; both types share the
    same class (Load_log_event)
  */
  NEW_LOAD_EVENT= 12,
  RAND_EVENT= 13,
  USER_VAR_EVENT= 14,
  FORMAT_DESCRIPTION_EVENT= 15,
  XID_EVENT= 16,
  BEGIN_LOAD_QUERY_EVENT= 17,
  EXECUTE_LOAD_QUERY_EVENT= 18,

  /*
    Add new events here - right above this comment!
    Existing events (except ENUM_END_EVENT) should never change their numbers
  */

  ENUM_END_EVENT /* end marker */
};
```

## Event Header

```cc
bool Log_event::write_header(IO_CACHE* file, ulong event_data_length)
{

  // #define LOG_EVENT_HEADER_LEN 19     /* the fixed header length */

  byte header[LOG_EVENT_HEADER_LEN];

// ...

  // #define EVENT_TYPE_OFFSET    4
  // #define SERVER_ID_OFFSET     5
  // #define EVENT_LEN_OFFSET     9
  // #define LOG_POS_OFFSET       13
  // #define FLAGS_OFFSET         17

  int4store(header, (ulong) when);              // timestamp
  header[EVENT_TYPE_OFFSET]= get_type_code();
  int4store(header+ SERVER_ID_OFFSET, server_id);
  int4store(header+ EVENT_LEN_OFFSET, data_written);
  int4store(header+ LOG_POS_OFFSET, log_pos);
  int2store(header+ FLAGS_OFFSET, flags);
}
```

```
 /*   Event Header  */

+----+----+----+----+--+
|****|****|****|****|**|
+----+----+----+----+--+

   4bytes timestamp
 + 4bytes server_id
 + 4bytes data_written
 + 4bytes log_pos
 + 2bytes flags
 ----------------------
  19bytes

```

## Query_log_event::

```cc
/*
  Query_log_event::write()

  NOTES:
    In this event we have to modify the header to have the correct
    EVENT_LEN_OFFSET as we don't yet know how many status variables we
    will print!
*/

bool Query_log_event::write(IO_CACHE* file)
{
  uchar buf[QUERY_HEADER_LEN + MAX_SIZE_LOG_EVENT_STATUS];
  uchar *start, *start_of_status;
  ulong event_length;

  if (!query)
    return 1;                                   // Something wrong with event

  /*
    We want to store the thread id:
    (- as an information for the user when he reads the binlog)
    - if the query uses temporary table: for the slave SQL thread to know to
    which master connection the temp table belongs.
    Now imagine we (write()) are called by the slave SQL thread (we are
    logging a query executed by this thread; the slave runs with
    --log-slave-updates). Then this query will be logged with
    thread_id=the_thread_id_of_the_SQL_thread. Imagine that 2 temp tables of
    the same name were created simultaneously on the master (in the master
    binlog you have
    CREATE TEMPORARY TABLE t; (thread 1)
    CREATE TEMPORARY TABLE t; (thread 2)
    ...)
    then in the slave's binlog there will be
    CREATE TEMPORARY TABLE t; (thread_id_of_the_slave_SQL_thread)
    CREATE TEMPORARY TABLE t; (thread_id_of_the_slave_SQL_thread)
    which is bad (same thread id!).

    To avoid this, we log the thread's thread id EXCEPT for the SQL
    slave thread for which we log the original (master's) thread id.
    Now this moves the bug: what happens if the thread id on the
    master was 10 and when the slave replicates the query, a
    connection number 10 is opened by a normal client on the slave,
    and updates a temp table of the same name? We get a problem
    again. To avoid this, in the handling of temp tables (sql_base.cc)
    we use thread_id AND server_id.  TODO when this is merged into
    4.1: in 4.1, slave_proxy_id has been renamed to pseudo_thread_id
    and is a session variable: that's to make mysqlbinlog work with
    temp tables. We probably need to introduce

    SET PSEUDO_SERVER_ID
    for mysqlbinlog in 4.1. mysqlbinlog would print:
    SET PSEUDO_SERVER_ID=
    SET PSEUDO_THREAD_ID=
    for each query using temp tables.
  */
  int4store(buf + Q_THREAD_ID_OFFSET, slave_proxy_id);
  int4store(buf + Q_EXEC_TIME_OFFSET, exec_time);
  buf[Q_DB_LEN_OFFSET] = (char) db_len;
  int2store(buf + Q_ERR_CODE_OFFSET, error_code);

  /*
    You MUST always write status vars in increasing order of code. This
    guarantees that a slightly older slave will be able to parse those he
    knows.
  */
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
    /*
      In 5.0.x where x<4 masters we used to store the end zero here. This was
      a waste of one byte so we don't do it in x>=4 masters. We change code to
      Q_CATALOG_NZ_CODE, because re-using the old code would make x<4 slaves
      of this x>=4 master segfault (expecting a zero when there is
      none). Remaining compatibility problems are: the older slave will not
      find the catalog; but it is will not crash, and it's not an issue
      that it does not find the catalog as catalogs were not used in these
      older MySQL versions (we store it in binlog and read it from relay log
      but do nothing useful with it). What is an issue is that the older slave
      will stop processing the Q_* blocks (and jumps to the db/query) as soon
      as it sees unknown Q_CATALOG_NZ_CODE; so it will not be able to read
      Q_AUTO_INCREMENT*, Q_CHARSET and so replication will fail silently in
      various ways. Documented that you should not mix alpha/beta versions if
      they are not exactly the same version, with example of 5.0.3->5.0.2 and
      5.0.4->5.0.3. If replication is from older to new, the new will
      recognize Q_CATALOG_CODE and have no problem.
    */
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
  /*
    NOTE: When adding new status vars, please don't forget to update
    the MAX_SIZE_LOG_EVENT_STATUS in log_event.h and update function
    code_name in this file.
   
    Here there could be code like
    if (command-line-option-which-says-"log_this_variable" && inited)
    {
    *start++= Q_THIS_VARIABLE_CODE;
    int4store(start, this_variable);
    start+= 4;
    }
  */
  
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