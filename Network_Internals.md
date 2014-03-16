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

struct inet_protos

 * inet_stream_ops
 * inet_dgram_ops
 * inet_sockraw_ops

struct proto

 * udp_prot, udpv6_prot
 * tcp_prot, tcpv6_prot
 * unix_proto
 * packet_proto
 * netlink_proto
