# netstat -su (UDP) の packet receive errors

## まとめ

```
[root@*** ~]# netstat -su
Udp:
    15312436 packets received
    2139 packets to unknown port received.
    275593336 packet receive errors  <<<< これ
    16445537 packets sent
```

 * UDP のバックログが溢れてパケットが DROP された際にカウントされる
 * rmem_alloc を上げるなどして対応可能
 * UDP のデーモンがバグってるとか、CPU使い切っているとかもあるので rmem_alloc 上げても改善しないケースもあるはず

## とある td-agent サーバー の例

`netstat -su` で表示される `packet receive errors` の数値が激しく高い

```
[root@*** ~]# netstat -su
Udp:
    15312436 packets received
    2139 packets to unknown port received.
    275593336 packet receive errors <<<< これ
    16445537 packets sent
```

だがしかし、この数値が正確に意味するが分からないのでソースを読んで調べます

## packet receive errors の数値はどこから取っている?

`netstat -su` の strace を取ると `packet receive errors` は _/proc/net/snmp_ を読んでるのが分かる

```
[root@*** ~]# cat /proc/net/snmp
Ip: Forwarding DefaultTTL InReceives InHdrErrors InAddrErrors ForwDatagrams InUnknownProtos InDiscards InDelivers OutRequests OutDiscards OutNoRoutes ReasmTimeout ReasmReqds ReasmOKs ReasmFails FragOKs FragFails FragCreates
Ip: 2 64 2359553910 0 105 0 0 0 2359548907 1574820495 0 0 0 0 0 0 0 0 0
Icmp: InMsgs InErrors InDestUnreachs InTimeExcds InParmProbs InSrcQuenchs InRedirects InEchos InEchoReps InTimestamps InTimestampReps InAddrMasks InAddrMaskReps OutMsgs OutErrors OutDestUnreachs OutTimeExcds OutParmProbs OutSrcQuenchs OutRedirects OutEchos OutEchoReps OutTimestamps OutTimestampReps OutAddrMasks OutAddrMaskReps
Icmp: 103688 5264 36009 0 0 0 0 62387 31 1 0 0 0 63735 0 1346 0 0 0 0 1 62387 0 1 0 0
IcmpMsg: InType0 InType3 InType8 InType9 InType13 OutType0 OutType3 OutType8 OutType14
IcmpMsg: 31 36009 62387 5260 1 62387 1346 1 1
Tcp: RtoAlgorithm RtoMin RtoMax MaxConn ActiveOpens PassiveOpens AttemptFails EstabResets CurrEstab InSegs OutSegs RetransSegs InErrs OutRsts
Tcp: 1 200 120000 -1 234534 309763 38103 167842 352 2068545849 1558305981 5333 0 347546
Udp: InDatagrams NoPorts InErrors OutDatagrams RcvbufErrors SndbufErrors
Udp: 15312386 2139 275584595 16445449 4427540 0
UdpLite: InDatagrams NoPorts InErrors OutDatagrams RcvbufErrors SndbufErrors
UdpLite: 0 0 0 0 0 0
```

## カーネルのソースを辿る

/proc/net/snmp に書かれいてる文字列を元に、カーネルのソースを **InDatagrams** で grep すると snmp4_udp_list なる配列が見つかる。 **RcvbufErrors** がそれっぽい数値に見える

```c
static const struct snmp_mib snmp4_udp_list[] = {
	SNMP_MIB_ITEM("InDatagrams", UDP_MIB_INDATAGRAMS),
	SNMP_MIB_ITEM("NoPorts", UDP_MIB_NOPORTS),
	SNMP_MIB_ITEM("InErrors", UDP_MIB_INERRORS),
	SNMP_MIB_ITEM("OutDatagrams", UDP_MIB_OUTDATAGRAMS),
	SNMP_MIB_ITEM("RcvbufErrors", UDP_MIB_RCVBUFERRORS),
	SNMP_MIB_ITEM("SndbufErrors", UDP_MIB_SNDBUFERRORS),
	SNMP_MIB_SENTINEL
};
```

UDP_MIB_RCVBUFERRORS を手がかりにソースを探っていきます

## ("RcvbufErrors", UDP_MIB_RCVBUFERRORS),

UDP_MIB_RCVBUFERRORS は **__udp_queue_rcv_skb** で統計を取っている。

 * sock_queue_rcv_skb が **ENOMEM** を返したら UDP_MIB_RCVBUFERRORS 統計値が ++ される
 * sock_queue_rcv_skb がどういう状態の際に ENOMEM を返すのか?

