
# backlog あれこれ

下記の設定がどんなレイヤで作用するのかを追った

 * net.core.somaxconn
 * net.core.netdev_max_backlog
 * net.ipv4.tcp_max_syn_backlog
 * net.unix.max_dgram_qlen

http://d.hatena.ne.jp/nyant/20111216/1324043063 も詳しい

## まとめ

 * net.core.netdev_max_backlog
   * per_cpu の softnet_data .input_pkt_queue (sk_buff) のキュー長と比較
   * input_pkt_queue sk_buff のキュー。プロトコルに依存しない
   * drop されたパケットは ifconfig の droppbed で確認できるはず
 * net.core.somaxconn
   * プロトコルに依存しない backlog の上限値
   * sys_listen で切り詰められる
   * net.ipv4.tcp_max_syn_backlog より大きくあるべき?
   * 上限は 65535
     * http://blog.yuryu.jp/2014/01/somaxconn-is-16-bit.html
 * net.ipv4.tcp_max_syn_backlog
   * IPv4 + TCP の LISTEN ソケットの SYN_RECV キューの最大長
   * reqsk_queue_alloc で somaxconn の値以下にセットされる
   * TCP だよね
 * net.unix.max_dgram_qlen
   * unix_create1

listen(2) する際に backlog の値が net.core.somaxconn と net.ipv4.tcp_max_syn_backlog とで切り詰められるので 両者の値を一緒に上げておかないと意味がない

## TODO

 * TCP で sk_ack_backlog の数をインクリメントするコードはどれ?
   * sk_acceptq_removed は inet_connection_sock.c で使われている
   * 対応する sk_acceptq_added が見つからん

```c
static inline void sk_acceptq_removed(struct sock *sk)
{
	sk->sk_ack_backlog--;
}

static inline void sk_acceptq_added(struct sock *sk)
{
	sk->sk_ack_backlog++;
}
```

## miscメモ

 * AF_INET/TCP の実装は net/ipv4/inet_connection_sock.c らへん
   * listen(2) inet_csk_listen_start
   * accpet(2) inet_csk_accept
   * struct proto tcp_prot 読んだら対応分かる
 * icksk_accept_queue
   * Internet Connection Socket Accept Queue
 * request_sock_queue
 * SYN_RECV ソケットは 32bit で 80バイト

----

## net.core.somaxconn

カーネル では core.sysctl_somaxconn で定義されている

```c
/* init_net はデフォルトの netns */
static struct ctl_table netns_core_table[] = {
	{
		.ctl_name	= NET_CORE_SOMAXCONN,
		.procname	= "somaxconn",
		.data		= &init_net.core.sysctl_somaxconn,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec
	},
	{ .ctl_name = 0 }
};
```

SOMAXCONN は 128 がデフォルト値である。

```c
/* Maximum queue length specifiable by listen.  */
#define SOMAXCONN	128
```

backlog のサイズは listen(2) で指定できる

```c
int listen(int sockfd, int backlog);
```

が、backlog のサイズは listen(2) する際に core.sysctl_somaxconn に切り詰められる

```c
/*
 *	Perform a listen. Basically, we allow the protocol to do anything
 *	necessary for a listen, and if that works, we mark the socket as
 *	ready for listening.
 */

SYSCALL_DEFINE2(listen, int, fd, int, backlog)
{
	struct socket *sock;
	int err, fput_needed;
	int somaxconn;

	sock = sockfd_lookup_light(fd, &err, &fput_needed);
	if (sock) {
        /* netns の変換 */
        /* core.sysctl_somaxconn はここだよ〜 */
		somaxconn = sock_net(sock->sk)->core.sysctl_somaxconn;
		if ((unsigned)backlog > somaxconn)
			backlog = somaxconn;

		err = security_socket_listen(sock, backlog);
		if (!err)
			err = sock->ops->listen(sock, backlog);

		fput_light(sock->file, fput_needed);
	}
	return err;
}
```

backlog がどのように扱われるかは プロトコルファミリと通信方式に依る

 * IPv4 + AF_INET + SOCK_STREAM なら sock->ops->listen は は inet_listen 呼び出しになる
 * AF_UNIX + SOCK_STREAM なら sock->ops->listen は unix_listen 呼び出しになる
   * backlog が `sk->sk_max_ack_backlog` としてセットされる
   * ACK を受け取れるキューのサイズ?

