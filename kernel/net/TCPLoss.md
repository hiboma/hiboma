# TCPLoss*

```c
$ netstat -st | grep loss             
    34023855 times recovered from packet loss due to SACK data
    353061143 TCP data loss events
    365040 timeouts in loss state
```

netstat のソースでは下記の通りに対応づけされている

```
204:     { "TCPLossFailures",  N_("%llu timeouts in loss state"), opt_number },
225:     { "TCPLoss", N_("%llu TCP data loss events") },
```

munin だと **Data loss events** で数値でてる

## カーネルの定義

```c
    SNMP_MIB_ITEM("TCPLossUndo", LINUX_MIB_TCPLOSSUNDO),
	SNMP_MIB_ITEM("TCPLoss", LINUX_MIB_TCPLOSS),
	SNMP_MIB_ITEM("TCPLossFailures", LINUX_MIB_TCPLOSSFAILURES),
```

## TCPLoss

```c
/* Process an event, which can update packets-in-flight not trivially.
 * Main goal of this function is to calculate new estimate for left_out,
 * taking into account both packets sitting in receiver's buffer and
 * packets lost by network.
 *
 * Besides that it does CWND reduction, when packet loss is detected
 * and changes state of machine.
 *
 * It does _not_ decide what to send, it is made in function
 * tcp_xmit_retransmit_queue().
 */
static void tcp_fastretrans_alert(struct sock *sk, int pkts_acked,
				  int newly_acked_sacked, bool is_dupack,
				  int flag)


//...                  

	/* C. Process data loss notification, provided it is valid. */
	if (tcp_is_fack(tp) && (flag & FLAG_DATA_LOST) &&
	    before(tp->snd_una, tp->high_seq) &&
	    icsk->icsk_ca_state != TCP_CA_Open &&
	    tp->fackets_out > tp->reordering) {
		tcp_mark_head_lost(sk, tp->fackets_out - tp->reordering);
		NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPLOSS);
	}
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

