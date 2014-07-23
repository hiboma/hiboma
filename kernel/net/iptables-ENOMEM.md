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

0x40, 0x41 のオプション名が分からないなー。 ↓ なんだろか

```
/* IP Cache bits. */
/* Src IP address. */
#define NFC_IP_SRC		0x0001
/* Dest IP address. */
#define NFC_IP_DST		0x0002
/* Input device. */
#define NFC_IP_IF_IN		0x0004
/* Output device. */
#define NFC_IP_IF_OUT		0x0008
/* TOS. */
#define NFC_IP_TOS		0x0010
/* Protocol. */
#define NFC_IP_PROTO		0x0020
/* IP options. */
#define NFC_IP_OPTIONS		0x0040
/* Frag & flags. */
#define NFC_IP_FRAG		0x0080

/* Per-protocol information: only matters if proto match. */
/* TCP flags. */
#define NFC_IP_TCPFLAGS		0x0100
/* Source port. */
#define NFC_IP_SRC_PT		0x0200
/* Dest port. */
#define NFC_IP_DST_PT		0x0400
/* Something else about the proto */
#define NFC_IP_PROTO_UNKNOWN	0x2000
```

```
int nf_setsockopt(struct sock *sk, int pf, int val, char __user *opt,
		  int len)
{
	return nf_sockopt(sk, pf, val, opt, &len, 0);
}

int nf_getsockopt(struct sock *sk, int pf, int val, char __user *opt, int *len)
{
	return nf_sockopt(sk, pf, val, opt, len, 1);
}
```