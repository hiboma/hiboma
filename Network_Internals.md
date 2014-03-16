## ソケットレイヤ

````
+-------------------+
  BSD Socket Layer
+---------^---------+
          |
   struct net_proto_family ソケットのコンストラクタ
   struct proto_ops        AFレイヤから BSDレイヤへ export されるメソッド
          |
+-------------------+
  AF_* Socket Layer
+-------------------+
          |
  struct inet_protos  ( IP -> tranport )
  struct proto        ( AF_INET -> transport )
  struct inet_protosw ?
          |
+-------------------+
    transport layer
+-------------------+
```

struct proto_ops

 * PF_INET
   * inet_stream_ops
   * inet_dgram_ops
   * inet_sockraw_ops
 * PF_UNIX
   * unix_stream_ops (SOCK_STREAM)
   * unix_dgram_ops  (SOCK_DGRAM)
   * unix_seqpacket_ops (SOCK_SEQPACKET)

struct socket の sock->ops

struct proto

 * udp_prot
 * udpv6_prot
 * tcp_prot
 * tcpv6_prot
 * unix_proto
 * packet_proto
 * netlink_proto
 * ping_prot

struct inet_protosw で結びつけされる

 * IPPROTO_TCP  = tcp_prot  + inet_stream_ops
 * IPPROTO_UDP  = udp_prot  + inet_dgram_ops
 * IPPROTO_ICMP = ping_prot + inet_dgram_ops
 * IPPROTO_IP   = rawprot   + inet_sockraw_ops

struct inet_protosw
  
```  c
static struct inet_protosw inetsw_array[] =
{
	{
		.type =       SOCK_STREAM,
		.protocol =   IPPROTO_TCP,
		.prot =       &tcp_prot,
		.ops =        &inet_stream_ops,
		.no_check =   0,
		.flags =      INET_PROTOSW_PERMANENT |
			      INET_PROTOSW_ICSK,
	},

	{
		.type =       SOCK_DGRAM,
		.protocol =   IPPROTO_UDP,
		.prot =       &udp_prot,
		.ops =        &inet_dgram_ops,
		.no_check =   UDP_CSUM_DEFAULT,
		.flags =      INET_PROTOSW_PERMANENT,
       },

       {
		.type =       SOCK_DGRAM,
		.protocol =   IPPROTO_ICMP,
		.prot =       &ping_prot,
		.ops =        &inet_dgram_ops,
		.no_check =   UDP_CSUM_DEFAULT,
		.flags =      INET_PROTOSW_REUSE,
       },

       {
	       .type =       SOCK_RAW,
	       .protocol =   IPPROTO_IP,	/* wild card */
	       .prot =       &raw_prot,
	       .ops =        &inet_sockraw_ops,
	       .no_check =   UDP_CSUM_DEFAULT,
	       .flags =      INET_PROTOSW_REUSE,
       }
};
```  