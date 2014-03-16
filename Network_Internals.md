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