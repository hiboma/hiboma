# netstat -su (UDP) の packet receive errors

 * UDP のバックログが溢れてパケットが DROP された際に出る
 * rmem_alloc を上げるなどして対応可能

## とある td-agent サーバー

`netstat -su` で表示される `packet receive errors` の数値が激しく高い

```
[root@*** ~]# netstat -su
Udp:
    15312436 packets received
    2139 packets to unknown port received.
    275593336 packet receive errors
    16445537 packets sent
```

だがしかし、この数値が正確に意味するが分からないのでソースを読んで調べます

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

/proc/net/snmp に書かれいてる文字列を元に **InDatagrams** で grep すると snmp4_udp_list なる配列が見つかる。 **RcvbufErrors** がそれっぽい数値に見える

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

## ("RcvbufErrors", UDP_MIB_RCVBUFERRORS),

UDP_MIB_RCVBUFERRORS は **__udp_queue_rcv_skb** で統計を取っている。

 * sock_queue_rcv_skb が **ENOMEM** を返したら UDP_MIB_RCVBUFERRORS 統計値が ++ される
 * ネットワークスタックの中で何が起こっているのか調べるには これらの数値を追うしかなさげ

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

## sock_queue_rcv_skb ?

 * sk_buff を sock の sk_receive_queue に繋ぐ
 * `&sk->sk_rmem_alloc >= sk->sk_rcvbuf` の際に ENOMEM を返す
 * sk_data_ready で通知

ENOMEM を返した際は、プロセスに通知もされずしれっと DROP されている? 

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

**net.core.rmem_alloc** を上げたら解消するかもってのはこういう原理なのですな

----

## sk->sk_backlog_rcv

ところで **__udp_queue_rcv_skb** は UDPのバックログに突っ込むメソッドである

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