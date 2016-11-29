# UNIX domain socket のバックログと net.core.somaxxconn

 * UNIX domain socket のバックログに net.core.somaxxconn がどう作用するか読む。
 * バックログのサイズがどのように キューとしてどのように扱われるかを読む

以下のシステムコールを扱う

 * socket(2)
 * connect(2)
 * accept(2)

AF_UNIX + SOCK_STREAM のコードを追っていく

# サーバー: socket(2)

サーバーは socket(2) で UNIX ドメインソケットを作成する。

```c
SYSCALL_DEFINE3(socket, int, family, int, type, int, protocol)
{
	int retval;
	struct socket *sock;
	int flags;

...

	retval = sock_create(family, type, protocol, &sock);
	if (retval < 0)
		goto out;

...
```

```c
int sock_create(int family, int type, int protocol, struct socket **res)
{
	return __sock_create(current->nsproxy->net_ns, family, type, protocol, res, 0);
}
EXPORT_SYMBOL(sock_create);
```

*pf->create()* で protocol family ごとに登録されたソケットのコンストラクタを呼ぶ。 AF_UNIX + SOCK_STREAM の場合は unix_create() を呼び出す

```c
int __sock_create(struct net *net, int family, int type, int protocol,
			 struct socket **res, int kern)
{
	int err;
	struct socket *sock;
	const struct net_proto_family *pf;

...

	err = pf->create(net, sock, protocol, kern);
	if (err < 0)
		goto out_module_put;
```

unix_create() の実装は下記の通り。 unix_create1() でソケットを作ってデスクリプタとして返す

```c
static int unix_create(struct net *net, struct socket *sock, int protocol,
		       int kern)
{
	if (protocol && protocol != PF_UNIX)
		return -EPROTONOSUPPORT;

	sock->state = SS_UNCONNECTED;

	switch (sock->type) {
	case SOCK_STREAM:
		sock->ops = &unix_stream_ops;
		break;
		/*
		 *	Believe it or not BSD has AF_UNIX, SOCK_RAW though
		 *	nothing uses it.
		 */
	case SOCK_RAW:
		sock->type = SOCK_DGRAM;
	case SOCK_DGRAM:
		sock->ops = &unix_dgram_ops;
		break;
	case SOCK_SEQPACKET:
		sock->ops = &unix_seqpacket_ops;
		break;
	default:
		return -ESOCKTNOSUPPORT;
	}

	return unix_create1(net, sock, kern) ? 0 : -ENOMEM;
}
```

*unix_create1()* の一部を抜き出す

```c
static struct sock *unix_create1(struct net *net, struct socket *sock, int kern)
{
	struct sock *sk = NULL;
	struct unix_sock *u;

...

	sk->sk_max_ack_backlog	= net->unx.sysctl_max_dgram_qlen;
```

sk->sk_max_ack_backlog に **net.unix.max_dgram_qlen** をセットしている (が、この後の listen(2) で上書きされる )

# サーバー: listen(2)

