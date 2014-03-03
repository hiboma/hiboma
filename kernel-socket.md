


## sock_create

BSDソケット (struct socket) を作るカーネル内API を辿る

 * __struct socket__
   * type = SOCK_DGRAM || SOCK_STREAM
   * familiy が struct sock のコンストラクとなる
     * PF_INET inet_create
       * sock->ops     の初期化
       * sock->sk = sk の初期化
       * __struct inet_sock__ の初期化
   * ops __struct proto_ops__
   * sk  __struct sock__
     * sk_receive_queue, sk_write_queue, ...
       * __struct sk_buff__ のキュー(実装はリスト)
       * skb_queue_len, skb_dequeue, とかでいじるやつ
     * sk_data_ready 等のコールバック
     * ソケットのバッファ
     * sk->sk_sock = socket 互いに参照
   * state
     * SS_ prefix (SS_CONNECTED, ...)

```c
/**
 *  struct socket - general BSD socket
 *  @state: socket state (%SS_CONNECTED, etc)
 *  @type: socket type (%SOCK_STREAM, etc)
 *  @flags: socket flags (%SOCK_ASYNC_NOSPACE, etc)
 *  @ops: protocol specific socket operations
 *  @fasync_list: Asynchronous wake up list
 *  @file: File back pointer for gc
 *  @sk: internal networking protocol agnostic socket representation
 *  @wait: wait queue for several uses
 */
struct socket {
	socket_state		state;

	kmemcheck_bitfield_begin(type);
	short			type;
	kmemcheck_bitfield_end(type);

	unsigned long		flags;
	/*
	 * Please keep fasync_list & wait fields in the same cache line
	 */
	struct fasync_struct	*fasync_list;
	wait_queue_head_t	wait;

	struct file		*file;
	struct sock		*sk;
	const struct proto_ops	*ops;
};
```

struct socket を作るエントリポイント

```c
sock_create(int family, int type, int protocol, struct socket **res)
```

 * net_proto_family の .create に繋がる
 * net_families[(int)] として確保された静的な配列
```c
struct net_proto_family {
	int		family;
	int		(*create)(struct net *net, struct socket *sock,
				  int protocol, int kern);
	struct module	*owner;
};
```

 * PF_INET の場合は inet_family_ops が選ばれる
```c
static struct net_proto_family inet_family_ops = {
	.family = PF_INET,
	.create = inet_create,
	.owner	= THIS_MODULE,
};
```

 * inet_create は INET なソケット初期化して返す
   * sturct inet_sock
   * struct sock
