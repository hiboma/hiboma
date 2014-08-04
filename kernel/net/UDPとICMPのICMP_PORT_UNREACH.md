# UDP の ECONNREFUSED と ICMP パケット

 * クライアントが対象ホストに UDP で LISTEN していないポートにパケットを飛ばす
 * 対象ホストは ICMP 3番の **Port Unreachable** を返す
 * クライアントはパケットを飛ばす前に connect(2) していれば ICMP のパケットを受信してエラーハンドリングできる
   * Linux の場合 ECONNREFUSED を返した

## ICMP の RFC より

http://www.networksorcery.com/enp/protocol/icmp/msg3.htm

> A host SHOULD generate Destination Unreachable messages with code: 2 (Protocol Unreachable), when the designated transport protocol is not supported; or 3 (Port Unreachable), when the designated transport protocol (e.g., UDP) is unable to demultiplex the datagram but has no protocol mechanism to inform the sender.

## Port Unreachable を確認するには?

```
[vagrant@vagrant-centos65 ~]$ netstat -su
IcmpMsg:
    InType3: 12   # 127.0.0.1 なので同じ
    OutType3: 12  # Port Unreachable
Udp:
    122 packets received
    12 packets to unknown port received.
    0 packet receive errors
    139 packets sent
```


## 検証スクリプトで見てみる

適当なポートにUDPパケットを飛ばす

```
[vagrant@vagrant-centos65 ~]$ ruby -rsocket -e 's = UDPSocket.new; p s.connect("127.0.0.1", 10000); p s.send("", 0, "127.0.0.1", 10000); p s.read'
0
0
-e:1:in `read': Connection refused (Errno::ECONNREFUSED)
        from -e:1
```

対象ホストからは tcpdump で ICMP のパケットが返されているのが取れる

```
$ sudo tcpdump -i lo
14:26:30.012624 IP localhost.38833 > localhost.ndmp: UDP, length 0
14:26:30.012624 IP localhost > localhost: ICMP localhost udp port ndmp unreachable, length 36
```

## カーネルの実装

__udp4_lib_rcv で `icmp_send(skb, ICMP_DEST_UNREACH, ICMP_PORT_UNREACH, 0);` 箇所が相当する


```c
/*
 *	All we need to do is get the socket, and then do a checksum.
 */

int __udp4_lib_rcv(struct sk_buff *skb, struct udp_table *udptable,
		   int proto)
{
	struct sock *sk;
	struct udphdr *uh;
	unsigned short ulen;
	struct rtable *rt = skb_rtable(skb);
	__be32 saddr, daddr;
	struct net *net = dev_net(skb->dev);

	/*
	 *  Validate the packet.
	 */
	if (!pskb_may_pull(skb, sizeof(struct udphdr)))
		goto drop;		/* No space for header. */

	uh   = udp_hdr(skb);
	ulen = ntohs(uh->len);
	saddr = ip_hdr(skb)->saddr;
	daddr = ip_hdr(skb)->daddr;

	if (ulen > skb->len)
		goto short_packet;

	if (proto == IPPROTO_UDP) {
		/* UDP validates ulen. */
		if (ulen < sizeof(*uh) || pskb_trim_rcsum(skb, ulen))
			goto short_packet;
		uh = udp_hdr(skb);
	}

	if (udp4_csum_init(skb, uh, proto))
		goto csum_error;

	if (rt->rt_flags & (RTCF_BROADCAST|RTCF_MULTICAST))
		return __udp4_lib_mcast_deliver(net, skb, uh,
				saddr, daddr, udptable);

	sk = __udp4_lib_lookup_skb(skb, uh->source, uh->dest, udptable);

	if (sk != NULL) {
		int ret = udp_queue_rcv_skb(sk, skb);
		sock_put(sk);

		/* a return value > 0 means to resubmit the input, but
		 * it wants the return to be -protocol, or 0
		 */
		if (ret > 0)
			return -ret;
		return 0;
	}

	if (!xfrm4_policy_check(NULL, XFRM_POLICY_IN, skb))
		goto drop;
	nf_reset(skb);

	/* No socket. Drop packet silently, if checksum is wrong */
	if (udp_lib_checksum_complete(skb))
		goto csum_error;

	UDP_INC_STATS_BH(net, UDP_MIB_NOPORTS, proto == IPPROTO_UDPLITE);
	icmp_send(skb, ICMP_DEST_UNREACH, ICMP_PORT_UNREACH, 0);

	/*
	 * Hmm.  We got an UDP packet to a port to which we
	 * don't wanna listen.  Ignore it.
	 */
	kfree_skb(skb);
	return 0;
```

## UDP の connect(2) と ICMP_PORT_UNREACH を受け取れる仕組み

UDP (AF_INET + SOCK_DGRAM) は connect(2) を ip4_datagram_connect で実装している

```
struct proto udp_prot = {
	.name		   = "UDP",
	.owner		   = THIS_MODULE,
	.close		   = udp_lib_close,
	.connect	   = ip4_datagram_connect,
```