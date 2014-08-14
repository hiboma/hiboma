# AF_INET + SOCK_STREAM の backlog その2

TCP の backlog は2種類ある。ややこしい

 * accept queue
   * accept(2) 待ちのキュー
   * キューの実体は inet_csk(sk)->icsk_accept_queue ???
   * inet_csk_reqsk_queue_len(sk) ?
 * SYN queue
   * キューの実体は sk->sk_ack_backlog 
   * sk_acceptq_is_full ( sk->sk_max_ack_backlog ) と比較してキュー溢れを判定

二つの queue (backlog) が存在する 

 * http://veithen.blogspot.jp/2014/01/how-tcp-backlog-works-in-linux.html
 * http://tmtms.hatenablog.com/entry/2014/08/06/tcp-established

## 検証コード

```sh
$ ruby -rsocket -e 's = TCPServer.open(10000); sleep 1 << 20'
```

これに nc とかで繋ぎまくっている時の netstat -s の統計値

```
TcpExt:
    84 resets received for embryonic SYN_RECV sockets # <= sysctl_tcp_abort_on_overflow=1 の場合に増える
    69 TCP sockets finished time wait in fast timer
    15 delayed acks sent
    187 times the listen queue of a socket overflowed # <= 増える
    187 SYNs to LISTEN sockets ignored                # <= 増える
```

refs http://dsas.blog.klab.org/archives/51977201.html

## /proc/net/snmp の数値

netstat -s の数値は下記の三つを出力している

```c
static const struct snmp_mib snmp4_net_list[] = {

//…
	SNMP_MIB_ITEM("EmbryonicRsts", LINUX_MIB_EMBRYONICRSTS),

//…
	SNMP_MIB_ITEM("ListenOverflows", LINUX_MIB_LISTENOVERFLOWS),
	SNMP_MIB_ITEM("ListenDrops", LINUX_MIB_LISTENDROPS),
```

## LINUX_MIB_LISTENDROPS, LINUX_MIB_LISTENOVERFLOWS

tcp_v4_syn_recv_sock で使われている。 tcp_v4_syn_recv_sock は inet_connection_sock_af_ops の .syn_recv_sock

```c
const struct inet_connection_sock_af_ops ipv4_specific = {
	.queue_xmit	   = ip_queue_xmit,
	.send_check	   = tcp_v4_send_check,
	.rebuild_header	   = inet_sk_rebuild_header,
	.conn_request	   = tcp_v4_conn_request,
	.syn_recv_sock	   = tcp_v4_syn_recv_sock,
```

tcp_v4_syn_recv_sock の中身

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

	struct ip_options *inet_opt;

	/* accept キューが溢れているのでシカト */

    //static inline int sk_acceptq_is_full(struct sock *sk)
    //{
    //	return sk->sk_ack_backlog > sk->sk_max_ack_backlog;
    //}
    //
	if (sk_acceptq_is_full(sk))
		goto exit_overflow;

	/* ルーティングでオーバフロー? */
	if (!dst && (dst = inet_csk_route_req(sk, req)) == NULL)
		goto exit;

	/* kmem_cache_alloc + GFP_ATOMIC な割り当てコケた場合。(成功した場合は新しいソケットは SYN_RECVD な state で返される) */
	newsk = tcp_create_openreq_child(sk, req, skb);
	if (!newsk)
		goto exit_nonewsk;

	newsk->sk_gso_type = SKB_GSO_TCPV4;
	sk_setup_caps(newsk, dst);

	newtp		      = tcp_sk(newsk);
	newinet		      = inet_sk(newsk);
	ireq		      = inet_rsk(req);
	newinet->daddr	      = ireq->rmt_addr;
	newinet->rcv_saddr    = ireq->loc_addr;
	newinet->saddr	      = ireq->loc_addr;
	inet_opt	      = ireq->opt;
	rcu_assign_pointer(newinet->opt, inet_opt);
	ireq->opt	      = NULL;
	newinet->mc_index     = inet_iif(skb);
	newinet->mc_ttl	      = ip_hdr(skb)->ttl;
	sk_extended(newsk)->rcv_tos = ip_hdr(skb)->tos;
	inet_csk(newsk)->icsk_ext_hdr_len = 0;
	if (inet_opt)
		inet_csk(newsk)->icsk_ext_hdr_len = inet_opt->optlen;
	newinet->id = newtp->write_seq ^ jiffies;

	tcp_mtup_init(newsk);
	tcp_sync_mss(newsk, dst_mtu(dst));
	newtp->advmss = dst_metric(dst, RTAX_ADVMSS);
	if (tcp_sk(sk)->rx_opt.user_mss &&
	    tcp_sk(sk)->rx_opt.user_mss < newtp->advmss)
		newtp->advmss = tcp_sk(sk)->rx_opt.user_mss;

	tcp_initialize_rcv_mss(newsk);
	if (tcp_rsk(req)->snt_synack)
		tcp_valid_rtt_meas(newsk,
		    tcp_time_stamp - tcp_rsk(req)->snt_synack);
	newtp->total_retrans = req->retrans;

	if (__inet_inherit_port(sk, newsk) < 0) {
		sock_put(newsk);
		goto exit;
	}
	__inet_hash_nolisten(newsk);

	return newsk;

exit_overflow:
	NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_LISTENOVERFLOWS);
exit_nonewsk:
	dst_release(dst);
exit:
	NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_LISTENDROPS);
	return NULL;
}
```

## LINUX_MIB_EMBRYONICRSTS 

syn_recv_sock の呼び出し元で使われている。

```c
struct sock *tcp_check_req(struct sock *sk, struct sk_buff *skb,
			   struct request_sock *req,
			   struct request_sock **prev)
{

//...

	/* SYN_RECV のソケットを複製する */
	child = inet_csk(sk)->icsk_af_ops->syn_recv_sock(sk, skb, req, NULL);
	if (child == NULL)
		goto listen_overflow;

	inet_csk_reqsk_queue_unlink(sk, req, prev);
	inet_csk_reqsk_queue_removed(sk, req);

	inet_csk_reqsk_queue_add(sk, req, child);
	return child;

listen_overflow:
    /* オーバフローした場合に、クライアントに RST パケットを送りかえすかどうか */
	if (!sysctl_tcp_abort_on_overflow) {
		inet_rsk(req)->acked = 1;
		return NULL;
	}

/* 胚芽、初期の … */
embryonic_reset:
	NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_EMBRYONICRSTS);
	if (!(flg & TCP_FLAG_RST))
		req->rsk_ops->send_reset(sk, skb);

	inet_csk_reqsk_queue_drop(sk, req, prev);
	return NULL;
}
```

### RST パケットが送られたかどうかを nc で strace する

getsockopet + SOL_SOCKET + SO_ERROR で RSTパケットを受け取ったことを確認している

```c
connect(3, {sa_family=AF_INET, sin_port=htons(10000), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
select(4, NULL, [3], NULL, NULL)        = 1 (out [3])
getsockopt(3, SOL_SOCKET, SO_ERROR, [7412818059146035304], [4]) = 0
fcntl(3, F_SETFL, O_RDWR)               = 0
write(2, "nc: ", 4nc: )                     = 4
write(2, "connect to localhost port 10000 "..., 44connect to localhost port 10000 (tcp) failed) = 44
write(2, ": ", 2: )                       = 2
write(2, "Connection reset by peer\n", 25Connection reset by peer
```