```c
static int inet_create(struct net *net, struct socket *sock, int protocol,
		       int kern)
{
	struct sock *sk;
	struct inet_protosw *answer;
	struct inet_sock *inet;
	struct proto *answer_prot;
	unsigned char answer_flags;
	char answer_no_check;
	int try_loading_module = 0;
	int err;

	if (unlikely(!inet_ehash_secret))
		if (sock->type != SOCK_RAW && sock->type != SOCK_DGRAM)
			build_ehash_secret();

	sock->state = SS_UNCONNECTED;

	/* Look for the requested type/protocol pair. */
lookup_protocol:
	err = -ESOCKTNOSUPPORT;
	rcu_read_lock();

    // sock->type (SOCK_DGRAM, SOCK_STREAM ...) でイテレート
    // inetsw はほぼ静的な配列
	list_for_each_entry_rcu(answer, &inetsw[sock->type], list) {

		err = 0;
		/* Check the non-wild match. */
		if (protocol == answer->protocol) {
			if (protocol != IPPROTO_IP)
				break;
		} else {
			/* Check for the two wild cases. */
			if (IPPROTO_IP == protocol) {
				protocol = answer->protocol;
				break;
			}
			if (IPPROTO_IP == answer->protocol)
				break;
		}
		err = -EPROTONOSUPPORT;
	}

	if (unlikely(err)) {
		if (try_loading_module < 2) {
			rcu_read_unlock();
			/*
			 * Be more specific, e.g. net-pf-2-proto-132-type-1
			 * (net-pf-PF_INET-proto-IPPROTO_SCTP-type-SOCK_STREAM)
			 */
             // 動的にモジュールを読み込むこともできる
			if (++try_loading_module == 1)
                // call_usermodehelper で modprobe を呼び出す
                // call_modprobe は call_usermodehelper の良サンプル
				request_module("net-pf-%d-proto-%d-type-%d",
					       PF_INET, protocol, sock->type);
			/*
			 * Fall back to generic, e.g. net-pf-2-proto-132
			 * (net-pf-PF_INET-proto-IPPROTO_SCTP)
			 */
			else
				request_module("net-pf-%d-proto-%d",
					       PF_INET, protocol);
			goto lookup_protocol;
		} else
			goto out_rcu_unlock;
	}

	err = -EPERM;
	if (sock->type == SOCK_RAW && !kern && !capable(CAP_NET_RAW))
		goto out_rcu_unlock;

	err = -EAFNOSUPPORT;
	if (!inet_netns_ok(net, protocol))
		goto out_rcu_unlock;

    // メソッドの初期化
	sock->ops = answer->ops;
	answer_prot = answer->prot;
	answer_no_check = answer->no_check;
	answer_flags = answer->flags;
	rcu_read_unlock();

	WARN_ON(answer_prot->slab == NULL);

	err = -ENOBUFS;
	sk = sk_alloc(net, PF_INET, GFP_KERNEL, answer_prot);
	if (sk == NULL)
		goto out;

	err = 0;
	sk->sk_no_check = answer_no_check;
	if (INET_PROTOSW_REUSE & answer_flags)
		sk->sk_reuse = 1;

	inet = inet_sk(sk);
	inet->is_icsk = (INET_PROTOSW_ICSK & answer_flags) != 0;

	if (SOCK_RAW == sock->type) {
		inet->num = protocol;
		if (IPPROTO_RAW == protocol)
			inet->hdrincl = 1;
	}

	if (ipv4_config.no_pmtu_disc)
		inet->pmtudisc = IP_PMTUDISC_DONT;
	else
		inet->pmtudisc = IP_PMTUDISC_WANT;

	inet->id = 0;

	sock_init_data(sock, sk);

	sk->sk_destruct	   = inet_sock_destruct;
	sk->sk_protocol	   = protocol;
	sk->sk_backlog_rcv = sk->sk_prot->backlog_rcv;

	inet->uc_ttl	= -1;
	inet->mc_loop	= 1;
	inet->mc_ttl	= 1;
	inet->mc_all	= 1;
	inet->mc_index	= 0;
	inet->mc_list	= NULL;
	sk_extended(sk)->rcv_tos = 0;

	sk_refcnt_debug_inc(sk);

	if (inet->num) {
		/* It assumes that any protocol which allows
		 * the user to assign a number at socket
		 * creation time automatically
		 * shares.
		 */
		inet->sport = htons(inet->num);
		/* Add to protocol hash chains. */
		sk->sk_prot->hash(sk);
	}

	if (sk->sk_prot->init) {
		err = sk->sk_prot->init(sk);
		if (err)
			sk_common_release(sk);
	}
out:
	return err;
out_rcu_unlock:
	rcu_read_unlock();
	goto out;
}
```

```c
struct proto_ops {
	int		family;
	struct module	*owner;
	int		(*release)   (struct socket *sock);
	int		(*bind)	     (struct socket *sock,
				      struct sockaddr *myaddr,
				      int sockaddr_len);
	int		(*connect)   (struct socket *sock,
				      struct sockaddr *vaddr,
				      int sockaddr_len, int flags);
	int		(*socketpair)(struct socket *sock1,
				      struct socket *sock2);
	int		(*accept)    (struct socket *sock,
				      struct socket *newsock, int flags);
	int		(*getname)   (struct socket *sock,
				      struct sockaddr *addr,
				      int *sockaddr_len, int peer);
	unsigned int	(*poll)	     (struct file *file, struct socket *sock,
				      struct poll_table_struct *wait);
	int		(*ioctl)     (struct socket *sock, unsigned int cmd,
				      unsigned long arg);
	int	 	(*compat_ioctl) (struct socket *sock, unsigned int cmd,
				      unsigned long arg);
	int		(*listen)    (struct socket *sock, int len);
	int		(*shutdown)  (struct socket *sock, int flags);
	int		(*setsockopt)(struct socket *sock, int level,
				      int optname, char __user *optval, unsigned int optlen);
	int		(*getsockopt)(struct socket *sock, int level,
				      int optname, char __user *optval, int __user *optlen);
	int		(*compat_setsockopt)(struct socket *sock, int level,
				      int optname, char __user *optval, unsigned int optlen);
	int		(*compat_getsockopt)(struct socket *sock, int level,
				      int optname, char __user *optval, int __user *optlen);
	int		(*sendmsg)   (struct kiocb *iocb, struct socket *sock,
				      struct msghdr *m, size_t total_len);
	int		(*recvmsg)   (struct kiocb *iocb, struct socket *sock,
				      struct msghdr *m, size_t total_len,
				      int flags);
	int		(*mmap)	     (struct file *file, struct socket *sock,
				      struct vm_area_struct * vma);
	ssize_t		(*sendpage)  (struct socket *sock, struct page *page,
				      int offset, size_t size, int flags);
	ssize_t 	(*splice_read)(struct socket *sock,  loff_t *ppos,
				       struct pipe_inode_info *pipe, size_t len, unsigned int flags);
};
```

