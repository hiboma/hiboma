# TCPLoss*

```c
$ netstat -st | grep loss             
    34023855 times recovered from packet loss due to SACK data
    353061143 TCP data loss events
    365040 timeouts in loss state
```

## カーネル

```c
    SNMP_MIB_ITEM("TCPLossUndo", LINUX_MIB_TCPLOSSUNDO),
	SNMP_MIB_ITEM("TCPLoss", LINUX_MIB_TCPLOSS),
	SNMP_MIB_ITEM("TCPLossFailures", LINUX_MIB_TCPLOSSFAILURES),
```

## TCPLossFailures

 * `icsk->icsk_retransmits == 0` で、
   * 再送の回数?
 * `icsk->icsk_ca_state == TCP_CA_Loss` なら **LINUX_MIB_TCPLOSSFAILURES** とする

```c
/*
 *	The TCP retransmit timer.
 */

void tcp_retransmit_timer(struct sock *sk)
{

//...

	if (icsk->icsk_retransmits == 0) {
		int mib_idx;

		if (icsk->icsk_ca_state == TCP_CA_Disorder) {
			if (tcp_is_sack(tp))
				mib_idx = LINUX_MIB_TCPSACKFAILURES;
			else
				mib_idx = LINUX_MIB_TCPRENOFAILURES;
		} else if (icsk->icsk_ca_state == TCP_CA_Recovery) {
			if (tcp_is_sack(tp))
				mib_idx = LINUX_MIB_TCPSACKRECOVERYFAIL;
			else
				mib_idx = LINUX_MIB_TCPRENORECOVERYFAIL;
		} else if (icsk->icsk_ca_state == TCP_CA_Loss) {
			mib_idx = LINUX_MIB_TCPLOSSFAILURES;
		} else {
			mib_idx = LINUX_MIB_TCPTIMEOUTS;
		}
		NET_INC_STATS_BH(sock_net(sk), mib_idx);
	}
```

