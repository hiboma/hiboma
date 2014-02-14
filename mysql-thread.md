# Can't create a new thread (errno %d)

```
   *  Error: `1135' SQLSTATE: `HY000' (`ER_CANT_CREATE_THREAD')

     Message: Can't create a new thread (errno %d); if you are not out
     of available memory, you can consult the manual for a possible
     OS-dependent bug
```

errno 11 = EAGAIN である

## ER_CANT_CREATE_THREAD を総ざらい

 ```
$ fgrep ER_CANT_CREATE_THREAD -R *
Docs/mysql.info:   *  Error: `1135' SQLSTATE: `HY000' (`ER_CANT_CREATE_THREAD')
include/mysqld_ername.h:{ "ER_CANT_CREATE_THREAD", 1135 },
include/mysqld_error.h:#define ER_CANT_CREATE_THREAD 1135
sql/mysqld.cc:                  ER(ER_CANT_CREATE_THREAD), error);
sql/mysqld.cc:      net_send_error(thd, ER_CANT_CREATE_THREAD, error_message_buff);
sql/share/errmsg.txt:ER_CANT_CREATE_THREAD  
sql/sql_insert.cc:	my_error(ER_CANT_CREATE_THREAD, MYF(0), error);
```

 * mysqld では　create_thread_to_handle_connection で出す
 * クライアント接続時のハンドラ

```c
/*
  Scheduler that uses one thread per connection
*/

void create_thread_to_handle_connection(THD *thd)
{
  // キャッシュされたスレッド > 既に動いてるスレッド
  if (cached_thread_count > wake_thread)
  {
    /* Get thread from cache */
    thread_cache.push_back(thd);
    wake_thread++;
    pthread_cond_signal(&COND_thread_cache);
  }
  else
  {
    char error_message_buff[MYSQL_ERRMSG_SIZE];
    /* Create new thread to handle connection */
    int error;
    thread_created++;
    threads.append(thd);
    DBUG_PRINT("info",(("creating thread %lu"), thd->thread_id));
    thd->prior_thr_create_utime= thd->start_utime= my_micro_time();

    // ここすなー
    if ((error=pthread_create(&thd->real_id,&connection_attrib,
                              handle_one_connection,
                              (void*) thd)))
    {
      /* purecov: begin inspected */
      // 例のエラー
      DBUG_PRINT("error",
                 ("Can't create thread to handle request (error %d)",
                  error));
      thread_count--;
      thd->killed= THD::KILL_CONNECTION;			// Safety
      (void) pthread_mutex_unlock(&LOCK_thread_count);

      pthread_mutex_lock(&LOCK_connection_count);
      --connection_count;
      pthread_mutex_unlock(&LOCK_connection_count);

      statistic_increment(aborted_connects,&LOCK_status);
      /* Can't use my_error() since store_globals has not been called. */
      my_snprintf(error_message_buff, sizeof(error_message_buff),
                  ER(ER_CANT_CREATE_THREAD), error);
      net_send_error(thd, ER_CANT_CREATE_THREAD, error_message_buff);
      (void) pthread_mutex_lock(&LOCK_thread_count);
      close_connection(thd,0,0);
      delete thd;
      (void) pthread_mutex_unlock(&LOCK_thread_count);
      return;
      /* purecov: end */
    }
  }
  (void) pthread_mutex_unlock(&LOCK_thread_count);
  DBUG_PRINT("info",("Thread created"));
}
```

pthread_create が返すエラーで死ぬ。システムコールは clone(2) なはず