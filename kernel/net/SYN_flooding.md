# possible SYN flooding on port %d. Sending cookies

/var/log/messages に出て来るログを出しているコードを起点に実装を探る

 * syn_flood_warning がログを出しているコード
 * マクロを見ると CONFIG_SYN_COOKIES で有効になる機能であることが分かる

```c
#ifdef CONFIG_SYN_COOKIES
static void syn_flood_warning(struct sk_buff *skb)
{
	static unsigned long warntime;

	if (time_after(jiffies, (warntime + HZ * 60))) {
		warntime = jiffies;
		printk(KERN_INFO
		       "possible SYN flooding on port %d. Sending cookies.\n",
		       ntohs(tcp_hdr(skb)->dest));
	}
}
#endif
```

お馴染みの `sysctl -w net.ipv4.tcp_syncookies=1` で有効にするコードは下記の部分

```
#ifdef CONFIG_SYN_COOKIES
	{
		.ctl_name	= NET_TCP_SYNCOOKIES,
		.procname	= "tcp_syncookies",
		.data		= &sysctl_tcp_syncookies,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec
	},
#endif
```

CONFIG_SYN_COOKIES が含まれているコードを追って行く (IPv4だけ)

 * inet_csk_reqsk_queue_is_full で want_cookie が立つ
   * icsk_accept_queue ってなんだっけ
 * cookie を投げる つ :cookie::cookie::cookie::cookie::cookie:

```c
int tcp_v4_conn_request(struct sock *sk, struct sk_buff *skb)
{
	struct inet_request_sock *ireq;
	struct tcp_options_received tmp_opt;
	struct request_sock *req;
	__be32 saddr = ip_hdr(skb)->saddr;
	__be32 daddr = ip_hdr(skb)->daddr;
    /* isn なんだろ? => init sequence number の有無 */
	__u32 isn = TCP_SKB_CB(skb)->when;
	struct dst_entry *dst = NULL;
#ifdef CONFIG_SYN_COOKIES
	int want_cookie = 0;
#else
#define want_cookie 0 /* Argh, why doesn't gcc optimize this :( */
#endif

//... 

	/* TW buckets are converted to open requests without
	 * limitations, they conserve resources and peer is
	 * evidently real one.
	 */
     /* inet_csk_reqsk_queue が溢れてる + isn ? が無い場合に cookie を送りつける */
    // inet_csk は inet_connection_sock を取り出す
    //
    // static inline int inet_csk_reqsk_queue_is_full(const struct sock *sk)
    // {
    //          return reqsk_queue_is_full(&inet_csk(sk)->icsk_accept_queue);
    // }   
	if (inet_csk_reqsk_queue_is_full(sk) && !isn) {
#ifdef CONFIG_SYN_COOKIES
		if (sysctl_tcp_syncookies) {
			want_cookie = 1;
		} else
#endif
        /* net.ipv4.tcp_syncookies=0 ならDROPするらしい */
		goto drop;
	}

	/* Accept backlog is full. If we have already queued enough
	 * of warm entries in syn queue, drop request. It is better than
	 * clogging syn queue with openreqs with exponentially increasing
	 * timeout.
	 */
    // static inline int sk_acceptq_is_full(struct sock *sk)
    // {
    //          return sk->sk_ack_backlog > sk->sk_max_ack_backlog;
    // }
	if (sk_acceptq_is_full(sk) && inet_csk_reqsk_queue_young(sk) > 1)
		goto drop;

	req = inet_reqsk_alloc(&tcp_request_sock_ops);
	if (!req)
		goto drop;

	tcp_clear_options(&tmp_opt);
	tmp_opt.mss_clamp = 536;
	tmp_opt.user_mss  = tcp_sk(sk)->rx_opt.user_mss;

	tcp_parse_options(skb, &tmp_opt, 0);

	if (want_cookie && !tmp_opt.saw_tstamp)
		tcp_clear_options(&tmp_opt);

	tmp_opt.tstamp_ok = tmp_opt.saw_tstamp;

	tcp_openreq_init(req, &tmp_opt, skb);

	ireq = inet_rsk(req);
	ireq->loc_addr = daddr;
	ireq->rmt_addr = saddr;
	ireq->no_srccheck = inet_sk(sk)->transparent;
	ireq->opt = tcp_v4_save_options(sk, skb);

	if (security_inet_conn_request(sk, skb, req))
		goto drop_and_free;

	if (!want_cookie)
		TCP_ECN_create_request(req, tcp_hdr(skb));

	if (want_cookie) {
#ifdef CONFIG_SYN_COOKIES
        /* 冒頭のログを出す */
		syn_flood_warning(skb);
        /* ??? */
		req->cookie_ts = tmp_opt.tstamp_ok;
#endif
        /* syncookie を作る。うーん難しい */
		isn = cookie_v4_init_sequence(sk, skb, &req->mss);
	} else if (!isn) {
		struct inet_peer *peer = NULL;

		/* VJ's idea. We save last timestamp seen
		 * from the destination in peer table, when entering
		 * state TIME-WAIT, and check against it before
		 * accepting new connection request.
		 *
		 * If "isn" is not zero, this request hit alive
		 * timewait bucket, so that all the necessary checks
		 * are made in the function processing timewait state.
		 */
		if (tmp_opt.saw_tstamp &&
		    tcp_death_row.sysctl_tw_recycle &&
		    (dst = inet_csk_route_req(sk, req)) != NULL &&
		    (peer = rt_get_peer((struct rtable *)dst)) != NULL &&
		    peer->v4daddr == saddr) {
			if (get_seconds() < peer->tcp_ts_stamp + TCP_PAWS_MSL &&
			    (s32)(peer->tcp_ts - req->ts_recent) >
							TCP_PAWS_WINDOW) {
				NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_PAWSPASSIVEREJECTED);
				goto drop_and_release;
			}
		}
		/* Kill the following clause, if you dislike this way. */
		else if (!sysctl_tcp_syncookies &&
			 (sysctl_max_syn_backlog - inet_csk_reqsk_queue_len(sk) <
			  (sysctl_max_syn_backlog >> 2)) &&
			 (!peer || !peer->tcp_ts_stamp) &&
			 (!dst || !dst_metric(dst, RTAX_RTT))) {
			/* Without syncookies last quarter of
			 * backlog is filled with destinations,
			 * proven to be alive.
			 * It means that we continue to communicate
			 * to destinations, already remembered
			 * to the moment of synflood.
			 */
			LIMIT_NETDEBUG(KERN_DEBUG "TCP: drop open request from %pI4/%u\n",
				       &saddr, ntohs(tcp_hdr(skb)->source));
			goto drop_and_release;
		}

		isn = tcp_v4_init_sequence(skb);
	}

    /* syncookies or syncookies 無しの init sequence */
	tcp_rsk(req)->snt_isn = isn;
	tcp_rsk(req)->snt_synack = tcp_time_stamp;

	if (__tcp_v4_send_synack(sk, req, dst) || want_cookie)
		goto drop_and_free;

	inet_csk_reqsk_queue_hash_add(sk, req, TCP_TIMEOUT_INIT);
	return 0;

drop_and_release:
	dst_release(dst);
drop_and_free:
	reqsk_free(req);
drop:
	return 0;
}
```