# nss-myhostname がブロックする

## 現象

 * CentOS7 で IPv6 インタフェースを無効にしている
 * systemd-libs が最新(systemd-219.el7_2.5) になっている

条件の元で

 * libnss_myhostname が、マシンのホスト名を名前解決する際に 20数秒の間ブロックする

ということが起こる。実装に即して書くと

 * getaddrinfo(3) + IPv6 で名前解決をする際に、PF_NETLINK + RTM_GETADDR で自ホストの IPv6 IP を取得しようとするが、ここで ppoll(3) がブロックする

## Vagrant CentOS7 で再現の手順

```
# systemd-libs を最新 (systemd-219.el7_2.5) にする
sudo yum update systemd-libs

# IPv6 インタフェースを無効にする
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1

# ホスト名を適当に変える。ただし /etc/hosts に記載されていないものにする。
sudo hostname example.com

# 再現用コードをコンパイルする。getaddrinfo(3) で IPv6 を名前解決するコードです
curl https://gist.githubusercontent.com/hiboma/1743404353ffc3f27e3c/raw/c97f3e846782de24664ab06fcbe4a9cd47368ec8/getaddrinfo.c > getaddrinfo.c
gcc getaddrinfo.c -o getaddrinfo

# 再現コードの実行
./getaddrinfo example.com
```

## ブロックした状態のトレース

#### ltrace

```
# 長いので略
[vagrant@localhost ~]$ ltrace ./getaddrinfo example.com
__libc_start_main(0x400818, 2, 0x7fffb4bad048, 0x400850 <unfinished ...>
memset(0x7fffb4bacf00, '\0', 48)                                                 = 0x7fffb4bacf00
getaddrinfo("example.com", nil, 0x7fffb4bacf00, 0x7fffb4bacef8
```
y
#### gstack

```
#0  0x00007f5cb34d5e79 in ppoll () from /lib64/libc.so.6
#1  0x00007f5cb39b41af in sd_rtnl_call.constprop.10 () from /lib64/libnss_myhostname.so.2
#2  0x00007f5cb39b5f72 in local_addresses.constprop.4 () from /lib64/libnss_myhostname.so.2
#3  0x00007f5cb39b7717 in _nss_myhostname_gethostbyname3_r () from /lib64/libnss_myhostname.so.2
#4  0x00007f5cb34c6982 in gaih_inet () from /lib64/libc.so.6
#5  0x00007f5cb34c9bdd in getaddrinfo () from /lib64/libc.so.6
#6  0x000000000040070b in lookup_host ()
#7  0x000000000040084a in main ()
```

##### ブロックする場合 (systemd-219) の strace

```
uname({sysname="Linux", nodename="example.com", release="3.10.0-123.4.4.el7.x86_64", version="#1 SMP Fri Jul 25 05:07:12 UTC 2014", machine="x86_64", domainname="(none)"}) = 0
socket(PF_NETLINK, SOCK_RAW|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 4 <0.000062>
setsockopt(4, SOL_SOCKET, SO_PASSCRED, [1], 4) = 0 <0.000006>
setsockopt(4, 0x10e /* SOL_?? */, 3, [1], 4) = 0 <0.000005>
bind(4, {sa_family=AF_NETLINK, pid=0, groups=00000000}, 16) = 0 <0.000006>
getsockname(4, {sa_family=AF_NETLINK, pid=3767, groups=00000000}, [12]) = 0 <0.000005>
sendto(4, "\30\0\0\0\26\0\5\3\1\0\0\0\0\0\0\0\n\200\0\0\0\0\0\0", 24, 0, {sa_family=AF_NETLINK, pid=0, groups=00000000}, 16) = 24 <0.000012>
recvmsg(4, {msg_name(0)=NULL, msg_iov(1)=[{NULL, 0}], msg_controllen=56, {cmsg_len=20, cmsg_level=0x10e /* SOL_??? */, cmsg_type=, ...}, msg_flags=MSG_TRUNC}, MSG_PEEK|MSG_TRUNC) = 20 <0.000006>
recvmsg(4, {msg_name(0)=NULL, msg_iov(1)=[{"\24\0\0\0\3\0\2\0\1\0\0\0\267\16\0\0\0\0\0\0", 64}], msg_controllen=56, {cmsg_len=20, cmsg_level=0x10e /* SOL_??? */, cmsg_type=, ...}, msg_flags=0}, MSG_TRUNC) = 20 <0.000005>
ppoll([{fd=4, events=POLLIN}], 1, {24, 999956000}, NULL, 8 ★ ここでブロック
```

