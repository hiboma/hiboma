# MySQL 5.1.73 のソースで `Can't create a new thread (errno %d)` を出す箇所を探す

## まとめ

pthread_create(3) がコケると出るメッセージ

 * 仮想メモリサイズの上限に達した場合にコケる
     * `vm.overcommmit_ratio`, `vm.overcommit_memory` によって挙動が変わるので先に見ておくこと
     * clone ではなく mmap や mprotect でもコケる
     * システムコールの errno は ENOMEM だけど、 pthread の仕様で EAGAIN に変えて返される
 * /etc/init.d/mysql stop がタイムアウト
   * シグナルに応答しない
   * シグナルハンドリング用のメモリも取れない状態?
 * クライアントを止めると復帰する
 * スレッド数が RLIMIT_NPROC の上限に達した場合もコケるはず

[pthread_man の man](http://linuxjm.sourceforge.jp/html/glibc-linuxthreads/man3/pthread_create.3.html) を見るとどちらも EAGAIN を返すので判別できない ...

## Can't create a new thread (errno %d)

### メッセージの詳細

エラー番号とシンボルとメッセージのテンプレは以下の様になっている

```
   *  Error: `1135' SQLSTATE: `HY000' (`ER_CANT_CREATE_THREAD')

     Message: Can't create a new thread (errno %d); if you are not out
     of available memory, you can consult the manual for a possible
     OS-dependent bug
```

 * 障碍児のメッセージでは　errno 11 = EAGAIN だった
 * クライアントではなくサーバ側の問題として発生する

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
   * `scheduler_functions* func` の関数ポインタとしてセット `func->add_connection`
 * クライアント接続時のハンドラ???

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
    // スレッドキャッシュから thd 取り出す
    thread_cache.push_back(thd);
    wake_thread++;

    // pthread_cond_signal で待機状態のシグナルを起こす
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

    // ここでスレッド生成すなー
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

      // aborted_connects をインクリメント
      statistic_increment(aborted_connects,&LOCK_status);
      /* Can't use my_error() since store_globals has not been called. */
      my_snprintf(error_message_buff, sizeof(error_message_buff),
                  ER(ER_CANT_CREATE_THREAD), error);

      // クライアントにエラーを返す
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

 * ltrace だと pthread_create が `errno = 11`

```
[pid 1662] pthread_create(0x3928d58, 0xd3f5e0, 0x5c5250, 0x3927430, 0xd3ef60)                                   = 11
```

 * pthread_create が返すエラーで死ぬ。システムコールは clone(2) なはず
   * 違った ... libc が EAGAIN をセットしてそう
     * https://www.sourceware.org/bugzilla/show_bug.cgi?id=386 EAGAIN か ENOMEM かの議論
     * POSIXでは ENOMEM じゃなくて EAGAIN を返すのが正しい仕様な様子
   * clone(2) 呼び出す前の mmap で死んでる
     * MAP_STACK なのでスレッド用のスタック
     * man を見るとスタックサイズは 2MB がデフォルトとあるが、下記のログだと 1MB
     * コネクション数 * 1MB だとなかなか仮想メモリをしっかり取るな

```
// LWP生えて ...
clone(child_stack=0x7f5c41248ff0, flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID, parent_tidptr=0x7f5c412499d0, tls=0x7f5c41249700, child_tidptr=0x7f5c412499d0) = 1962
// mmap でスタックを作ろうとしたところ
mmap(NULL, 10489856, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_STACK, -1, 0) = -1 ENOMEM (Cannot allocate memory)
// ぷげら
write(2, "pthread_create failed: errno = 1"..., 76pthread_create failed: errno = 11, error = Resource temporarily unavailable
) = 76
```

 * mysqld をトレースすると pthread_create の mprotect(2) で ENOMEM で死んでた
   * 疑似再現コードだと MAP_STACK の mmap(2) だったのでちょっと違う
   * pthread_create の中であるのは合ってるかな?

``` 
[pid 10526] clone(Process 10592 attached
child_stack=0x7f856e8e4f10, flags=CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_THREAD|CLONE_SYSVSEM|CLONE_SETTLS|CLONE_PARENT_SETTID|CLONE_CHILD_CLEARTID, parent_tidptr=0x7f856e8e59d0, tls=0x7f856e8e5700, child_tidptr=0x7f856e8e59d0) = 10592
[pid 10526] select(13, [10 12], NULL, NULL, NULL <unfinished ...>
[pid 10592] set_robust_list(0x7f856e8e59e0, 0x18) = 0
[pid 10592] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = 0x7f854c000000
[pid 10592] munmap(0x7f8550000000, 67108864) = 0
[pid 10592] mprotect(0x7f854c000000, 135168, PROT_READ|PROT_WRITE) = -1 ENOMEM (Cannot allocate memory)
[pid 10592] munmap(0x7f854c000000, 67108864) = 0
[pid 10592] mmap(0x7f8550000000, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = 0x7f8550000000
[pid 10592] mprotect(0x7f8550000000, 135168, PROT_READ|PROT_WRITE) = -1 ENOMEM (Cannot allocate memory)
[pid 10592] munmap(0x7f8550000000, 67108864) = 0
[pid 10592] write(33, "\271\0\0\0\377\21\4Out of memory; check if mysqld or some other process uses all available memory; if not, you may have to use 'ulimit' to allow mysqld to use more memory or you can add more swap space", 189) = 189
``` 
   
 * mysqld がスレッドを生成できない => kill するためのスレッドを作成できない?
   * pthread_create が EAGAIN 返すような状況で `/etc/init.d/mysqld stop` しても mysqld が応答しない
   * クライアントを止めても stop はブロックし続ける
   * シグナルハンドラ周りでブロックしてそうだけど、 strace 見ただけじゃよく分からん

create_thread_to_handle_connection を上に辿ると create_new_thread に辿り着く

```c
// mysqld.cc

/**
  Create new thread to handle incoming connection.

    This function will create new thread to handle the incoming
    connection.  If there are idle cached threads one will be used.
    'thd' will be pushed into 'threads'.

    In single-threaded mode (\#define ONE_THREAD) connection will be
    handled inside this function.

  @param[in,out] thd    Thread handle of future thread.
*/

static void create_new_thread(THD *thd)
{
  NET *net=&thd->net;
  DBUG_ENTER("create_new_thread");

  if (protocol_version > 9)
    net->return_errno=1;

  /*
    Don't allow too many connections. We roughly check here that we allow
    only (max_connections + 1) connections.
  */

  pthread_mutex_lock(&LOCK_connection_count);

  if (connection_count >= max_connections + 1 || abort_loop)
  {
    pthread_mutex_unlock(&LOCK_connection_count);

    // おっとよく見る奴だ 
    DBUG_PRINT("error",("Too many connections"));
    close_connection(thd, ER_CON_COUNT_ERROR, 1);
    delete thd;
    DBUG_VOID_RETURN;
  }

  ++connection_count;

  if (connection_count > max_used_connections)
    max_used_connections= connection_count;

  pthread_mutex_unlock(&LOCK_connection_count);

  /* Start a new thread to handle connection. */

  pthread_mutex_lock(&LOCK_thread_count);

  /*
    The initialization of thread_id is done in create_embedded_thd() for
    the embedded library.
    TODO: refactor this to avoid code duplication there
  */
  thd->thread_id= thd->variables.pseudo_thread_id= thread_id++;

  thread_count++;

  // ここでスレッドキャッシュを使うか、 pthread_create するかになる
  thread_scheduler.add_connection(thd);

  DBUG_VOID_RETURN;
}
#endif /* EMBEDDED_LIBRARY */
```

 * create_new_thread は handle_connections_sockets から呼ばれる
   * accept したり socket をごそごそいじる

```c
pthread_handler_t handle_connections_sockets(void *arg __attribute__((unused)))

...
```

