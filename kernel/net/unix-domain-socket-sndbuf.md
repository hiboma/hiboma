# sndbuf - UNIX Domain Socket

## What is SO_SNDBUF option ?

see http://man7.org/linux/man-pages/man7/socket.7.html

```
       SO_SNDBUF
              Sets or gets the maximum socket send buffer in bytes.  The
              kernel doubles this value (to allow space for bookkeeping
              overhead) when it is set using setsockopt(2), and this doubled
              value is returned by getsockopt(2).  The default value is set
              by the /proc/sys/net/core/wmem_default file and the maximum
              allowed value is set by the /proc/sys/net/core/wmem_max file.
              The minimum (doubled) value for this option is 2048.
```

## SO_SNDBUF for UNIX domain sockets

ref http://man7.org/linux/man-pages/man7/unix.7.html

```
       The SO_SNDBUF socket option does have an effect for UNIX domain
       sockets, but the SO_RCVBUF option does not.  For datagram sockets,
       the SO_SNDBUF value imposes an upper limit on the size of outgoing
       datagrams.  This limit is calculated as the doubled (see socket(7))
       option value less 32 bytes used for overhead.
```

important: **but the SO_RCVBUF option does not (have effect)**

## How SO_RCVBUF is set?

setsockopt(2)

```c
/*
 *	This is meant for all protocols to use and covers goings on
 *	at the socket level. Everything here is generic.
 */

int sock_setsockopt(struct socket *sock, int level, int optname,
		    char __user *optval, int optlen)
{
	struct sock *sk=sock->sk;
	struct sk_filter *filter;
	int val;
	int valbool;
	struct linger ling;
	int ret = 0;
	

 ...

		case SO_SNDBUF:
			/* Don't error on this BSD doesn't and if you think
			   about it this is right. Otherwise apps have to
			   play 'guess the biggest size' games. RCVBUF/SNDBUF
			   are treated in BSD as hints */
			   
			if (val > sysctl_wmem_max)
				val = sysctl_wmem_max;
set_sndbuf:
			sk->sk_userlocks |= SOCK_SNDBUF_LOCK;
			if ((val * 2) < SOCK_MIN_SNDBUF)        
				sk->sk_sndbuf = SOCK_MIN_SNDBUF; // 2048
			else
				sk->sk_sndbuf = val * 2;

			/*
			 *	Wake up sending tasks if we
			 *	upped the value.
			 */
			sk->sk_write_space(sk);
			break;
```

 * SO_SNDBUF is doubled and set in sk->sk_sndbuf;
 * sysctl.wmem_max overrides SO_SNDBUF value if `SO_SNDBUF > sysctl_wmem_max`.

## default value of sk->sk_sndbuf

`sysctl_wmem_default`

```
void sock_init_data(struct socket *sock, struct sock *sk)
{
	skb_queue_head_init(&sk->sk_receive_queue);
	skb_queue_head_init(&sk->sk_write_queue);
	skb_queue_head_init(&sk->sk_error_queue);
#ifdef CONFIG_NET_DMA
	skb_queue_head_init(&sk->sk_async_wait_queue);
#endif

	sk->sk_send_head	=	NULL;

	init_timer(&sk->sk_timer);
	
	sk->sk_allocation	=	GFP_KERNEL;
	sk->sk_rcvbuf		=	sysctl_rmem_default;
	sk->sk_sndbuf		=	sysctl_wmem_default;
	sk->sk_state		=	TCP_CLOSE;
	sk->sk_socket		=	sock;
```

`net.core.wmem_default` is set to 208KB on CentOS7.

```
[vagrant@localhost ~]$ cat /etc/redhat-release 
CentOS Linux release 7.0.1406 (Core)

[vagrant@localhost ~]$ uname -a
Linux localhost.localdomain 3.10.0-327.13.1.el7.x86_64 #1 SMP Thu Mar 31 16:04:38 UTC 2016 x86_64 x86_64 x86_64 GNU/Linux

[vagrant@localhost ~]$ sysctl net.core.wmem_default
net.core.wmem_default = 212992  # 208KB
```

## in net/unix/af_unix.c

 * (1) sk->sk_sndbuf is used in unix_writable

```
static inline int unix_writable(struct sock *sk)
{
	return (atomic_read(&sk->sk_wmem_alloc) << 2) <= sk->sk_sndbuf;
}
```

 * (2)

