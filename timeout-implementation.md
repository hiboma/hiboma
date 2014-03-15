## timeout あれこれ

## 環境

 * プロトコルは TCP/IP だけで試験
 * /proc/sys/net/ipv4/tcp_syn_retries はデフォルト値
 * Vagrant
   * CentOS6.5 2.6.32-431.el6.x86_64

## 便利表

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

___タイムアウト___ と書いてもコンテキストが数種あることが分かる

 * connect(2) = 3way-hand-shake のタイムアウト
 * conncet(2) に成功し、その後のデータ転送のタイムアウト
 * ホスト名解決のタイムアウト
 * コマンド実行時間のタイムアウト

ツールのオプション指定がどのタイムアウト値を変更しているのか把握しておくと捗る

## TCP の SYN再送でタイムアウトになるケース

SYN再送の回数を小さくすると再送のタイムアウト値が短くなるため、ツールで指定した数値よりも早くタイムアウトしうる

```
# 不達の IP に繋ごうとしてタイムアウト
$ time nc 192.168.100.1 80

real    1m3.001s
user    0m0.000s
sys     0m0.000s
```

nc は select(2) のタイムアウトを指定しないのでずっとブロックするはずだけど、 SYNの再送上限に達してが先にタイムアウトする ↓ 下記は SYN再送の tcpdump

```
00:49:58.737282 IP 10.0.2.15.38278 > 192.168.100.1.http: Flags [S], seq 2741378757, win 14600, options [mss 1460,sackOK,TS val 117887789 ecr 0,nop,wscale 7], length 0
00:49:59.736376 IP 10.0.2.15.38278 > 192.168.100.1.http: Flags [S], seq 2741378757, win 14600, options [mss 1460,sackOK,TS val 117888789 ecr 0,nop,wscale 7], length 0
00:50:01.737149 IP 10.0.2.15.38278 > 192.168.100.1.http: Flags [S], seq 2741378757, win 14600, options [mss 1460,sackOK,TS val 117890789 ecr 0,nop,wscale 7], length 0
00:50:05.737388 IP 10.0.2.15.38278 > 192.168.100.1.http: Flags [S], seq 2741378757, win 14600, options [mss 1460,sackOK,TS val 117894790 ecr 0,nop,wscale 7], length 0
00:50:13.738313 IP 10.0.2.15.38278 > 192.168.100.1.http: Flags [S], seq 2741378757, win 14600, options [mss 1460,sackOK,TS val 117902790 ecr 0,nop,wscale 7], length 0
00:50:29.738310 IP 10.0.2.15.38278 > 192.168.100.1.http: Flags [S], seq 2741378757, win 14600, options [mss 1460,sackOK,TS val 117918790 ecr 0,nop,wscale 7], length 0
```

ツールで指定したタイムアウトと合わせて SYN再送も確認する必要がある

#### SYN再送の回数を減らしてタイムアウトを発生させる

/proc/sys/net/ipv4/tcp_syn_retries を変えてテストしてみよう

```sh
echo 0 > /proc/sys/net/ipv4/tcp_syn_retries 
```

0 にしたので SYN 再送回数が 0 に ... ならなかった

 * 0 にしても必ず一回の再送 ( 1回目の SYN 送信 -> 1秒 待つ -> 2回目の SYN 送信 -> 2秒待つ ) が行われて、実時間で __3秒以上___ かかるのだった
```
# 最初の SYN 送信
01:31:03.101121 IP 10.0.2.15.48866 > 192.168.100.0.http: Flags [S], seq 3817435773, win 14600, options [mss 1460,sackOK,TS val 120352153 ecr 0,nop,wscale 7], length 0
# 1秒後に再送
01:31:04.100374 IP 10.0.2.15.48866 > 192.168.100.0.http: Flags [S], seq 3817435773, win 14600, options [mss 1460,sackOK,TS val 120353153 ecr 0,nop,wscale 7], length 0
```
 * tcp の再送は tcpdump などで見ておけばよい
   * 他に何もプロセスいなければ `sudp tcpdump port 80` とかでおk 
   * 再送の間隔については http://d.hatena.ne.jp/rx7/20131129/p1 も大事

### curl でSYN再送タイムアウトのテスト 

```
$ time curl --connect-timeout 999 192.168.100.0
curl: (7) couldn't connect to host

real    0m3.004s
user    0m0.002s
sys     0m0.001s
```

3秒でタイムアウト。 poll が POLLERR|POLLHUP 返している

