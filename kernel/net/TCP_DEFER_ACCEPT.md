# TCP_DEFER_ACCEPT

## refs

 * http://d.hatena.ne.jp/kazuhooku/20100327/1269682361

## ソース

do_tcp_setsockopt でセットされる

 * request_sock_queue の rskq_defer_accept に retrans? として設定
 * SYN/ACK を再送する回数を決める様子

```c
	case TCP_DEFER_ACCEPT:
		/* Translate value in seconds to number of retransmits */
		icsk->icsk_accept_queue.rskq_defer_accept =
            // 秒数を再送の回数に変換?
			secs_to_retrans(val, TCP_TIMEOUT_INIT / HZ,
					TCP_RTO_MAX / HZ);
		break;

// ...
struct request_sock_queue {
	struct request_sock	*rskq_accept_head;
	struct request_sock	*rskq_accept_tail;
	rwlock_t		syn_wait_lock;
	u8			rskq_defer_accept;
	/* 3 bytes hole, try to pack */
	struct listen_sock	*listen_opt;
};
```

rskq_defer_accept は inet_csk_reqsk_queue_prune で参照されている

 * syn/ack を再送するタイムアウトを計算している?
 * 

```c
void inet_csk_reqsk_queue_prune(struct sock *parent,
				const unsigned long interval,
				const unsigned long timeout,
				const unsigned long max_rto)
{
	struct inet_connection_sock *icsk = inet_csk(parent);
	struct request_sock_queue *queue = &icsk->icsk_accept_queue;
	struct listen_sock *lopt = queue->listen_opt;

    // ???
	int max_retries = icsk->icsk_syn_retries ? : sysctl_tcp_synack_retries;
	int thresh = max_retries;
	unsigned long now = jiffies;
	struct request_sock **reqp, *req;
	int i, budget;

	if (lopt == NULL || lopt->qlen == 0)
		return;

	/* Normally all the openreqs are young and become mature
	 * (i.e. converted to established socket) for first timeout.
	 * If synack was not acknowledged for 3 seconds, it means
	 * one of the following things: synack was lost, ack was lost,
	 * rtt is high or nobody planned to ack (i.e. synflood).
	 * When server is a bit loaded, queue is populated with old
	 * open requests, reducing effective size of queue.
	 * When server is well loaded, queue size reduces to zero
	 * after several minutes of work. It is not synflood,
	 * it is normal operation. The solution is pruning
	 * too old entries overriding normal timeout, when
	 * situation becomes dangerous.
	 *
	 * Essentially, we reserve half of room for young
	 * embrions; and abort old ones without pity, if old
	 * ones are about to clog our table.
	 */
	if (lopt->qlen>>(lopt->max_qlen_log-1)) {
		int young = (lopt->qlen_young<<1);

		while (thresh > 2) {
			if (lopt->qlen < young)
				break;
			thresh--;
			young <<= 1;
		}
	}

	if (queue->rskq_defer_accept)
        // ここ. max_retries 上書きしてるな
		max_retries = queue->rskq_defer_accept;

	budget = 2 * (lopt->nr_table_entries / (timeout / interval));
	i = lopt->clock_hand;

	do {
		reqp=&lopt->syn_table[i];
		while ((req = *reqp) != NULL) {
			if (time_after_eq(now, req->expires)) {
				int expire = 0, resend = 0;

                // syn/ack 再送のタイムアウトを計算
				syn_ack_recalc(req, thresh, max_retries,
					       queue->rskq_defer_accept,
					       &expire, &resend);
				if (!expire &&
				    (!resend ||
                     // syn/ack 送信? -> tcp_v4_send_synack
				     !req->rsk_ops->rtx_syn_ack(parent, req) ||
                     // acked なので ACK 済み?
				     inet_rsk(req)->acked)) {
					unsigned long timeo;

					if (req->retrans++ == 0)
						lopt->qlen_young--;
					timeo = min((timeout << req->retrans), max_rto);
					req->expires = now + timeo;
					reqp = &req->dl_next;

                    // もういっぺん再送
					continue;
				}

                // syn/ack 再送でタイムアウト? なので DROP する
				/* Drop this request */
				inet_csk_reqsk_queue_unlink(parent, req, reqp);
				reqsk_queue_removed(queue, req);
				reqsk_free(req);
				continue;
			}
			reqp = &req->dl_next;
		}

		i = (i + 1) & (lopt->nr_table_entries - 1);

	} while (--budget > 0);

	lopt->clock_hand = i;

	if (lopt->qlen)
		inet_csk_reset_keepalive_timer(parent, interval);
}

EXPORT_SYMBOL_GPL(inet_csk_reqsk_queue_prune);
```

tcp_v4_send_synack から syn/ack を送信する処理

```c
static int tcp_v4_send_synack(struct sock *sk, struct request_sock *req)
{
    // ->
	return __tcp_v4_send_synack(sk, req, NULL);
}
```

```c
/*
 *	Send a SYN-ACK after having received a SYN.
 *	This still operates on a request_sock only, not on a big
 *	socket.
 */
static int __tcp_v4_send_synack(struct sock *sk, struct request_sock *req,
				struct dst_entry *dst)
{
	const struct inet_request_sock *ireq = inet_rsk(req);
	int err = -1;
	struct sk_buff * skb;

	/* First, grab a route. */
	if (!dst && (dst = inet_csk_route_req(sk, req)) == NULL)
		return -1;

    // skb を sock_wmalloc
	skb = tcp_make_synack(sk, dst, req);
	if (skb) {
		struct tcphdr *th = tcp_hdr(skb);

		th->check = tcp_v4_check(skb->len,
					 ireq->loc_addr,
					 ireq->rmt_addr,
					 csum_partial(th, skb->len,
						      skb->csum));

        // IPヘッダをごそごそして送信
		err = ip_build_and_send_pkt(skb, sk, ireq->loc_addr,
					    ireq->rmt_addr,
					    ireq->opt);
		err = net_xmit_eval(err);
	}

    // 送信用バッファが足らん場合?
	dst_release(dst);
	return err;
}
```