socket(2) で作ったソケットで listen(2) する。引数の backlog が somaxconn より大きい場合は somaxconn に切り詰められる

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
		somaxconn = sock_net(sock->sk)->core.sysctl_somaxconn; ★
		if ((unsigned int)backlog > somaxconn)
			backlog = somaxconn;

		err = security_socket_listen(sock, backlog);
		if (!err)
			err = sock->ops->listen(sock, backlog);

		fput_light(sock->file, fput_needed);
	}
	return err;
}
```

AF_UNIX + SOCK_STREAM の場合は *sock->ops->listen()* は *unix_listen* を呼び出す (途中は省略)。 sk->sk_max_ack_backlog に backlog をセットする

```c
static int unix_listen(struct socket *sock, int backlog)
{
	int err;
	struct sock *sk = sock->sk;
	struct unix_sock *u = unix_sk(sk);
	struct pid *old_pid = NULL;

	err = -EOPNOTSUPP;
	if (sock->type != SOCK_STREAM && sock->type != SOCK_SEQPACKET)
		goto out;	/* Only stream/seqpacket sockets accept */
	err = -EINVAL;
	if (!u->addr)
		goto out;	/* No listens on an unbound socket */
	unix_state_lock(sk);
	if (sk->sk_state != TCP_CLOSE && sk->sk_state != TCP_LISTEN)
		goto out_unlock;
	if (backlog > sk->sk_max_ack_backlog)
		wake_up_interruptible_all(&u->peer_wait);
	sk->sk_max_ack_backlog	= backlog; ★
	sk->sk_state		= TCP_LISTEN;
	/* set credentials so connect can copy them */
	init_peercred(sk);
	err = 0;

out_unlock:
	unix_state_unlock(sk);
	put_pid(old_pid);
out:
	return err;
}
```

# クライアント: connect(2) 側

サーバーが作ったソケットに クライアントが connect(2) する

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
	unsigned int hash;
	int st;
	int err;
	long timeo;

	timeo = sock_sndtimeo(sk, flags & O_NONBLOCK);

...

	/* Allocate skb for sending to listening sock */
	skb = sock_wmalloc(newsk, 1, 0, GFP_KERNEL);
	if (skb == NULL)
		goto out;

...

	if (unix_recvq_full(other)) {
		err = -EAGAIN;
		if (!timeo)
			goto out_unlock;

...

	sock_hold(sk);
	unix_peer(newsk)	= sk;
	newsk->sk_state		= TCP_ESTABLISHED;
	newsk->sk_type		= sk->sk_type;
	init_peercred(newsk);
	newu = unix_sk(newsk);
	RCU_INIT_POINTER(newsk->sk_wq, &newu->peer_wq);
	otheru = unix_sk(other);

...

	/* Set credentials */
	copy_peercred(sk, other);

	sock->state	= SS_CONNECTED;
	sk->sk_state	= TCP_ESTABLISHED;
	sock_hold(newsk);

...

	/* take ten and and send info to listening sock */
	spin_lock(&other->sk_receive_queue.lock);
	__skb_queue_tail(&other->sk_receive_queue, skb);
	spin_unlock(&other->sk_receive_queue.lock);
	unix_state_unlock(other);
	other->sk_data_ready(other);
	sock_put(other);
	return 0;

out_unlock:
	if (other)
		unix_state_unlock(other);

...
```

unix_recvq_full() が true の場合

 * ノンブロッキングモードの場合は EAGAIN を返す
 * ブロッキングモードの場合はブロックする

##### unix_recvq_full() は何か?

```c
static inline int unix_recvq_full(struct sock const *sk)
{
	return skb_queue_len(&sk->sk_receive_queue) > sk->sk_max_ack_backlog;
}
```

 * sk->sk_receive_queue が sk->sk_max_ack_backlog より大きい場合に trueとなる
 * sk->sk_receive_queue はサーバの accpet(2) 待ちのキューを意味する (後述する)
 * サーバーの accpet(2) が間に合わず クライアントの connect(2) が溢れていると true になる

##### sk->sk_receive_queue は何か?

```c
	/* Allocate skb for sending to listening sock */
	skb = sock_wmalloc(newsk, 1, 0, GFP_KERNEL);
	if (skb == NULL)
		goto out;

...

    /* other はサーバ側のソケットを指す */
	__skb_queue_tail(&other->sk_receive_queue, skb);
```

 * skb を割り当てて、 other->sk_receive_queue の末尾に繋ぐ
   * socket は *TCP_ESTABLISHED**  unix_sk は **SS_CONNECTED** に遷移する
   * 3 way-handshake 相当を済ませたソケットということで OK ?

connect(2) して accept(2) 待ちの クライアントがいることを skb, sk->sk_receive_queue の仕組みをつかって抽象化している

# サーバー: accept(2)

サーバーは connect(2) を accpet(2) する。 sk->sk_receive_queue から取り出す