## connect(2) と 起床関数

```
$ strace telnet 192.0.0.1 8080
$ strace curl   192.0.0.1 8080
```

telnet は inet_stream_connect で待ちに入る

```
[vagrant@vagrant-centos65 ~]$ cat /proc/4920/stack 
[<ffffffff814c6acc>] inet_stream_connect+0x18c/0x2c0
[<ffffffff81448867>] sys_connect+0xd7/0xf0
[<ffffffff8100b072>] system_call_fastpath+0x16/0x1b
[<ffffffffffffffff>] 0xffffffffffffffff
```

curl は poll_schedule_timeout で待ちに入っていた

```
[vagrant@vagrant-centos65 ~]$ cat /proc/4874/stack 
[<ffffffff8119fce9>] poll_schedule_timeout+0x39/0x60
[<ffffffff811a0487>] do_sys_poll+0x457/0x520
[<ffffffff811a0741>] sys_poll+0x71/0x100
[<ffffffff8100b072>] system_call_fastpath+0x16/0x1b
[<ffffffffffffffff>] 0xffffffffffffffff
```

AF_INET の connect(2) は inet_stream_connect である

```c
const struct proto_ops inet_stream_ops = {
//...
	.connect	   = inet_stream_connect,
```

inet_stream_connect は sk->sk_prot->connect を呼び出し後 inet_wait_for_connect で待つ

```
/*
 *	Connect to a remote host. There is regrettably still a little
 *	TCP 'magic' in here.
 */
int inet_stream_connect(struct socket *sock, struct sockaddr *uaddr,
			int addr_len, int flags)
{

//...

	case SS_UNCONNECTED:
		err = -EISCONN;
		if (sk->sk_state != TCP_CLOSE)
			goto out;

		err = sk->sk_prot->connect(sk, uaddr, addr_len);
		if (err < 0)
			goto out;

// ...

	if ((1 << sk->sk_state) & (TCPF_SYN_SENT | TCPF_SYN_RECV)) {
		/* Error code is set above */
		if (!timeo || !inet_wait_for_connect(sk, timeo))
			goto out;
```

inet_wait_for_connect の中身は 待ちキュー + タイムアウト

 * sk_sleep を wait_queue_t として prepare_to_wait + schedule_timeout で待つ
 * 定期的に起床して signal_pending でシグナルを受信していないか見る
            
```c
static long inet_wait_for_connect(struct sock *sk, long timeo)
{
	DEFINE_WAIT(wait);

	prepare_to_wait(sk->sk_sleep, &wait, TASK_INTERRUPTIBLE);

	/* Basic assumption: if someone sets sk->sk_err, he _must_
	 * change state of the socket from TCP_SYN_*.
	 * Connect() does not allow to get error notifications
	 * without closing the socket.
	 */
	while ((1 << sk->sk_state) & (TCPF_SYN_SENT | TCPF_SYN_RECV)) {
		release_sock(sk);
		timeo = schedule_timeout(timeo);
		lock_sock(sk);
		if (signal_pending(current) || !timeo)
			break;
		prepare_to_wait(sk->sk_sleep, &wait, TASK_INTERRUPTIBLE);
	}
	finish_wait(sk->sk_sleep, &wait);
	return timeo;
}
```

## 割り込みコンテキスト側

(Top Half? Bottom Half?) から sk->sk_sleep で待っているプロセスを起床させるのは以下のコールバック群らしい

```c
struct sock {

	void			(*sk_state_change)(struct sock *sk);
	void			(*sk_data_ready)(struct sock *sk, int bytes);
	void			(*sk_write_space)(struct sock *sk);
	void			(*sk_error_report)(struct sock *sk);
```

実装のサンプルは以下の通り

