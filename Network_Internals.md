## ソケットレイヤ

 * struct socket => 変数名は sock
 * struct sock   => 変数名は sk

````
+-------------------+
     System Call
+-------------------+
          |
+-------------------+
  BSD Socket Layer
+-------------------+
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

#### struct socket

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

#### struct net_proto_family

```c
struct net_proto_family {
	int		family;
	int		(*create)(struct net *net, struct socket *sock,
				  int protocol, int kern);
	struct module	*owner;
};
```

BSDソケットレイヤからプロトコルファミリのコンストラクタとして呼び出しされる

 * inet_family_ops
 * inet6_family_ops
 * unix_family_ops
 * packet_family_ops
 * netlink_family_ops

#### struct proto_ops

`struct socket` の `sock->ops->*`

 * PF_INET
   * inet_stream_ops
   * inet_dgram_ops
   * inet_sockraw_ops
 * PF_INET6
   * inet6_stream_ops
   * inet6_dgram_ops
   * inet6_sockraw_ops
 * PF_UNIX
   * unix_stream_ops (SOCK_STREAM)
   * unix_dgram_ops  (SOCK_DGRAM)
   * unix_seqpacket_ops (SOCK_SEQPACKET)
 * PF_NETLINK
   * netlink_ops
 * PF_PACKET
   * packet_ops
   * packet_ops_spkt

#### struct proto

`struct sock` の `sk->sk_proto->*`

 * udp_prot
   * `struct inet_sock *inet = inet_sk(sk);`
 * udpv6_prot
 * tcp_prot
   * `struct tcp_sock *tp = tcp_sk(sk)`
 * tcpv6_prot
 * unix_proto
 * packet_proto
 * netlink_proto
 * ping_prot

#### struct inet_protosw

struct proto_ops と struct proto が結びつけされる

 * IPPROTO_TCP  = tcp_prot  + inet_stream_ops
 * IPPROTO_UDP  = udp_prot  + inet_dgram_ops
 * IPPROTO_ICMP = ping_prot + inet_dgram_ops
 * IPPROTO_IP   = rawprot   + inet_sockraw_ops

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