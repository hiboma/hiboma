# iptables: Memory allocation problem

## CentOS4

```
[root@vagrant ~]# strace -enetwork -f iptables -I INPUT -s 192.168.0.1 -j DROP
socket(PF_INET, SOCK_RAW, IPPROTO_RAW)  = 3
getsockopt(3, SOL_IP, 0x40 /* IP_??? */, "filter\0\0\0\0\0\200\0\0\0\0\0\0\0\0\360\241\201\365\364\234a\365\326\325\21\300"..., [84]) = 0
getsockopt(3, SOL_IP, 0x41 /* IP_??? */, "filter\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"..., [2437032]) = 0
setsockopt(3, SOL_IP, 0x40 /* IP_??? */, "filter\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"..., 2437236) = -1 ENOMEM (Cannot allocate memory)
iptables: Memory allocation problem
```

## setsockopt(2), getsockopt(2)

```
#include <sys/types.h>
#include <sys/socket.h>

int getsockopt(int sockfd, int level, int optname, void *optval, socklen_t *optlen);
int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen);
```

0x40, 0x41 のオプション名が分からないなー