```c
static int __udp_queue_rcv_skb(struct sock *sk, struct sk_buff *skb)
{
	int rc;

	if (inet_sk(sk)->daddr)
		sock_rps_save_rxhash(sk, skb->rxhash);

	rc = sock_queue_rcv_skb(sk, skb);
	if (rc < 0) {
		int is_udplite = IS_UDPLITE(sk);

		/* Note that an ENOMEM error is charged twice */
		if (rc == -ENOMEM)
            /* ここ */
			UDP_INC_STATS_BH(sock_net(sk), UDP_MIB_RCVBUFERRORS,
					is_udplite);
		UDP_INC_STATS_BH(sock_net(sk), UDP_MIB_INERRORS, is_udplite);
		kfree_skb(skb);
		trace_udp_fail_queue_rcv_skb(rc, sk);
		return -1;
	}

	return 0;
}
```

## sock_queue_rcv_skb の実装は ?

`&sk->sk_rmem_alloc >= sk->sk_rcvbuf` の際に ENOMEM を返す

 * sk_buff を sock の sk_receive_queue に繋ぐ
 * sk_data_ready で通知
 * **ENOMEM** を返した際は、デーモンに通知もされずしれっと DROP される
   * 加えて、UDPなのでクライアント側で気がつく方法も無い

```c
int sock_queue_rcv_skb(struct sock *sk, struct sk_buff *skb)
{
	int err = 0;
	int skb_len;
	unsigned long flags;
	struct sk_buff_head *list = &sk->sk_receive_queue;

    /* ここ */
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

    /* プロセスに通知 */
	if (!sock_flag(sk, SOCK_DEAD))
		sk->sk_data_ready(sk, skb_len);
out:
	return err;
}
EXPORT_SYMBOL(sock_queue_rcv_skb);
```

**net.core.rmem_alloc** を上げると sk->sk_rmem_alloc の数値が上がるはず。チューニングの肝はこの点。

----

## sk->sk_rmem_alloc は何?

 * skb->truesize (sock_buffer + payload ) を加算している
 * socket buffer ( sk_receive_queue ) の使用量

```
  *	@sk_rmem_alloc: receive queue bytes committed
```  

```c
static inline void skb_set_owner_r(struct sk_buff *skb, struct sock *sk)
{
	skb_orphan(skb);
	skb->sk = sk;
	skb->destructor = sock_rfree;
	atomic_add(skb->truesize, &sk->sk_rmem_alloc);
	sk_mem_charge(sk, skb->truesize);
}
```

## sk->sk_rcvbuf は何?

sk->sk_rmem_alloc の取りうる最大値。単位は bytes

```
  *	@sk_rcvbuf: size of receive buffer in bytes
```

inet_crete -> sock_init_data で **sysctl_rmem_default** で初期化される

```
void sock_init_data(struct socket *sock, struct sock *sk)
{

//...

	sk->sk_allocation	=	GFP_KERNEL;
	sk->sk_rcvbuf		=	sysctl_rmem_default;
	sk->sk_sndbuf		=	sysctl_wmem_default;
	sk->sk_state		=	TCP_CLOSE;
```

sysctl_wmem_default は AF_INET なソケットに対してグローバルに影響することが読み取れる

sk->sk_rcvbuf は saetsockopt(2) + SO_RCVBUF でも変更されうる。

 * sysctl_rmem_max 以上の値は渡せない
 * SOCK_MIN_RCVBUF 以下の数値は SOCK_MIN_RCVBUF に丸められる
 * setsockopt(2) に渡した数値を 2倍したものが sk->sk_rcvbuf にセットされる
   * setsockopt(2) を呼ぶ側は sk_buff があることに気がつかないで、実データのサイズで値をセットしようとするので struct sk_buff を含めていい感じに扱うために 2倍