```
/*
 *	Move a socket into listening state.
 */
int inet_listen(struct socket *sock, int backlog)
{
	struct sock *sk = sock->sk;
	unsigned char old_state;
	int err;

	lock_sock(sk);

	err = -EINVAL;
	if (sock->state != SS_UNCONNECTED || sock->type != SOCK_STREAM)
		goto out;

	old_state = sk->sk_state;
	if (!((1 << old_state) & (TCPF_CLOSE | TCPF_LISTEN)))
		goto out;

	/* Really, if the socket is already in listen state
	 * we can only allow the backlog to be adjusted.
	 */
	if (old_state != TCP_LISTEN) {
		err = inet_csk_listen_start(sk, backlog);
		if (err)
			goto out;
	}
	sk->sk_max_ack_backlog = backlog;
	err = 0;

out:
	release_sock(sk);
	return err;
}
EXPORT_SYMBOL(inet_listen);
```

baclkog は nr_table_entries として reqsk_queue_alloc に渡される

```c
// nr_table_entries = backlog
int inet_csk_listen_start(struct sock *sk, const int nr_table_entries)
{
	struct inet_sock *inet = inet_sk(sk);
	struct inet_connection_sock *icsk = inet_csk(sk);
	int rc = reqsk_queue_alloc(&icsk->icsk_accept_queue, nr_table_entries);

	if (rc != 0)
		return rc;

	sk->sk_max_ack_backlog = 0;
	sk->sk_ack_backlog = 0;
	inet_csk_delack_init(sk);

	/* There is race window here: we announce ourselves listening,
	 * but this transition is still not validated by get_port().
	 * It is OK, because this socket enters to hash table only
	 * after validation is complete.
	 */
	sk->sk_state = TCP_LISTEN;
	if (!sk->sk_prot->get_port(sk, inet->num)) {
		inet->sport = htons(inet->num);

		sk_dst_reset(sk);
		sk->sk_prot->hash(sk);

		return 0;
	}

	sk->sk_state = TCP_CLOSE;
	__reqsk_queue_destroy(&icsk->icsk_accept_queue);
	return -EADDRINUSE;
}

EXPORT_SYMBOL_GPL(inet_csk_listen_start);
```

reqsk_queue_alloc で nr_table_entries は下記の様に扱われている

 * nr_table_entries (= backlog) と sysctl_max_syn_backlog の min()
 * nr_table_entries (= backlog) と 8 の max()
 * roundup_pow_of_two で 2の倍数に切り詰められる?
   * つまり `8 <= nr_table_entries <= sysctl_max_syn_backlog` に設定される
 * backlog 分の resquet_sock を vmalloc/kzalloc で割り当てる
   * = request_sock がメモリ上のデータとしての backlog の正体?

```c

//                     |-- nr_table_entries = backlog --|
//                     |                                |
//                     |                                |
// [listen_sock][request_sock][request_sock] ... [request_sock]
//    \
//     \
//  LISTEN の socket?
//

/*
 * Maximum number of SYN_RECV sockets in queue per LISTEN socket.
 * One SYN_RECV socket costs about 80bytes on a 32bit machine.
 * It would be better to replace it with a global counter for all sockets
 * but then some measure against one socket starving all other sockets
 * would be needed.
 *
 * The minimum value of it is 128. Experiments with real servers show that
 * it is absolutely not enough even at 100conn/sec. 256 cures most
 * of problems.
 * This value is adjusted to 128 for low memory machines,
 * and it will increase in proportion to the memory of machine.
 * Note : Dont forget somaxconn that may limit backlog too.
 */
int sysctl_max_syn_backlog = 256;

int reqsk_queue_alloc(struct request_sock_queue *queue,
		      unsigned int nr_table_entries)
{
	size_t lopt_size = sizeof(struct listen_sock);
	struct listen_sock *lopt;

    /* sysctl_max_syn_backlog はここだよ〜 */
	nr_table_entries = min_t(u32, nr_table_entries, sysctl_max_syn_backlog);
	nr_table_entries = max_t(u32, nr_table_entries, 8);
	nr_table_entries = roundup_pow_of_two(nr_table_entries + 1);
	lopt_size += nr_table_entries * sizeof(struct request_sock *);
	if (lopt_size > PAGE_SIZE)
		lopt = __vmalloc(lopt_size,
			GFP_KERNEL | __GFP_HIGHMEM | __GFP_ZERO,
			PAGE_KERNEL);
	else
		lopt = kzalloc(lopt_size, GFP_KERNEL);
	if (lopt == NULL)
		return -ENOMEM;

	for (lopt->max_qlen_log = 3;
	     (1 << lopt->max_qlen_log) < nr_table_entries;
	     lopt->max_qlen_log++);

	get_random_bytes(&lopt->hash_rnd, sizeof(lopt->hash_rnd));
	rwlock_init(&queue->syn_wait_lock);
	queue->rskq_accept_head = NULL;
	lopt->nr_table_entries = nr_table_entries;

	write_lock_bh(&queue->syn_wait_lock);
	queue->listen_opt = lopt;
	write_unlock_bh(&queue->syn_wait_lock);

	return 0;
}
```

