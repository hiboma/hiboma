

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