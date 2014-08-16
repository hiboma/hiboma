# MSG_OOB

## Message Out Of Band Data

利用方法が謎なやつ

```c
#include <sys/types.h>
#include <sys/socket.h>

ssize_t recv(int sockfd, void *buf, size_t len, int flags);

ssize_t recvfrom(int sockfd, void *buf, size_t len, int flags,
                 struct sockaddr *src_addr, socklen_t *addrlen);

ssize_t recvmsg(int sockfd, struct msghdr *msg, int flags);
```

man recv の説明に下記の通り

```
MSG_OOB
このフラグは、通常のデータ・ストリームでは受信できない 帯域外 (out-of-band) データの受信を要求する。 プロトコルによっては、 通常のデータ・キューの先頭に速達データを置くものがあるが、 そのようなプロトコルではこのフラグは使用できない。
```

## UDP の場合

送信で EOPNOTSUPP を返す。受信でもシカトされてそう

```c
int udp_sendmsg(struct kiocb *iocb, struct sock *sk, struct msghdr *msg,
		size_t len)
{

//...
	if (msg->msg_flags & MSG_OOB) /* Mirror BSD error message compatibility */
		return -EOPNOTSUPP;
```

## TCP

sk->sk_receive_queue とは別に struct tcp_sock が out_of_order_queue キューを持っている

```c 
struct sk_buff_head	out_of_order_queue; /* Out of order segments go here */`
```

sk->sk_receive_queue より優先して読み込まれるキューなのかな?

### out_of_order_queue に sk_buff を突っ込むコード

```c
static void tcp_data_queue(struct sock *sk, struct sk_buff *skb)
{
	struct tcphdr *th = tcp_hdr(skb);
	struct tcp_sock *tp = tcp_sk(sk);
	int eaten = -1;

//...
		if (eaten <= 0) {
queue_and_out:
			if (eaten < 0 &&
			    tcp_try_rmem_schedule(sk, skb->truesize))
				goto drop;

			skb_set_owner_r(skb, sk);
			__skb_queue_tail(&sk->sk_receive_queue, skb);
		}


//...
		if (!skb_queue_empty(&tp->out_of_order_queue)) {
			tcp_ofo_queue(sk);

			/* RFC2581. 4.2. SHOULD send immediate ACK, when
			 * gap in queue is filled.
			 */
			if (skb_queue_empty(&tp->out_of_order_queue))
				inet_csk(sk)->icsk_ack.pingpong = 0;
		}
        

//...
        
	if (!skb_peek(&tp->out_of_order_queue)) {
		/* Initial out of order segment, build 1 SACK. */
		if (tcp_is_sack(tp)) {
			tp->rx_opt.num_sacks = 1;
			tp->selective_acks[0].start_seq = TCP_SKB_CB(skb)->seq;
			tp->selective_acks[0].end_seq =
						TCP_SKB_CB(skb)->end_seq;
		}
		__skb_queue_head(&tp->out_of_order_queue, skb);

// この後も続くけど、えらい複雑なので略
```

tcp_ofo_queue

 * out_of_order_queue にキューイングされた sk_buff を sk->sk_receive_queue に移す
 * プロセスコンテキストでは out_of_order_queue から直で読み出すのでは無さそ

```
/* This one checks to see if we can put data from the
 * out_of_order queue into the receive_queue.
 */
static void tcp_ofo_queue(struct sock *sk)
{
	struct tcp_sock *tp = tcp_sk(sk);
	__u32 dsack_high = tp->rcv_nxt;
	struct sk_buff *skb;

	while ((skb = skb_peek(&tp->out_of_order_queue)) != NULL) {
		if (after(TCP_SKB_CB(skb)->seq, tp->rcv_nxt))
			break;

		if (before(TCP_SKB_CB(skb)->seq, dsack_high)) {
			__u32 dsack = dsack_high;
			if (before(TCP_SKB_CB(skb)->end_seq, dsack_high))
				dsack_high = TCP_SKB_CB(skb)->end_seq;
			tcp_dsack_extend(sk, TCP_SKB_CB(skb)->seq, dsack);
		}

		if (!after(TCP_SKB_CB(skb)->end_seq, tp->rcv_nxt)) {
			SOCK_DEBUG(sk, "ofo packet was already received \n");
			__skb_unlink(skb, &tp->out_of_order_queue);
			__kfree_skb(skb);
			continue;
		}
		SOCK_DEBUG(sk, "ofo requeuing : rcv_next %X seq %X - %X\n",
			   tp->rcv_nxt, TCP_SKB_CB(skb)->seq,
			   TCP_SKB_CB(skb)->end_seq);

		__skb_unlink(skb, &tp->out_of_order_queue);
		__skb_queue_tail(&sk->sk_receive_queue, skb);
		tp->rcv_nxt = TCP_SKB_CB(skb)->end_seq;
		if (tcp_hdr(skb)->fin)
			tcp_fin(skb, sk, tcp_hdr(skb));
	}
}
```