sk_max_ack_backlog と比較してドロップされる箇所はどこ?

sk_acceptq_is_full の場合パケットが drop される

```c
int tcp_v4_conn_request(struct sock *sk, struct sk_buff *skb)
{

	struct request_sock *req;

// ...

	/* TW buckets are converted to open requests without
	 * limitations, they conserve resources and peer is
	 * evidently real one.
	 */
	if (inet_csk_reqsk_queue_is_full(sk) && !isn) {
#ifdef CONFIG_SYN_COOKIES
		if (sysctl_tcp_syncookies) {
			want_cookie = 1;
		} else
#endif
		goto drop;
	}

	/* Accept backlog is full. If we have already queued enough
	 * of warm entries in syn queue, drop request. It is better than
	 * clogging syn queue with openreqs with exponentially increasing
	 * timeout.
	 */
	if (sk_acceptq_is_full(sk) && inet_csk_reqsk_queue_young(sk) > 1)
		goto drop;

	req = inet_reqsk_alloc(&tcp_request_sock_ops);
	if (!req)
		goto drop;
```

sk_acceptq_is_full の中身は下記の通り。ここで backlog の数値が意味を茄子

```c
static inline int sk_acceptq_is_full(struct sock *sk)
{
	return sk->sk_ack_backlog > sk->sk_max_ack_backlog;
}
```

sk_acceptq_is_full は tcp_v4_syn_recv_sock でも使っている

```c
/*
 * The three way handshake has completed - we got a valid synack -
 * now create the new socket.
 */
struct sock *tcp_v4_syn_recv_sock(struct sock *sk, struct sk_buff *skb,
				  struct request_sock *req,
				  struct dst_entry *dst)
{
	struct inet_request_sock *ireq;
	struct inet_sock *newinet;
	struct tcp_sock *newtp;
	struct sock *newsk;
#ifdef CONFIG_TCP_MD5SIG
	struct tcp_md5sig_key *key;
#endif
	struct ip_options *inet_opt;

	if (sk_acceptq_is_full(sk))
		goto exit_overflow;
```

tcp_v4_syn_recv_sock, tcp_v4_conn_request が出てくるのは ↓

```c
const struct inet_connection_sock_af_ops ipv4_specific = {
	.queue_xmit	   = ip_queue_xmit,
	.send_check	   = tcp_v4_send_check,
	.rebuild_header	   = inet_sk_rebuild_header,
	.conn_request	   = tcp_v4_conn_request,
	.syn_recv_sock	   = tcp_v4_syn_recv_sock,
	.remember_stamp	   = tcp_v4_remember_stamp,
	.net_header_len	   = sizeof(struct iphdr),
	.setsockopt	   = ip_setsockopt,
	.getsockopt	   = ip_getsockopt,
	.addr2sockaddr	   = inet_csk_addr2sockaddr,
	.sockaddr_len	   = sizeof(struct sockaddr_in),
	.bind_conflict	   = inet_csk_bind_conflict,
#ifdef CONFIG_COMPAT
	.compat_setsockopt = compat_ip_setsockopt,
	.compat_getsockopt = compat_ip_getsockopt,
#endif
};
```

