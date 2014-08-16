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