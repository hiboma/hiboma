# AttemptFails

## netstat -s

```
$ netstat -s

# ...

Tcp:
    753104 active connections openings
    917634700 passive connection openings
    95662 failed connection attempts ★


```

net-utils

```
statistics.c
124:    {"AttemptFails", N_("%u failed connection attempts"), number},
```

## "AttemptFails" in kernel

```
static const struct snmp_mib snmp4_tcp_list[] = {
	SNMP_MIB_ITEM("RtoAlgorithm", TCP_MIB_RTOALGORITHM),
	SNMP_MIB_ITEM("RtoMin", TCP_MIB_RTOMIN),
	SNMP_MIB_ITEM("RtoMax", TCP_MIB_RTOMAX),
	SNMP_MIB_ITEM("MaxConn", TCP_MIB_MAXCONN),
	SNMP_MIB_ITEM("ActiveOpens", TCP_MIB_ACTIVEOPENS),
	SNMP_MIB_ITEM("PassiveOpens", TCP_MIB_PASSIVEOPENS),
	SNMP_MIB_ITEM("AttemptFails", TCP_MIB_ATTEMPTFAILS), ★
```

## TCP_MIB_ATTEMPTFAILS?

```
void tcp_done(struct sock *sk)
{
	if (sk->sk_state == TCP_SYN_SENT || sk->sk_state == TCP_SYN_RECV)
		TCP_INC_STATS_BH(sock_net(sk), TCP_MIB_ATTEMPTFAILS); ★

	tcp_set_state(sk, TCP_CLOSE);
	tcp_clear_xmit_timers(sk);

	sk->sk_shutdown = SHUTDOWN_MASK;

	if (!sock_flag(sk, SOCK_DEAD))
		sk->sk_state_change(sk);
	else
		inet_csk_destroy_sock(sk);
}
EXPORT_SYMBOL_GPL(tcp_done);
```

## tcp_done ?

```
tcp_done         1018 include/net/tcp.h extern void tcp_done(struct sock *sk);
tcp_done         2924 net/ipv4/tcp.c   EXPORT_SYMBOL_GPL(tcp_done);
tcp_done         4117 net/ipv4/tcp_input.c 	tcp_done(sk);
tcp_done         5897 net/ipv4/tcp_input.c 						tcp_done(sk);
tcp_done         5931 net/ipv4/tcp_input.c 				tcp_done(sk);
tcp_done          482 net/ipv4/tcp_ipv4.c 			tcp_done(sk);
tcp_done          358 net/ipv4/tcp_minisocks.c 	tcp_done(sk);
tcp_done           51 net/ipv4/tcp_timer.c 	tcp_done(sk);
tcp_done           92 net/ipv4/tcp_timer.c 		tcp_done(sk);
tcp_done          562 net/ipv4/tcp_timer.c 	tcp_done(sk);
tcp_done          445 net/ipv6/tcp_ipv6.c 			tcp_done(sk);
```