## net.core.netdev_max_backlog

 * netdev_max_backlog は input_pkt_queue.qlen と比較してドロップするか否かを決定する
   * sk_buff の中身はプロトコルに依存しないので netdev_max_backlog もプロトコルに依存しない設定
   * enqueue_to_backlog はハードウェア割り込みコンテキスト
   * デバイスが受け取れるパケットの backlog サイズと理解したらよいかな?

```c
/*
 * enqueue_to_backlog is called to queue an skb to a per CPU backlog
 * queue (may be a remote CPU queue).
 */
static int enqueue_to_backlog(struct sk_buff *skb, int cpu,
			      unsigned int *qtail)
{
	struct softnet_data *queue;
	unsigned long flags;

	queue = &per_cpu(softnet_data, cpu);

	local_irq_save(flags);
	__get_cpu_var(netdev_rx_stat).total++;

	spin_lock(&queue->input_pkt_queue.lock);

    /* netdev_max_backlog はここだよ〜 */
    /* 超えたら drop */
	if (queue->input_pkt_queue.qlen <= netdev_max_backlog) {
		if (queue->input_pkt_queue.qlen) {
enqueue:
			__skb_queue_tail(&queue->input_pkt_queue, skb);
			*qtail = queue->input_queue_head +
				 queue->input_pkt_queue.qlen;

			spin_unlock_irqrestore(&queue->input_pkt_queue.lock,
			    flags);
			return NET_RX_SUCCESS;
		}

		/* Schedule NAPI for backlog device */
		if (napi_schedule_prep(&queue->backlog)) {
			if (cpu != smp_processor_id()) {
				struct rps_remote_softirq_cpus *rcpus =
				    &__get_cpu_var(rps_remote_softirq_cpus);

				cpu_set(cpu, rcpus->mask[rcpus->select]);
				__raise_softirq_irqoff(NET_RX_SOFTIRQ);
			} else
				____napi_schedule(queue, &queue->backlog);
		}
		goto enqueue;
	}

	spin_unlock(&queue->input_pkt_queue.lock);

    /* drop されている */
	__get_cpu_var(netdev_rx_stat).dropped++;
	local_irq_restore(flags);

	kfree_skb(skb);
    /* ドロップです */
	return NET_RX_DROP;
}
```

enqueue_to_backlog を呼び出すのは netif_rx

 * デバイスドライバからパケットを受け取りキューイングする
 * バッファ(sk_buff?) は上位プロトコルで drop されうる

```c
/**
 *	netif_rx	-	post buffer to the network code
 *	@skb: buffer to post
 *
 *	This function receives a packet from a device driver and queues it for
 *	the upper (protocol) levels to process.  It always succeeds. The buffer
 *	may be dropped during processing for congestion control or by the
 *	protocol layers.
 *
 *	return values:
 *	NET_RX_SUCCESS	(no congestion)
 *	NET_RX_DROP     (packet was dropped)
 *
 */

int netif_rx(struct sk_buff *skb)
{
	struct rps_dev_flow voidflow, *rflow = &voidflow;
	int cpu;

	/* if netpoll wants it, pretend we never saw it */
	if (netpoll_rx(skb))
		return NET_RX_DROP;

	if (!skb->tstamp.tv64)
		net_timestamp(skb);

	trace_netif_rx(skb);
	cpu = get_rps_cpu(skb->dev, skb, &rflow);
	if (cpu < 0)
		cpu = smp_processor_id();

	return enqueue_to_backlog(skb, cpu, &rflow->last_qtail);
}
EXPORT_SYMBOL(netif_rx);
```

## 割り込みからどのようにプロトコルスタックを上っていくかをつらつらを書きだす

### ドライバの準備

struct virtio_driver virtio_net_driver の .probe 登録

 * virtnet_probe(struct virtio_device *vdev)
 * netif_napi_add(dev, &vi->napi, virtnet_poll, napi_weight);
 * NAPI に virtnet_poll の登録
 * virtnet_poll(struct napi_struct *napi, int budget)
 * receive_buf(struct net_device *dev, void *buf, unsigned int len)
 * netif_receive_skb へ続く

----

### ドライバ層

#### device driver が netif_receive_skb 呼び出しするパス

 * netif_receive_skb(struct sk_buff *skb)
 * __netif_receive_skb
   * ... deliver_skb に続く