```c
	case SO_RCVBUF:
		/* Don't error on this BSD doesn't and if you think
		   about it this is right. Otherwise apps have to
		   play 'guess the biggest size' games. RCVBUF/SNDBUF
		   are treated in BSD as hints */

		if (val > sysctl_rmem_max)
			val = sysctl_rmem_max;
set_rcvbuf:
		sk->sk_userlocks |= SOCK_RCVBUF_LOCK;
		/*
		 * We double it on the way in to account for
		 * "struct sk_buff" etc. overhead.   Applications
		 * assume that the SO_RCVBUF setting they make will
		 * allow that much actual data to be received on that
		 * socket.
		 *
		 * Applications are unaware that "struct sk_buff" and
		 * other overheads allocate from the receive buffer
		 * during socket buffer allocation.
		 *
		 * And after considering the possible alternatives,
		 * returning the value we actually used in getsockopt
		 * is the most desirable behavior.
		 */
		if ((val * 2) < SOCK_MIN_RCVBUF)
			sk->sk_rcvbuf = SOCK_MIN_RCVBUF;
		else
			sk->sk_rcvbuf = val * 2;
		break;
```

## sk->sk_backlog_rcv とは何か?

**__udp_queue_rcv_skb** は UDPのバックログに突っ込むメソッドである

```c
struct proto udp_prot = {
//...
	.backlog_rcv	   = __udp_queue_rcv_skb,
```

バックロッグのパケットを rcv するのに使われている様子

inet_crete で struct sock の初期化の際に sk_backlog_rcv メソッドがセットされる

```c
	sk->sk_backlog_rcv = sk->sk_prot->backlog_rcv;
```

sk->sk_backlog_rcv を呼び出すのは **sk_backlog_rcv**

```
static inline int sk_backlog_rcv(struct sock *sk, struct sk_buff *skb)
{
	return sk->sk_backlog_rcv(sk, skb);
}
```

sk_backlog_rcv は sk_receive_skb で呼び出されている。 sk_receive_skb 呼び出すソースが見つからない

```c
int sk_receive_skb(struct sock *sk, struct sk_buff *skb, const int nested)
{
	int rc = NET_RX_SUCCESS;

	if (socsk_filter(sk, skb))
		goto discard_and_relse;

	skb->dev = NULL;

    // バックログ + rmem_alloc のサイズを見て、rcvqueue が溢れていないかどうか
    // /*
    //  * Take into account size of receive queue and backlog queue
    //  * Do not take into account this skb truesize,
    //  * to allow even a single big packet to come.
    //  */
    // static inline bool sk_rcvqueues_full(const struct sock *sk, const struct sk_buff *skb,
    // 				     unsigned int limit)
    // {
    // 	unsigned int qsize = sk_extended(sk)->sk_backlog.len +
    // 			     atomic_read(&sk->sk_rmem_alloc);
    // 
    // 	return qsize > limit;
    // }
	if (sk_rcvqueues_full(sk, skb, sk->sk_rcvbuf)) {
		atomic_inc(&sk->sk_drops);
		goto discard_and_relse;
	}
	if (nested)
		bh_lock_sock_nested(sk);
	else
		bh_lock_sock(sk);

    /* ??? */    
	if (!sock_owned_by_user(sk)) {
		/*
		 * trylock + unlock semantics:
		 */
		mutex_acquire(&sk->sk_lock.dep_map, 0, 1, _RET_IP_);

        /* ここで sk_backlog_rcv */
		rc = sk_backlog_rcv(sk, skb);

		mutex_release(&sk->sk_lock.dep_map, 1, _RET_IP_);
	} else if (sk_add_backlog(sk, skb, sk->sk_rcvbuf)) {
		bh_unlock_sock(sk);
		atomic_inc(&sk->sk_drops);
		goto discard_and_relse;
	}

	bh_unlock_sock(sk);
out:
	sock_put(sk);
	return rc;
discard_and_relse:
	kfree_skb(skb);
	goto out;
}
EXPORT_SYMBOL(sk_receive_skb);
```

----

 * http://vger.kernel.org/~davem/skb_sk.html
 * http://www.haifux.org/lectures/217/netLec5.pdf

> When do RcvbufErrors occur ?
> The total number of bytes queued in sk_receive_queue queue of a socket is sk->sk_rmem_alloc.
> The total allowed memory of a socket is sk->sk_rcvbuf. It can be retrieved with getsockopt() using SO_RCVBUF.
> Each time a packet is received, the sk- >sk_rmem_alloc is incremented by skb->truesize:
> skb->truesize it the size (in bytes) allocated for the data of the skb plus the size of sk_buff structure itself.

 * sk->sk_rcvbuf = 最大値
 * sk->sk_rmem_alloc = sk_receive_queue の使用量
 * skb->truesize = sizeof(sk_buff) + payload
   * パケットが届くと sk->sk_rmem_alloc に加算される
