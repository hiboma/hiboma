# ListenOverflows

accept queue 溢れするとインクリメントされるカウンタ

```
# via https://github.com/BrightcoveOS/Diamond/wiki/collectors-TCPCollector
We completed a 3WHS but couldn't put the socket on the accept queue, so we had to discard the connection.
```

munin だと Listen overflow

## カーネルの実装

```c
	SNMP_MIB_ITEM("ListenOverflows", LINUX_MIB_LISTENOVERFLOWS),
```

 * `sk_acceptq_is_full(sk)` な状態
 * 3-way handshake が終わったけど、 accept queue が溢れているので、discard されたTCP接続

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

	if (!dst && (dst = inet_csk_route_req(sk, req)) == NULL)
		goto exit;

	newsk = tcp_create_openreq_child(sk, req, skb);
	if (!newsk)
		goto exit_nonewsk;

//...

exit_overflow:
	NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_LISTENOVERFLOWS);
exit_nonewsk:
	dst_release(dst);
exit:
	NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_LISTENDROPS);
	return NULL;
}
```