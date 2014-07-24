# netstat -su (UDP) の packet receive errors

## とある td-agent サーバー

`netstat -su` で表示される `packet receive errors` の意味が分からない

```
[root@*** ~]# netstat -su
Udp:
    15312436 packets received
    2139 packets to unknown port received.
    275593336 packet receive errors
    16445537 packets sent
```

strace を取ると `packet receive errors` は _/proc/net/snmp_ を読んでるのが分かる

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

**InDatagrams** で grep すると snmp4_udp_list なる配列が見つかる。 **RcvbufErrors** がそれっぽい数値に見える

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

## SNMP_MIB_ITEM("RcvbufErrors", UDP_MIB_RCVBUFERRORS),

UDP_MIB_RCVBUFERRORS は **__udp_queue_rcv_skb** で統計を取っている。

 * sock_queue_rcv_skb が **ENOMEM** を返したら UDP_MIB_RCVBUFERRORS 統計値が ++ される

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

 * &sk->sk_rmem_alloc) >= sk->sk_rcvbuf で ENOMEM

```c
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