#### device driver が netif_rx 呼び出しするパス

 * netif_rx(struct sk_buff *skb)
 * enqueue_to_backlog(struct sk_buff *skb, int cpu, unsigned int *qtail)
   * CPU ごとのバックログに sk_buff を突っ込む?
     * `queue->input_pkt_queue.qlen <= netdev_max_backlog` でドロップするか否かを見る
   * **netdev_max_backlog**
     * プロトコルに関係ないレイヤ( net.core ) での backlog
     * ここでしか参照されてない
 * ____napi_schedule
 * __raise_softirq_irqoff(NET_RX_SOFTIRQ)

----

### SoftIRQ 層

open_softirq(NET_RX_SOFTIRQ, net_rx_action) で登録していたソフト割り込みハンドラを実行

 * net_rx_action
 * ???
   * TODO 次に繋がる部分が分からん

struct softnet_data *queue の .backlog.poll 呼び出し

----

 * process_backlog
 * __netif_receive_skb
 * deliver_skb

struct packet_type pt->prev->func で .func 呼び出し

----

### IP 層

 * ip_rcv
 * ip_rcv_finish
 * dst_input
 * ip_local_deliver
 * ip_local_deliver_finish

struct net_protocol *ipprot の .handler 呼び出し

----

### TCP 層

 * tcp_v4_rcv
 * tcp_v4_do_rcv
   * sk->sk_state によってディスパッチ
 * tcp_rcv_state_process
   * TCP_LISTEN + SYN パケットを送られた
 * icsk->icsk_af_ops->conn_request

struct inet_connection_sock_af_ops の .conn_request で

 * tcp_v4_conn_request
   * sk_acceptq_is_full(sk) で **sk_max_ack_backlog** と比較

## process_backlog

 * softirq
 * input_pkt_queue

![2014-05-08 18 06 30](https://cloud.githubusercontent.com/assets/172456/2913701/247285f6-d690-11e3-8487-8abccd4515ce.png)

```c
static int process_backlog(struct napi_struct *napi, int quota)
{
	int work = 0;
	struct softnet_data *sd = container_of(napi, struct softnet_data, backlog);
	unsigned long start_time = jiffies;

	napi->weight = weight_p;
	do {
		struct sk_buff *skb;

		spin_lock_irq(&sd->input_pkt_queue.lock);
		skb = __skb_dequeue(&sd->input_pkt_queue);
		if (!skb) {
			/*
			 * Inline a custom version of __napi_complete().
			 * only current cpu owns and manipulates this napi,
			 * and NAPI_STATE_SCHED is the only possible flag set on backlog.
			 * we can use a plain write instead of clear_bit(),
			 * and we dont need an smp_mb() memory barrier.
			 */
			list_del(&napi->poll_list);
			napi->state = 0;

			spin_unlock_irq(&sd->input_pkt_queue.lock);
			break;
		}
		incr_input_queue_head(sd);
		spin_unlock_irq(&sd->input_pkt_queue.lock);

		__netif_receive_skb(skb);
	} while (++work < quota && jiffies == start_time);

	return work;
}
```

----

 * net.ipv4.tcp_syncookies 
 * http://d.hatena.ne.jp/nyant/20111216/1324043063
 * TCP_DEFER_ACCEPT

```
server/listen.c

#ifdef APR_TCP_DEFER_ACCEPT
        rv = apr_socket_opt_set(s, APR_TCP_DEFER_ACCEPT, 1);
        if (rv != APR_SUCCESS && !APR_STATUS_IS_ENOTIMPL(rv)) {
            ap_log_perror(APLOG_MARK, APLOG_WARNING, rv, p,
                              "Failed to enable APR_TCP_DEFER_ACCEPT");
        }
#endif

srclib/apr/network_io/unix/sockopt.c

    case APR_TCP_DEFER_ACCEPT:
#if defined(TCP_DEFER_ACCEPT)
        if (apr_is_option_set(sock, APR_TCP_DEFER_ACCEPT) != on) {
            int optlevel = IPPROTO_TCP;
            int optname = TCP_DEFER_ACCEPT;

            if (setsockopt(sock->socketdes, optlevel, optname, 
                           (void *)&on, sizeof(int)) == -1) {
                return errno;
            }
            apr_set_option(sock, APR_TCP_DEFER_ACCEPT, on);
        }
#else


strut net

net->core.sysctl_somaxconn
```