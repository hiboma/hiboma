## ソケットレイヤ

````
+-------------------+
  BSD Socket Layer
+---------^---------+
          |
   struct net_proto_family ソケットのコンストラクタ
   struct proto_ops        AFレイヤから BSDレイヤへ export されるメソッド
          |
+---------+---------+
  AF_* Socket Layer
+-------------------+
```