```c
static int unix_accept(struct socket *sock, struct socket *newsock, int flags)
{
	struct sock *sk = sock->sk;
	struct sock *tsk;
	struct sk_buff *skb;
	int err;

...

	/* If socket state is TCP_LISTEN it cannot change (for now...),
	 * so that no locks are necessary.
	 */

	skb = skb_recv_datagram(sk, 0, flags&O_NONBLOCK, &err); ★
	if (!skb) {
		/* This means receive shutdown. */
		if (err == 0)
			err = -EINVAL;
		goto out;
	}

	tsk = skb->sk;
	skb_free_datagram(sk, skb);
	wake_up_interruptible(&unix_sk(sk)->peer_wait);

	/* attach accepted sock to socket */
	unix_state_lock(tsk);
	newsock->state = SS_CONNECTED;
	unix_sock_inherit_flags(sock, newsock);
	sock_graft(tsk, newsock);
	unix_state_unlock(tsk);
	return 0;

out:
	return err;
```

*skb_recv_datagram()* で sk->sk_receive_queue から skb を取り出す

 * *skb_recv_datagram()* が操作するキューは sk->sk_receive_queue
 * キューから skb を取り出して skb->sk を見て対向のクライアントを起床させる
 * *datagram* とあるがキューを実装するにあたって datagram の skb 実装を借用しているだけである

```c
struct sk_buff *skb_recv_datagram(struct sock *sk, unsigned int flags,
				  int noblock, int *err)
{
	int peeked, off = 0;

	return __skb_recv_datagram(sk, flags | (noblock ? MSG_DONTWAIT : 0),
				   &peeked, &off, err);
}
EXPORT_SYMBOL(skb_recv_datagram);
```

```c
struct sk_buff *__skb_recv_datagram(struct sock *sk, unsigned int flags,
				    int *peeked, int *off, int *err)
{
	struct sk_buff *skb, *last;
	long timeo;

	timeo = sock_rcvtimeo(sk, flags & MSG_DONTWAIT);

	do {
		skb = __skb_try_recv_datagram(sk, flags, peeked, off, err,
					      &last);
		if (skb)
			return skb;

		if (*err != -EAGAIN)
			break;
	} while (timeo &&
		!__skb_wait_for_more_packets(sk, err, &timeo, last));

	return NULL;
}
EXPORT_SYMBOL(__skb_recv_datagram);
```

```c
struct sk_buff *__skb_try_recv_datagram(struct sock *sk, unsigned int flags,
					int *peeked, int *off, int *err,
					struct sk_buff **last)
{
	struct sk_buff_head *queue = &sk->sk_receive_queue;
	struct sk_buff *skb;
	unsigned long cpu_flags;
	/*
	 * Caller is allowed not to check sk->sk_err before skb_recv_datagram()
	 */
	int error = sock_error(sk);

	if (error)
		goto no_packet;

	do {
		/* Again only user level code calls this function, so nothing
		 * interrupt level will suddenly eat the receive_queue.
		 *
		 * Look at current nfs client by the way...
		 * However, this function was correct in any case. 8)
		 */
		int _off = *off;

		*last = (struct sk_buff *)queue;
		spin_lock_irqsave(&queue->lock, cpu_flags);
		skb_queue_walk(queue, skb) {
			*last = skb;
			*peeked = skb->peeked;
			if (flags & MSG_PEEK) {
				if (_off >= skb->len && (skb->len || _off ||
							 skb->peeked)) {
					_off -= skb->len;
					continue;
				}

				skb = skb_set_peeked(skb);
				error = PTR_ERR(skb);
				if (IS_ERR(skb)) {
					spin_unlock_irqrestore(&queue->lock,
							       cpu_flags);
					goto no_packet;
				}

				atomic_inc(&skb->users);
			} else
				__skb_unlink(skb, queue); // sk->sk_receive_queue から skb をとりだす

			spin_unlock_irqrestore(&queue->lock, cpu_flags);
			*off = _off;
			return skb;
		}

		spin_unlock_irqrestore(&queue->lock, cpu_flags);
	} while (sk_can_busy_loop(sk) &&
		 sk_busy_loop(sk, flags & MSG_DONTWAIT));

	error = -EAGAIN;

no_packet:
	*err = error;
	return NULL;
}
EXPORT_SYMBOL(__skb_try_recv_datagram);
```