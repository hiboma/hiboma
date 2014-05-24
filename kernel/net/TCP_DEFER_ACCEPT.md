# TCP_DEFER_ACCEPT

do_tcp_setsockopt でセットされる

 * request_sock_queue の rskq_defer_accept に retrans? として設定

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