```
connect(3, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("192.168.100.0")}, 16) = -1 EINPROGRESS (Operation now in progress)
poll([{fd=3, events=POLLOUT|POLLWRNORM}], 1, 1000000) = 1 ([{fd=3, revents=POLLERR|POLLHUP}])
getsockopt(3, SOL_SOCKET, SO_ERROR, [8589934702], [4]) = 0
```

### wget でSYN再送タイムアウトのテスト 

```
$ time wget --tries 1 --connect-timeout 999 192.168.100.0
--2014-03-15 00:42:13--  http://192.168.100.0/
Connecting to 192.168.100.0:80... failed: Connection timed out.
Giving up.


real    0m3.003s
user    0m0.001s
sys     0m0.001s
```

3秒でタイムアウト。wget は connect(2) が ETIMEDOUT 返す

```
setitimer(ITIMER_REAL, {it_interval={0, 0}, it_value={999, 0}}, NULL) = 0
connect(3, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("192.168.100.0")}, 16) = -1 ETIMEDOUT (Connection timed out)
```

# 各種ツールの挙動を調べたログ

## curl --connect-timeout

```
curl --connect-timeout 5 192.168.100.1
```

#### USAGE

```
       --connect-timeout <seconds>
              Maximum  time  in  seconds that you allow the connection to the server to take.  This only limits the connection phase, once curl has connected this
              option is of no more use. See also the -m/--max-time option.

```

#### strace の結果

fcntl(2) O_NONBLOCK + poll(2) で待つ

```
socket(PF_INET, SOCK_STREAM, IPPROTO_TCP) = 3
setsockopt(3, SOL_SOCKET, SO_KEEPALIVE, [1], 4) = 0
fcntl(3, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(3, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
connect(3, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("192.168.100.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
poll([{fd=3, events=POLLOUT|POLLWRNORM}], 1, 5000) = 0 (Timeout)
getsockopt(3, SOL_SOCKET, SO_ERROR, [-4294967296], [4]) = 0
close(3)                                = 0
```

タイムアウトした際のエラーコードは 28 で man curl にも説明が載っている

```
       28     Operation timeout. The specified time-out period was reached according to the conditions.
```

## curl --max-time

#### USAGE

--max-time は実時間で curl の実行を制御する。「curlを実行してからN秒」でタイムアウトする

```
       -m/--max-time <seconds>
              Maximum  time  in  seconds  that you allow the whole operation to take.  This is useful for preventing your batch jobs from hanging for hours due to
              slow networks or links going down.  See also the --connect-timeout option.
```

デカいファイルをダウンロードしている際にタイムアウトする例

```
$ time curl --max-time 5 https://www.kernel.org/pub/linux/kernel/v3.x/linux-3.13.6.tar.xz >/dev/null
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  7 73.6M    7 5494k    0     0   956k      0  0:01:18  0:00:05  0:01:13 1250k
curl: (28) Operation timed out after 5000 milliseconds with 5626456 out of 77194340 bytes received

real	0m5.751s
user	0m0.146s
sys	0m0.100s
```

--max-time の実体は alarm(2) である

```
alarm(5)                              = 0
```

 * コマンドの実行時間を制限するのだから select(2) とか poll(2) だと実現できなそう
 * --read-timeout や --connect-timeout と組み合わせて実装することを考えると alarm(2) 使うしか無さそう

なるほど感高いなー 

## wget --connect-timeout

#### USAGE

```
       --connect-timeout=seconds
           Set the connect timeout to seconds seconds.  TCP connections that take longer to establish will be aborted.  By default, there is no connect timeout,
           other than that implemented by system libraries.
```

connect(2) のタイムアウトを指定してテスト

```
$ wget --connect-timeout 5 192.168.100.1
--2014-03-14 15:31:17--  http://192.168.100.1/
Connecting to 192.168.0.90:80... failed: Connection timed out.
Retrying.

--2014-03-14 15:31:23--  (try: 2)  http://192.168.100.1/
Connecting to 192.168.0.90:80... failed: Connection timed out.
Retrying.

--2014-03-14 15:31:30--  (try: 3)  http://192.168.100.1/
Connecting to 192.168.0.90:80... failed: Connection timed out.
Retrying.
```

wget は勝手に retry するのであった

#### strace の結果

--connect-timeout の実体は setitimer(ITTIMER_REAL) 

