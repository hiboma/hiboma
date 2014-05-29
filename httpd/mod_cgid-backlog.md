# mod_cgid + backlog

クライアントが多い際に mod_cgid の backlog が溢れていることでスループットが低下していないかどうか? を調べるためにソースを読む

## 前置き

 * mod_cgid のソースは modules/generators/mod_cgid.c 
 * mod_cgid のソケットは UNIXドメインソケット(AF_UNIX, SOCK_STREAM)

## mod_cgid ソケットの backlog のサイズ
 
mod_cgid のソケットの backlog は **DEFAULT_CGID_LISTENBACKLOG** (デフォルト値 100) で決定される

 * mod_cgid に大量の接続が来た場合は queue される
   * worker から DEFAULT_CGID_LISTENBACKLOG 以上の接続があれば溢れる(はず)
 * queue が溢れた場合は ECONNREFUSED を返し、 workerスレッドは再接続を試みる

```c
/* DEFAULT_CGID_LISTENBACKLOG controls the max depth on the unix socket's
 * pending connection queue.  If a bunch of cgi requests arrive at about
 * the same time, connections from httpd threads/processes will back up
 * in the queue while the cgid process slowly forks off a child to process
 * each connection on the unix socket.  If the queue is too short, the
 * httpd process will get ECONNREFUSED when trying to connect.
 */
#ifndef DEFAULT_CGID_LISTENBACKLOG
#define DEFAULT_CGID_LISTENBACKLOG 100
#endif

// ...

    if (listen(sd, DEFAULT_CGID_LISTENBACKLOG) < 0) {
        ap_log_error(APLOG_MARK, APLOG_ERR, errno, main_server, 
                     "Couldn't listen on unix domain socket"); 
        return errno;
    } 
```

再接続でどんな挙動をするかは ↓ に書く

## worker スレッドから mod_cgid に connect(2) する箇所のコード

connect_to_daemon のソースを読むと良い

 * connect して ECONNREFUSED を返した場合は **sliding_timer** の分 sleep してから再接続
   * 1回目では 100ms sleep
   * 2回目以降の再接続では **sliding_timer *=2** で 200, 400, 800, ... と sleep 時間が増える
   * 再接続の回数は **DEFAULT_CONNECT_ATTEMPTS** (デフォルト値 15回)

```c
static int connect_to_daemon(int *sdptr, request_rec *r,
                             cgid_server_conf *conf)
{
    struct sockaddr_un unix_addr;
    int sd;
    int connect_tries;
    apr_interval_time_t sliding_timer;

    memset(&unix_addr, 0, sizeof(unix_addr));
    unix_addr.sun_family = AF_UNIX;
    strcpy(unix_addr.sun_path, conf->sockname);

    connect_tries = 0;
    sliding_timer = 100000; /* 100 milliseconds */
    while (1) {
        ++connect_tries;
        if ((sd = socket(AF_UNIX, SOCK_STREAM, 0)) < 0) {
            return log_scripterror(r, conf, HTTP_INTERNAL_SERVER_ERROR, errno, 
                                   "unable to create socket to cgi daemon");
        }
        if (connect(sd, (struct sockaddr *)&unix_addr, sizeof(unix_addr)) < 0) {
            if (errno == ECONNREFUSED && connect_tries < DEFAULT_CONNECT_ATTEMPTS) {
                ap_log_rerror(APLOG_MARK, APLOG_DEBUG, errno, r,
                              "connect #%d to cgi daemon failed, sleeping before retry",
                              connect_tries);
                close(sd);
                apr_sleep(sliding_timer);
                if (sliding_timer < apr_time_from_sec(2)) {
                    sliding_timer *= 2;
                }
            }
            else {
                close(sd);
                return log_scripterror(r, conf, HTTP_SERVICE_UNAVAILABLE, errno, 
                                       "unable to connect to cgi daemon after multiple tries");
            }
        }
        else {
            apr_pool_cleanup_register(r->pool, (void *)sd, close_unix_socket,
                                      apr_pool_cleanup_null);
            break; /* we got connected! */
        }
        /* gotta try again, but make sure the cgid daemon is still around */
        if (kill(daemon_pid, 0) != 0) {
            return log_scripterror(r, conf, HTTP_SERVICE_UNAVAILABLE, errno,
                                   "cgid daemon is gone; is Apache terminating?");
        }
    }
    *sdptr = sd;
    return OK;
}
```

## workerスレッドが再接続しているかどうかを調べる方法

 * worker スレッドを strace -econnect して追う?
   * スレッドめちゃくちゃあるし現実的でなさそう
   * strace もそれなりにオーバーヘッドあるので要注意
 * LogLevel を debug にすればログを出してくれる
   * production で debug にするのは現実的でない
   * LogLevel を変えるパッチを当てて様子するとか?

```c
                // connect_to_daemon の中
                ap_log_rerror(APLOG_MARK, APLOG_DEBUG, errno, r,
                              "connect #%d to cgi daemon failed, sleeping before retry",
                              connect_tries);
```
 * mod_cgid の backlog のサイズを取る方法 (あるのかな?)

## 評価の方法

再接続する挙動が確認できなければ別の要因がボトルネックになっているので 考え直し

----

ここからはカーネルの話

## カーネルのバックログ上限

sysctl の `net.unix.max_dgram_qlen` が backlog の上限。調べ中

```
[vagrant@vagrant-centos65 ~]$ sysctl -a | grep unix
net.unix.max_dgram_qlen = 10
```


