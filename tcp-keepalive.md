# TCP keepalive

サーバ側の Ethernet インタフェースを down させた場合の挙動を見る

## 検証のフロー

```
                  LISTEN
[host1]           [host2]

# host1 から host2 に TCP接続する

ESTABLISHED       ESTABLISHED
[host1] --------> [host2]

# host2 で ifconfig eth1 down
# host1 は 検知できてない

ESTABLISHED       ESTABLISHED
[host1] --------x [host2]

# host1 から keepalive パケットが飛ぶ
# host2 から 応答が無い

ESTABLISHED       ESTABLISHED
[host1] ----k---x [host2]

# host1
#   poll(2)     が POLLHUP
#   recvfrom(2) が ETIMEDOUT
# host2
#   ESTABLISHED のまま
[host1] x       x [host2]
```

## 検証のコマンド

検証用にクライアント側で極端に短い keepalive 設定にする

```
sudo sysctl -w net.ipv4.tcp_keepalive_time=5
sudo sysctl -w net.ipv4.tcp_keepalive_intvl=1
sudo sysctl -w net.ipv4.tcp_keepalive_probes=1
```

サーバは nc で待機する

```
nc -l 8080
```

クライントが適当に繋ぐ。しばらくすると keepalive の probe パケットを出す

```
curl 192.168.1.101

# probe パケット
15:23:42.952735 IP (tos 0x0, ttl 64, id 48968, offset 0, flags [DF], proto TCP (6), length 52)
    192.168.1.100.55887 > 192.168.1.101.webcache: Flags [.], cksum 0xc4d4 (correct), seq 0, ack 1, win 229, options [nop,nop,TS val 3674888 ecr 3630892], length 0

# probe パケットへの応答
15:23:42.953020 IP (tos 0x0, ttl 64, id 41262, offset 0, flags [DF], proto TCP (6), length 52)
    192.168.1.101.webcache > 192.168.1.100.55887: Flags [.], cksum 0xd84d (correct), seq 1, ack 1, win 243, options [nop,nop,TS val 3635893 ecr 3664887], length 0
```

ここでサーバの Ethernet インタフェースを down させる

```
sudo ifconfig eth1 down
```

クライアントのプロセスは poll(2) で待ち続ける
クライアントのカーネルが keepalive パケットを net.ipv4.tcp_keepalive_probes回 * net.ipv4.tcp_keepalive_intvl秒間隔で送るが応答が無いので、poll(2) を通してプロセスに通知される

```
# 1回目
15:24:27.953813 IP (tos 0x0, ttl 64, id 48977, offset 0, flags [DF], proto TCP (6), length 52)
    192.168.1.100.55887 > 192.168.1.101.webcache: Flags [.], cksum 0x653f (correct), seq 0, ack 1, win 229, options [nop,nop,TS val 3719890 ecr 3675894], length 0

# 2回目
15:24:28.954780 IP (tos 0x0, ttl 64, id 48978, offset 0, flags [DF], proto TCP (6), length 52)
    192.168.1.100.55887 > 192.168.1.101.webcache: Flags [R.], cksum 0x6152 (correct), seq 1, ack 1, win 229, options [nop,nop,TS val 3720890 ecr 3675894], length 0
```

## まとめ

 * プロセスのタイムアウト < keepalive のタイムアウトの場合、プロセス側でも検知できる
 * プロセスのタイムアウト > keepalive のタイムアウトの場合、カーネル側で検知してプロセスに通知
   * プロセスが select(2) や poll(2) で待機している場合に限る? 何かパケット送れば不達であることを確認できるか?

## TODO

 * keepalive パケットの仕様
 * eth1 down してもサーバ側のソケットが ESTABLISHED なままなのは何故?
 * setsockopt(2) での指定方法
   * TCP_KEEPCNT
   * TCP_KEEPIDLE, SO_KEEPALIVE
   * TCP_KEEPINTVL

