# mod_cgid + backlog

クライアントが多い際に mod_cgid の backlog が溢れてスループットが低下していないかどうか? を調べるためにソースを読む

## まとめ

 * backlog 溢れると worker スレッドは sleep してから再接続する
 * 再接続したかどうかは debug でログ出さないと見れない

 backlog 溢れしてなければ別の要因がボトルネック (そらそうだ)

## ソース読む前に前置き

 * mod_cgid のソースは modules/generators/mod_cgid.c 
 * mod_cgid のソケットは UNIXドメインソケット(AF_UNIX, SOCK_STREAM)
 * mod_cgid のアーキテクチャは ↓ な感じ

![](http://f.st-hatena.com/images/fotolife/h/hiboma/20130314/20130314223222.png) 

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

パッチ当てるなり make の際に指定すれば変更可能な数値です。再接続でどんな挙動をするかは ↓ に書く

## worker スレッドから mod_cgid に connect(2) する箇所のコード

connect_to_daemon のソースを読むと良い

 * connect して ECONNREFUSED を返した場合は **sliding_timer** の分 sleep してから再接続
   * 1回目では 100ms sleep
   * 2回目以降の再接続では **sliding_timer *=2** で 200, 400, 800, ... と sleep 時間が増える
   * 再接続の回数は **DEFAULT_CONNECT_ATTEMPTS** (デフォルト値 15回)
   * 再接続したかどうかは `LogLevel debug` じゃないと出ないぽい

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

再接続する挙動が確認できなければ別の要因がボトルネックになっているので考え直し....

----

ここからはカーネルの話。まだ調べ中

## カーネルのUNIXドメインソケットバックログ上限

sysctl の `net.unix.max_dgram_qlen` が backlog の上限。

```
[vagrant@vagrant-centos65 ~]$ sysctl -a | grep unix
net.unix.max_dgram_qlen = 10
```

 * カーネルの内部では `unx.sysctl_max_dgram_qlen` として扱われる
 * sk->sk_max_ack_backlog にセットされている

```c
static struct sock *unix_create1(struct net *net, struct socket *sock)
{
	struct sock *sk = NULL;
	struct unix_sock *u;

	atomic_long_inc(&unix_nr_socks);
	if (atomic_long_read(&unix_nr_socks) > 2 * get_max_files())
		goto out;

	sk = sk_alloc(net, PF_UNIX, GFP_KERNEL, &unix_proto);
	if (!sk)
		goto out;

	sock_init_data(sock, sk);
	lockdep_set_class(&sk->sk_receive_queue.lock,
				&af_unix_sk_receive_queue_lock_key);

	sk->sk_write_space	= unix_write_space;
	sk->sk_max_ack_backlog	= net->unx.sysctl_max_dgram_qlen;
	sk->sk_destruct		= unix_sock_destructor;
	u	  = unix_sk(sk);
	u->dentry = NULL;
	u->mnt	  = NULL;
	spin_lock_init(&u->lock);
	atomic_long_set(&u->inflight, 0);
	INIT_LIST_HEAD(&u->link);
	mutex_init(&u->readlock); /* single task reading lock */
	init_waitqueue_head(&u->peer_wait);
	unix_insert_socket(unix_sockets_unbound, sk);
out:
	if (sk == NULL)
		atomic_long_dec(&unix_nr_socks);
	else {
		local_bh_disable();
		sock_prot_inuse_add(sock_net(sk), sk->sk_prot, 1);
		local_bh_enable();
	}
	return sk;
}
```

 * sk->sk_max_ack_backlog は listen(2) の backlog サイズで上書きされている
 * mod_cgid の場合は DEFAULT_CGID_LISTENBACKLOG で上書きされている、でいいのかな?

```c
static int unix_listen(struct socket *sock, int backlog)
{
	int err;
	struct sock *sk = sock->sk;
	struct unix_sock *u = unix_sk(sk);
	struct pid *old_pid = NULL;
	const struct cred *old_cred = NULL;

	err = -EOPNOTSUPP;
	if (sock->type != SOCK_STREAM && sock->type != SOCK_SEQPACKET)
		goto out;	/* Only stream/seqpacket sockets accept */
	err = -EINVAL;
	if (!u->addr)
		goto out;	/* No listens on an unbound socket */
	unix_state_lock(sk);
	if (sk->sk_state != TCP_CLOSE && sk->sk_state != TCP_LISTEN)
		goto out_unlock;

	/* connect しているクライアントを起床させる。なんでだろう? */
	if (backlog > sk->sk_max_ack_backlog)
		wake_up_interruptible_all(&u->peer_wait);

    /* net.unix.max_dgram_qlen を上書き */
	sk->sk_max_ack_backlog	= backlog;
	sk->sk_state		= TCP_LISTEN;
	/* set credentials so connect can copy them */
	init_peercred(sk);
	err = 0;

out_unlock:
	unix_state_unlock(sk);
	put_pid(old_pid);
	if (old_cred)
		put_cred(old_cred);
out:
	return err;
}
```

sk->sk_max_ack_backlog を超えたかどうかは unix_recvq_full で見る

 * sk->sk_receive_queue のサイズを比較
 * read とか recvmsg で読み取り待ちキューのサイズ

```c
static inline int unix_recvq_full(struct sock const *sk)
{
	return skb_queue_len(&sk->sk_receive_queue) > sk->sk_max_ack_backlog;
}
```

## backlog を超えて sendmsg がブロックするケース

 * SOCK_DGRAM で sendmsg -> recvmsg
 * SOCK_STREAM は???

### SOCK_DGRAM の場合

```
unix_dgram_sendmsg -----> [ sk->sk_receive_queue ] ---> unix_dgram_recvmsg
```

 * sendmsg する際にバックログが溢れていないかを見る
 * バックログが溢れていればブロックする
 * バックログが溢れていなければ skb を sk->sk_receive_queue に繋ぐ
   * ところで skb は kiocv を memcpy して作っている

```c
static int unix_dgram_sendmsg(struct kiocb *kiocb, struct socket *sock,
			      struct msghdr *msg, size_t len)
{

// ...

    // 相手側の sk->sk_receive_queue のバックログ溢れている
	if (unix_peer(other) != sk && unix_recvq_full(other)) {
        // NONBLOCK なら EAGAIN 返す
		if (!timeo) {
			err = -EAGAIN;
			goto out_unlock;
		}

        // 相手側から起床ささてもらうのを待つ
		timeo = unix_wait_for_peer(other, timeo);

		err = sock_intr_errno(timeo);
		if (signal_pending(current))
			goto out_free;

		goto restart;
	}

    // sk->sk_receive_queue に skb を繋ぐ
	maybe_add_creds(skb, sock, other);
	skb_queue_tail(&other->sk_receive_queue, skb);
```

バックログが溢れていたら unix_wait_for_peer で待ちに入る

```c
static long unix_wait_for_peer(struct sock *other, long timeo)
{
	struct unix_sock *u = unix_sk(other);
	int sched;
	DEFINE_WAIT(wait);

    // シグナル受け付けるよ
    // u->peer_wait が wait_queue_head_t
	prepare_to_wait_exclusive(&u->peer_wait, &wait, TASK_INTERRUPTIBLE);

    // 再度ソケットの状態を見る
	sched = !sock_flag(other, SOCK_DEAD) &&
		!(other->sk_shutdown & RCV_SHUTDOWN) &&
		unix_recvq_full(other);

	unix_state_unlock(other);

    // 要スケジューリングということで待たされる
	if (sched)
		timeo = schedule_timeout(timeo);

	finish_wait(&u->peer_wait, &wait);
	return timeo;
}
```

起床させるのはメッセージの受け取り側 = recvmsg

```c
```c
static int unix_dgram_recvmsg(struct kiocb *iocb, struct socket *sock,
			      struct msghdr *msg, size_t size,
			      int flags)
{
	struct sock_iocb *siocb = kiocb_to_siocb(iocb);
	struct scm_cookie tmp_scm;
	struct sock *sk = sock->sk;
	struct unix_sock *u = unix_sk(sk);
	int noblock = flags & MSG_DONTWAIT;
	struct sk_buff *skb;
	int err;

	err = -EOPNOTSUPP;
	if (flags&MSG_OOB)
		goto out;

	msg->msg_namelen = 0;

	mutex_lock(&u->readlock);

    // 
	skb = skb_recv_datagram(sk, flags, noblock, &err);
	if (!skb) {
		unix_state_lock(sk);
		/* Signal EOF on disconnected non-blocking SEQPACKET socket. */
		if (sk->sk_type == SOCK_SEQPACKET && err == -EAGAIN &&
		    (sk->sk_shutdown & RCV_SHUTDOWN))
			err = 0;
		unix_state_unlock(sk);
		goto out_unlock;
	}

    // ここで sendmsg でブロックしているプロセスを起床させる
    // 起床下側にコンテキストスイッチさせないで、継続するやつ?
	wake_up_interruptible_sync(&u->peer_wait);    
```