```c
/*
 *	Default Socket Callbacks
 */

static void sock_def_wakeup(struct sock *sk)
{
	read_lock(&sk->sk_callback_lock);
	if (sk_has_sleeper(sk))
		wake_up_interruptible_all(sk->sk_sleep);
	read_unlock(&sk->sk_callback_lock);
}

static void sock_def_error_report(struct sock *sk)
{
	read_lock(&sk->sk_callback_lock);
	if (sk_has_sleeper(sk))
		wake_up_interruptible_poll(sk->sk_sleep, POLLERR);
	sk_wake_async(sk, SOCK_WAKE_IO, POLL_ERR);
	read_unlock(&sk->sk_callback_lock);
}

static void sock_def_readable(struct sock *sk, int len)
{
	read_lock(&sk->sk_callback_lock);
	if (sk_has_sleeper(sk))
		wake_up_interruptible_sync_poll(sk->sk_sleep, POLLIN | POLLPRI |
						POLLRDNORM | POLLRDBAND);
	sk_wake_async(sk, SOCK_WAKE_WAITD, POLL_IN);
	read_unlock(&sk->sk_callback_lock);
}

static void sock_def_write_space(struct sock *sk)
{
	read_lock(&sk->sk_callback_lock);

	/* Do not wake up a writer until he can make "significant"
	 * progress.  --DaveM
	 */
	if ((atomic_read(&sk->sk_wmem_alloc) << 1) <= sk->sk_sndbuf) {
		if (sk_has_sleeper(sk))
			wake_up_interruptible_sync_poll(sk->sk_sleep, POLLOUT |
						POLLWRNORM | POLLWRBAND);

		/* Should agree with poll, otherwise some programs break */
		if (sock_writeable(sk))
			sk_wake_async(sk, SOCK_WAKE_SPACE, POLL_OUT);
	}

	read_unlock(&sk->sk_callback_lock);
}
```

## コールバックを呼び出す箇所

TCP の場合 tcp_rcv_established の中で sk_data_ready を呼び、 connect(2) を呼んだプロセスを起床させている

```
int tcp_rcv_established(struct sock *sk, struct sk_buff *skb,
			struct tcphdr *th, unsigned len)
{
	struct tcp_sock *tp = tcp_sk(sk);

/// ...

				sk->sk_data_ready(sk, 0);
			return 0;
		}
	}
    
```

UDPの場合 sock_queue_rcv_skb の中で呼び出している

```
int sock_queue_rcv_skb(struct sock *sk, struct sk_buff *skb)
{
	int err = 0;
	int skb_len;
	unsigned long flags;
	struct sk_buff_head *list = &sk->sk_receive_queue;

	if (atomic_read(&sk->sk_rmem_alloc) >= sk->sk_rcvbuf) {
		err = -ENOMEM;
		trace_sock_rcvqueue_full(sk, skb);
		goto out;
	}

	err = sk_filter(sk, skb);
	if (err)
		goto out;

	if (!sk_rmem_schedule(sk, skb->truesize)) {
		err = -ENOBUFS;
		goto out;
	}

	skb->dev = NULL;
	skb_set_owner_r(skb, sk);

	/* Cache the SKB length before we tack it onto the receive
	 * queue.  Once it is added it no longer belongs to us and
	 * may be freed by other threads of control pulling packets
	 * from the queue.
	 */
	skb_len = skb->len;

	spin_lock_irqsave(&list->lock, flags);
	skb->dropcount = atomic_read(&sk->sk_drops);
	__skb_queue_tail(list, skb);
	spin_unlock_irqrestore(&list->lock, flags);

	if (!sock_flag(sk, SOCK_DEAD))
		sk->sk_data_ready(sk, skb_len);
out:
	return err;
}
EXPORT_SYMBOL(sock_queue_rcv_skb);
```

```c
static const struct net_protocol udp_protocol = {
	.handler =	udp_rcv,
	.err_handler =	udp_err,
	.no_policy =	1,
	.netns_ok =	1,
};

// sk->sk_data_ready(sk, skb_len);
//     __skb_queue_tail
// sock_queue_rcv_skb
// __udp_queue_rcv_skb
// udp_queue_rcv_skb
//     sk_add_backlog
// __udp4_lib_rcv
// udp_rcv
//     ret = ipprot->handler(skb);
// ip_local_deliver_finish
// ip_local_deliver
// IPルーティング

static const struct net_protocol tcp_protocol = {
	.handler =	tcp_v4_rcv,
	.err_handler =	tcp_v4_err,
	.no_policy =	1,
	.netns_ok =	1,
};

// sk->sk_data_ready(sk, 0);
//     __skb_queue_tail(&sk->sk_receive_queue, skb);
// tcp_rcv_established
// tcp_v4_do_rcv
//   sk_add_backlog
// tcp_v4_rcv
// ip_local_deliver_finish
// ip_local_deliver
// IPルーティング

```