```
socket(PF_INET, SOCK_STREAM, IPPROTO_IP) = 3
rt_sigaction(SIGALRM, {0x4291b0, [ALRM], SA_RESTORER|SA_RESTART, 0x7f0282b6e9a0}, {SIG_DFL, [ALRM], SA_RESTORER|SA_RESTART, 0x7f0282b6e9a0}, 8) = 0
rt_sigprocmask(SIG_BLOCK, NULL, [], 8)  = 0
setitimer(ITIMER_REAL, {it_interval={0, 0}, it_value={5, 0}}, NULL) = 0
connect(3, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("192.168.100.1")}, 16) = ? ERESTARTSYS (To be restarted)
--- SIGALRM (Alarm clock) @ 0 (0) ---
rt_sigprocmask(SIG_SETMASK, [], NULL, 8) = 0
rt_sigaction(SIGALRM, {SIG_DFL, [ALRM], SA_RESTORER|SA_RESTART, 0x7f0282b6e9a0}, {0x4291b0, [ALRM], SA_RESTORER|SA_RESTART, 0x7f0282b6e9a0}, 8) = 0
close(3)                                = 0
```

## nc

```
nc 192.168.100.1 80
```

#### strace

nc はタイムアウト値がない

```
connect(3, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("192.168.100.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
select(4, NULL, [3], NULL, NULL)        = 1 (out [3])
getsockopt(3, SOL_SOCKET, SO_ERROR, [6543341856086818926], [4]) = 0
fcntl(3, F_SETFL, O_RDWR)               = 0
close(3)                                = 0
```

システムコール呼び出し側でタイムアウト値をしていしなくとも SYN の再送が先にタイムアウトにいたる

```
15:34:31.679754 IP 10.0.2.15.38186 > 192.168.100.1.http: Flags [S], seq 3071784278, win 14600, options [mss 1460,sackOK,TS val 84560732 ecr 0,nop,wscale 7], length 0
15:34:32.680423 IP 10.0.2.15.38186 > 192.168.100.1.http: Flags [S], seq 3071784278, win 14600, options [mss 1460,sackOK,TS val 84561733 ecr 0,nop,wscale 7], length 0
15:34:34.681910 IP 10.0.2.15.38186 > 192.168.100.1.http: Flags [S], seq 3071784278, win 14600, options [mss 1460,sackOK,TS val 84563734 ecr 0,nop,wscale 7], length 0
15:34:38.681501 IP 10.0.2.15.38186 > 192.168.100.1.http: Flags [S], seq 3071784278, win 14600, options [mss 1460,sackOK,TS val 84567734 ecr 0,nop,wscale 7], length 0
15:34:46.682595 IP 10.0.2.15.38186 > 192.168.100.1.http: Flags [S], seq 3071784278, win 14600, options [mss 1460,sackOK,TS val 84575735 ecr 0,nop,wscale 7], length 0
15:35:02.683394 IP 10.0.2.15.38186 > 192.168.100.1.http: Flags [S], seq 3071784278, win 14600, options [mss 1460,sackOK,TS val 84591735 ecr 0,nop,wscale 7], length 0
```

