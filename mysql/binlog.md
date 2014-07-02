

 * my_b_safe_write

## メモ

 * いろんな Event が定義されていて、それぞれに write メソッドが用意されてるa

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