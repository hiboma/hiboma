## timeout あれこれ

 * プロトコルは TCP/IP
 * /proc/sys/net/ipv4/tcp_syn_retries はデフォルト値

　| syscall | 何のタイムアウト? | 
----|:----:|:----:
wget --dns-timeout | setitimer(2) + ITIMER_REAL | ホスト名前解決のタイムアウト (nscd, hosts, dns 等) |
wget --connect-timeout | setitimer(2) + ITTIMER_REAL | connect(2) のタイムアウト
wget --read-timeout | select(2) | connect(2)後、idle時間(= データを受信しない時間) でのタイムアウト
wget --timeout | - | 上記三つをまとめセット | 
curl --connect-timeout | fcntl(2) O_NONBLOCK + poll(2) | connect(2) のタイムアウト
curl --max-time | alarm(2) | curl を実行してからの実時間でのタイムアウト
nc | select(2) | タイムアウト値無し。TCPの再送回数が上限でタイムアウト | 
nc -w | select(2) | connec(2)でタイムアウトした / idle 時間がになったらタイムアウトぽい 

## TCP の SYN再送でタイムアウトになるケース

SYN再送の回数を小さくすると再送のタイムアウト値が短くなるため、ツールで指定した数値よりも早くタイムアウトしうる

####  /proc/sys/net/ipv4/tcp_syn_retries で再送の回数を減らす

```
echo 0 > /proc/sys/net/ipv4/tcp_syn_retries 
```

0 にしても必ず一回の再送 ( 1回目の SYN 送信 -> 1秒 待つ -> 2回目の SYN 送信 -> 2秒待つ ) が入るので 実時間で 3秒以上かかる

### curl でテスト 

```
$ time curl --connect-timeout 999 192.168.100.0
curl: (7) couldn't connect to host

real    0m3.004s
user    0m0.002s
sys     0m0.001s
```

poll が POLLERR|POLLHUP 返す

```
connect(3, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("192.168.100.0")}, 16) = -1 EINPROGRESS (Operation now in progress)
poll([{fd=3, events=POLLOUT|POLLWRNORM}], 1, 1000000) = 1 ([{fd=3, revents=POLLERR|POLLHUP}])
getsockopt(3, SOL_SOCKET, SO_ERROR, [8589934702], [4]) = 0
```

### wget でテスト

```
$ time wget --tries 1 --connect-timeout 999 192.168.100.0
--2014-03-15 00:42:13--  http://192.168.100.0/
Connecting to 192.168.100.0:80... failed: Connection timed out.
Giving up.


real    0m3.003s
user    0m0.001s
sys     0m0.001s
```

wget は connect(2) が ETIMEDOUT 返す

```
setitimer(ITIMER_REAL, {it_interval={0, 0}, it_value={999, 0}}, NULL) = 0
connect(3, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("192.168.100.0")}, 16) = -1 ETIMEDOUT (Connection timed out)
```