再送の間隔が ___1 -> 2 -> 4 -> 8 -> 16___ ですね ( http://d.hatena.ne.jp/rx7/20131129/p1 も読んでね )

## nc -w 

```
nc -w 10 192.168.100.0 80
```

#### usage

```
     -w timeout
             If a connection and stdin are idle for more than timeout seconds, then the connection is silently closed.  The -w flag has no effect on the -l
             option, i.e. nc will listen forever for a connection, with or without the -w flag.  The default is no timeout.
```

connection と stdin の idle 時間のタイムアウトらしい

#### strace

connect(2) で待つ場合は select(2) の待ち時間を指すようだ

```
socket(PF_INET, SOCK_STREAM, IPPROTO_TCP) = 3
fcntl(3, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(3, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
connect(3, {sa_family=AF_INET, sin_port=htons(80), sin_addr=inet_addr("192.168.100.0")}, 16) = -1 EINPROGRESS (Operation now in progress)
select(4, NULL, [3], NULL, {10, 0})     = 0 (Timeout)
```

connect(2) した後は poll(2) で待つ時間を指すようだ。不思議

```
socket(PF_INET, SOCK_STREAM, IPPROTO_TCP) = 3
fcntl(3, F_GETFL)                       = 0x2 (flags O_RDWR)
fcntl(3, F_SETFL, O_RDWR|O_NONBLOCK)    = 0
connect(3, {sa_family=AF_INET, sin_port=htons(8080), sin_addr=inet_addr("127.0.0.1")}, 16) = -1 EINPROGRESS (Operation now in progress)
select(4, NULL, [3], NULL, {10, 0})     = 1 (out [3], left {9, 999998})
getsockopt(3, SOL_SOCKET, SO_ERROR, [5936974387507888128], [4]) = 0
fcntl(3, F_SETFL, O_RDWR)               = 0
poll([{fd=3, events=POLLIN}, {fd=0, events=POLLIN}], 2, 10000) = 0 (Timeout)
```

## wget --dns-timeout

#### usage

```
       --dns-timeout=seconds
           Set the DNS lookup timeout to seconds seconds.  DNS lookups that don’t complete within the specified time will fail.  By default, there is no timeout
           on DNS lookups, other than that implemented by system libraries.
```

--dns-timeout は libresolv のタイムアウトも絡むのでややこしい

 * DNS だけでなくて , /etc/hosts を読み込む時間、nscd にクエリを出す時間も含まれる
 * --dns-timeout > libresolv の場合は libreolsv (libnss_dns ?) のタイムアウトが優先される
  * タイムアウトの時間は /etc/resolv.conf に左右される (デフォルトでは５秒のタイムアウト timeout:<N> + リトライ attempts:<N> )
    * see also http://linuxjm.sourceforge.jp/html/LDP_man-pages/man5/resolver.5.html
  * リゾルバに左右されるので無闇に --dns-timeout を長くしても意味は無いことが分かる
 * リゾルバのソケットを select(2) や poll(2) できない??? ので setitimer(2) でタイムアウトしている
   * 個別に見るの大変そうだし ...

nameserver に適当に不達のIP を指定してタイムアウトのテストすると良い  

```
setitimer(ITIMER_REAL, {it_interval={0, 0}, it_value={999, 0}}, NULL) = 0

// nscd にクエリを投げようとする
socket(PF_FILE, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3
connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
close(3)                                = 0

// DNS にクエリを投げる
socket(PF_INET, SOCK_DGRAM|SOCK_NONBLOCK, IPPROTO_IP) = 3
connect(3, {sa_family=AF_INET, sin_port=htons(53), sin_addr=inet_addr("192.168.100.0")}, 16) = 0
poll([{fd=3, events=POLLOUT}], 1, 0)    = 1 ([{fd=3, revents=POLLOUT}])
sendto(3, "\346\374\1\0\0\1\0\0\0\0\0\0\3www\6kernel\3org\0\0\1\0\1", 32, MSG_NOSIGNAL, NULL, 0) = 32
poll([{fd=3, events=POLLIN|POLLOUT}], 1, 5000) = 1 ([{fd=3, revents=POLLOUT}])
sendto(3, "\232\275\1\0\0\1\0\0\0\0\0\0\3www\6kernel\3org\0\0\34\0\1", 32, MSG_NOSIGNAL, NULL, 0) = 32
poll([{fd=3, events=POLLIN}], 1, 4999)  = ? ERESTART_RESTARTBLOCK (To be restarted)
--- SIGALRM (Alarm clock) @ 0 (0) ---
```

## wget --read-timeout

#### usage

```
       --read-timeout=seconds
           Set the read (and write) timeout to seconds seconds.  The "time" of this timeout refers to idle time: if, at any point in the download, no data is
           received for more than the specified number of seconds, reading fails and the download is restarted.  This option does not directly affect the duration
           of the entire download.
```

idle時間のタイムアウトを指定する。
 * idle = データを受信しない時間
 * connect(2) した後のデータ読む段階での select(2) でタイムアウトの時間を指す

```
$ wget --read-timeout=10 127.0.0.1:8080
--2014-03-14 23:20:08--  http://127.0.0.1:8080/
Connecting to 127.0.0.1:8080... connected.
HTTP request sent, awaiting response... Read error (Connection timed out) in headers.
Retrying.

--2014-03-14 23:20:19--  (try: 2)  http://127.0.0.1:8080/
Connecting to 127.0.0.1:8080... failed: Connection refused.
```

テスト時は nc -l 8080 で accept(2) だけする疑似httpd を作れるので そこに向けて wget すればよい

#### strace 

```
socket(PF_INET, SOCK_STREAM, IPPROTO_IP) = 3
connect(3, {sa_family=AF_INET, sin_port=htons(8080), sin_addr=inet_addr("127.0.0.1")}, 16) = 0
write(2, "connected.\n", 11connected.
)            = 11
select(4, NULL, [3], NULL, {10, 0})     = 1 (out [3], left {9, 999998})
write(3, "GET / HTTP/1.0\r\nUser-Agent: Wget"..., 112) = 112
write(2, "HTTP request sent, awaiting resp"..., 40HTTP request sent, awaiting response... ) = 40
select(4, [3], NULL, NULL, {10, 0})     = 0 (Timeout)
```

## wget --timeout=seconds

```
       --timeout=seconds
           Set the network timeout to seconds seconds.  This is equivalent to specifying --dns-timeout, --connect-timeout, and --read-timeout, all at the same
           time.
```

 * 3つまとめてセットくん
 * 大雑把過ぎる気がするので、個別に指定した方がトラブル時の調査も楽なのかな?