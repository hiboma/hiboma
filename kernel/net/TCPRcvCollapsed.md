# TCPRcvCollapsed

 * ソケットのバッファサイズが小さい
 * 受信キューの中で、パケットが collapse された数値

```c
$ netstat -st | grep col
    598799 packets collapsed in receive queue due to low socket buffer
```

## カーネルの実装

下記の様に定数が定義される

```c
/* ipv4/proc.c */
SNMP_MIB_ITEM("TCPRcvCollapsed", LINUX_MIB_TCPRCVCOLLAPSED),
```

## LINUX_MIB_TCPRCVCOLLAPSED がインクリメントされる箇所

__skb_unlink, __kfree_skb で sk_buff を捨てている

```c
static struct sk_buff *tcp_collapse_one(struct sock *sk, struct sk_buff *skb,
					struct sk_buff_head *list)
{
	struct sk_buff *next = NULL;

	if (!skb_queue_is_last(list, skb))
		next = skb_queue_next(list, skb);

	__skb_unlink(skb, list);
	__kfree_skb(skb);
	NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPRCVCOLLAPSED);

	return next;
}
```

tcp_collapse_one は、 tcp_collapse の中で呼び出される。 sk_buff をイテレートして、破棄するメソッドかな。

```c
/* Collapse contiguous sequence of skbs head..tail with
 * sequence numbers start..end.
 *
 * If tail is NULL, this means until the end of the list.
 *
 * Segments with FIN/SYN are not collapsed (only because this
 * simplifies code)
 */
static void
tcp_collapse(struct sock *sk, struct sk_buff_head *list,
	     struct sk_buff *head, struct sk_buff *tail,
	     u32 start, u32 end)
{
	struct sk_buff *skb, *n;
	bool end_of_skbs;

	/* First, check that queue is collapsible and find
	 * the point where collapsing can be useful. */
	skb = head;
restart:
	end_of_skbs = true;
	skb_queue_walk_from_safe(list, skb, n) {
		if (skb == tail)
			break;
		/* No new bits? It is possible on ofo queue. */
		if (!before(start, TCP_SKB_CB(skb)->end_seq)) {
			skb = tcp_collapse_one(sk, skb, list);
			if (!skb)
				break;
			goto restart;
		}
```

tcp_collapse を呼び出す箇所。

tcp_prune_queue で、sk->sk_receive_queue に空きがない場合に、キューの中身を破棄する?

```c
/* Reduce allocated memory if we can, trying to get
 * the socket within its memory limits again.
 *
 * Return less than zero if we should start dropping frames
 * until the socket owning process reads some of the data
 * to stabilize the situation.
 */
static int tcp_prune_queue(struct sock *sk)
{
	struct tcp_sock *tp = tcp_sk(sk);

	SOCK_DEBUG(sk, "prune_queue: c=%x\n", tp->copied_seq);

	NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_PRUNECALLED);

	if (atomic_read(&sk->sk_rmem_alloc) >= sk->sk_rcvbuf)
		tcp_clamp_window(sk);
	else if (tcp_memory_pressure)
		tp->rcv_ssthresh = min(tp->rcv_ssthresh, 4U * tp->advmss);

	tcp_collapse_ofo_queue(sk);
	if (!skb_queue_empty(&sk->sk_receive_queue))
		tcp_collapse(sk, &sk->sk_receive_queue,
			     skb_peek(&sk->sk_receive_queue),
			     NULL,
			     tp->copied_seq, tp->rcv_nxt);
```