##### ブロックしない場合 (systemd-208) の strace

 * socket(2) のオプションが違う SOCK_NONBLOCK が指定されてない
 * ノンブロッキングソケットでないので、ppoll(2) は呼ばないのかな?

````
uname({sysname="Linux", nodename="example.com", release="3.10.0-123.4.4.el7.x86_64", version="#1 SMP Fri Jul 25 05:07:12 UTC 2014", machine="x86_64", domainname="(none)"}) = 0
socket(PF_NETLINK, SOCK_DGRAM, 0)       = 4
setsockopt(4, SOL_SOCKET, SO_PASSCRED, [1], 4) = 0
sendto(4, "\21\0\0\0\26\0\5\3g\22\0\0\0\0\0\0\0", 17, 0, NULL, 0) = 17
recvmsg(4, {msg_name(0)=NULL, msg_iov(1)=[{"L\0\0\0\24\0\2\0g\22\0\0\354\r\0\0\2\10\200\376\1\0\0\0\10\0\1\0\177\0\0\1"..., 16408}], msg_controllen=32, {cmsg_len=28, cmsg_level=SOL_SOCKET, cmsg_type=SCM_CREDENTIALS{pid=0, uid=0, gid=0}}, msg_flags=0}, 0) = 164
recvmsg(4, {msg_name(0)=NULL, msg_iov(1)=[{"H\0\0\0\24\0\2\0g\22\0\0\354\r\0\0\n\200\200\376\1\0\0\0\24\0\1\0\0\0\0\0"..., 16408}], msg_controllen=32, {cmsg_len=28, cmsg_level=SOL_SOCKET, cmsg_type=SCM_CREDENTIALS{pid=0, uid=0, gid=0}}, msg_flags=0}, 0) = 144
recvmsg(4, {msg_name(0)=NULL, msg_iov(1)=[{"\24\0\0\0\3\0\2\0g\22\0\0\354\r\0\0\0\0\0\0", 16408}], msg_controllen=32, {cmsg_len=28, cmsg_level=SOL_SOCKET, cmsg_type=SCM_CREDENTIALS{pid=0, uid=0, gid=0}}, msg_flags=0}, 0) = 20
close(4)                                = 0
```

## 原因のソース

この [コミット](https://github.com/systemd/systemd/commit/d1ca51b153d7854d49400289ddedc7d493458f71) が原因かな?

 * nss-myhostname の ソケットハンドリングを `sd-rtnl` というやり方に変えたのが原因ぽい
 * CentOS7 の場合は、systemd-libs-208 から systemd-libs-219 にバージョンがジャンプする際に上記のコミットが取り込まれている

#### 実装の詳細

 * getaddrinfo が nss-myhostname の [_nss_myhostname_gethostbyname4_r](https://github.com/systemd/systemd/blob/v219/src/nss-myhostname/nss-myhostname.c#57) を呼ぶのでここを辿る
   * タイムアウト指定は [ここ](https://github.com/systemd/systemd/blob/v219/src/libsystemd/sd-bus/bus-internal.h#L327) で25秒になっている
   * ppoll(2) は [ここ](https://github.com/systemd/systemd/blob/v219/src/libsystemd/sd-rtnl/sd-rtnl.c#577) で呼び出している

