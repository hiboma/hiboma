# AF_UNIX の sk_max_ack_backlog

## SOCK_STREAM の場合

 * sk->sk_receive_queue が accept(2)/connect(2) と sendmsg(2)/recvmsg(2) の二つの用途のキューとして扱われている

#### listen(2) 

サーバが listen(2) する際に backlog sk->sk_max_ack_backlog をセットする

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
	/* バックログに余裕がでるので、再接続を促すため? */
	if (backlog > sk->sk_max_ack_backlog)
		wake_up_interruptible_all(&u->peer_wait);

	sk->sk_max_ack_backlog	= backlog;
	sk->sk_state		= TCP_LISTEN;
	/* set credentials so connect can copy them */
	init_peercred(sk);
	err = 0;
```

#### accept(2)

サーバは unix_accept で accept(2) する

 * skb_recv_datagram で connect(2) してきたクライアントの sk_buff を取る
   * connect(2) の sk_buff を datagram 扱いする
   * sk->sk_receive_queue から sk_buff 取ってる
     * AF_INET と全然違う仕組みなので注意 ( AF_INET は icksk_accept_queue, syn_tables )

```c
static int unix_accept(struct socket *sock, struct socket *newsock, int flags)
{
	struct sock *sk = sock->sk;
	struct sock *tsk;
	struct sk_buff *skb;
	int err;

	err = -EOPNOTSUPP;
	if (sock->type != SOCK_STREAM && sock->type != SOCK_SEQPACKET)
		goto out;

	err = -EINVAL;
	if (sk->sk_state != TCP_LISTEN)
		goto out;

	/* If socket state is TCP_LISTEN it cannot change (for now...),
	 * so that no locks are necessary.
	 */

	skb = skb_recv_datagram(sk, 0, flags&O_NONBLOCK, &err);
	if (!skb) {
		/* This means receive shutdown. */
		if (err == 0)
			err = -EINVAL;
		goto out;
	}

	tsk = skb->sk;
	skb_free_datagram(sk, skb);
    /* クライアントを起床、データを何か送ってもらう */
	wake_up_interruptible(&unix_sk(sk)->peer_wait);

	/* attach accepted sock to socket */
	unix_state_lock(tsk);
	newsock->state = SS_CONNECTED;
	sock_graft(tsk, newsock);
	unix_state_unlock(tsk);
	return 0;

out:
	return err;
}
```

#### connect(2)

AF_UNIX + SOCK_STREAM では unix_recvq_full で backlog を超えたかどうかを判定する

```c
static inline int unix_recvq_full(struct sock const *sk)
{
	return skb_queue_len(&sk->sk_receive_queue) > sk->sk_max_ack_backlog;
}
```

クライアントは unix_stream_connect で connect(2) する

 * unix_recvq_full の場合は EAGAIN もしくはブロックする
 * connect(2) が sk_receive_queue にキューイングされている。
   * sk_receive_queue UDPと扱いがい違うのでややこしい

```c
static int unix_stream_connect(struct socket *sock, struct sockaddr *uaddr,
			       int addr_len, int flags)
{
	struct sockaddr_un *sunaddr = (struct sockaddr_un *)uaddr;
	struct sock *sk = sock->sk;
	struct net *net = sock_net(sk);
	struct unix_sock *u = unix_sk(sk), *newu, *otheru;
	struct sock *newsk = NULL;
	struct sock *other = NULL;
	struct sk_buff *skb = NULL;
	unsigned hash;
	int st;
	int err;
	long timeo;

//...    

	if (unix_recvq_full(other)) {
		err = -EAGAIN;
		if (!timeo)
			goto out_unlock;

		timeo = unix_wait_for_peer(other, timeo);

		err = sock_intr_errno(timeo);
		if (signal_pending(current))
			goto out;
		sock_put(other);
		goto restart;
	}

//...    
	/* take ten and and send info to listening sock */
	spin_lock(&other->sk_receive_queue.lock);
	__skb_queue_tail(&other->sk_receive_queue, skb);
	spin_unlock(&other->sk_receive_queue.lock);
	unix_state_unlock(other);
	other->sk_data_ready(other, 0);
	sock_put(other);
	return 0;
```    