```c
static int unix_stream_sendmsg(struct kiocb *kiocb, struct socket *sock,
			       struct msghdr *msg, size_t len)
{
	struct sock_iocb *siocb = kiocb_to_siocb(kiocb);
	struct sock *sk = sock->sk;
	struct sock *other = NULL;
	int err, size;
	struct sk_buff *skb;
	int sent = 0;
	struct scm_cookie tmp_scm;
	bool fds_sent = false;
	int max_level;
	int data_len;

	if (NULL == siocb->scm)
		siocb->scm = &tmp_scm;
	wait_for_unix_gc();
	err = scm_send(sock, msg, siocb->scm, false);
	if (err < 0)
		return err;

	err = -EOPNOTSUPP;
	if (msg->msg_flags&MSG_OOB)
		goto out_err;

	if (msg->msg_namelen) {
		err = sk->sk_state == TCP_ESTABLISHED ? -EISCONN : -EOPNOTSUPP;
		goto out_err;
	} else {
		err = -ENOTCONN;
		other = unix_peer(sk);
		if (!other)
			goto out_err;
	}

	if (sk->sk_shutdown & SEND_SHUTDOWN)
		goto pipe_err;

	while (sent < len) {
		size = len - sent;

		/* Keep two messages in the pipe so it schedules better */
		size = min_t(int, size, (sk->sk_sndbuf >> 1) - 64);

		if (size > SKB_MAX_ALLOC)
			size = SKB_MAX_ALLOC;
			
		/*
		 *	Grab a buffer
		 */
		 
		skb=sock_alloc_send_skb(sk,size,msg->msg_flags&MSG_DONTWAIT, &err);

		if (skb==NULL)
			goto out_err;

		/*
		 *	If you pass two values to the sock_alloc_send_skb
		 *	it tries to grab the large configurationsbuffer with GFP_NOFS
		 *	(which can fail easily), and if it fails grab the
		 *	fallback size buffer which is under a page and will
		 *	succeed. [Alan]
		 */
		size = min_t(int, size, skb_tailroom(skb));

		memcpy(UNIXCREDS(skb), &siocb->scm->creds, sizeof(struct ucred));
		if (siocb->scm->fp)
			unix_attach_fds(siocb->scm, skb);

		if ((err = memcpy_fromiovec(skb_put(skb,size), msg->msg_iov, size)) != 0) {
			kfree_skb(skb);
			goto out_err;
		}

		unix_state_rlock(other);

		if (sock_flag(other, SOCK_DEAD) ||
		    (other->sk_shutdown & RCV_SHUTDOWN))
			goto pipe_err_free;

		skb_queue_tail(&other->sk_receive_queue, skb);
		unix_state_runlock(other);
		other->sk_data_ready(other, size);
		sent+=size;
	}

	scm_destroy(siocb->scm);
	siocb->scm = NULL;

	return sent;

pipe_err_free:
	unix_state_runlock(other);
	kfree_skb(skb);
pipe_err:
	if (sent==0 && !(msg->msg_flags&MSG_NOSIGNAL))
		send_sig(SIGPIPE,current,0);
	err = -EPIPE;
out_err:
	scm_destroy(siocb->scm);
	siocb->scm = NULL;
	return sent ? : err;
}
```

```c
		skb=sock_alloc_send_skb(sk,size,msg->msg_flags&MSG_DONTWAIT, &err);
```

```c
struct sk_buff *sock_alloc_send_skb(struct sock *sk, unsigned long size, 
				    int noblock, int *errcode)
{
	return sock_alloc_send_pskb(sk, size, 0, noblock, errcode);
}
```

```c
/*
 *	Generic send/receive buffer handlers
 */

static struct sk_buff *sock_alloc_send_pskb(struct sock *sk,
					    unsigned long header_len,
					    unsigned long data_len,
					    int noblock, int *errcode)
{
	struct sk_buff *skb;
	gfp_t gfp_mask;
	long timeo;
	int err;

	gfp_mask = sk->sk_allocation;
	if (gfp_mask & __GFP_WAIT)
		gfp_mask |= __GFP_REPEAT;

	timeo = sock_sndtimeo(sk, noblock);
	while (1) {
		err = sock_error(sk);
		if (err != 0)
			goto failure;

		err = -EPIPE;
		if (sk->sk_shutdown & SEND_SHUTDOWN)
			goto failure;

		if (atomic_read(&sk->sk_wmem_alloc) < sk->sk_sndbuf) {
			skb = alloc_skb(header_len, sk->sk_allocation);
			if (skb) {
				int npages;
				int i;

				/* No pages, we're done... */
				if (!data_len)
					break;

				npages = (data_len + (PAGE_SIZE - 1)) >> PAGE_SHIFT;
				skb->truesize += data_len;
				skb_shinfo(skb)->nr_frags = npages;
				for (i = 0; i < npages; i++) {
					struct page *page;
					skb_frag_t *frag;

					page = alloc_pages(sk->sk_allocation, 0);
					if (!page) {
						err = -ENOBUFS;
						skb_shinfo(skb)->nr_frags = i;
						kfree_skb(skb);
						goto failure;
					}

					frag = &skb_shinfo(skb)->frags[i];
					frag->page = page;
					frag->page_offset = 0;
					frag->size = (data_len >= PAGE_SIZE ?
						      PAGE_SIZE :
						      data_len);
					data_len -= PAGE_SIZE;
				}

				/* Full success... */
				break;
			}
			err = -ENOBUFS;
			goto failure;
		}
		set_bit(SOCK_ASYNC_NOSPACE, &sk->sk_socket->flags);
		set_bit(SOCK_NOSPACE, &sk->sk_socket->flags);
		err = -EAGAIN;
		if (!timeo)
			goto failure;
		if (signal_pending(current))
			goto interrupted;
		timeo = sock_wait_for_wmem(sk, timeo);
	}

	skb_set_owner_w(skb, sk);
	return skb;

interrupted:
	err = sock_intr_errno(timeo);
failure:
	*errcode = err;
	return NULL;
}
```
