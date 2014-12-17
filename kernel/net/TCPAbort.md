# TCPAbort* 属

```c
	SNMP_MIB_ITEM("TCPAbortOnData", LINUX_MIB_TCPABORTONDATA),
	SNMP_MIB_ITEM("TCPAbortOnClose", LINUX_MIB_TCPABORTONCLOSE),
	SNMP_MIB_ITEM("TCPAbortOnMemory", LINUX_MIB_TCPABORTONMEMORY),
	SNMP_MIB_ITEM("TCPAbortOnTimeout", LINUX_MIB_TCPABORTONTIMEOUT),
	SNMP_MIB_ITEM("TCPAbortOnLinger", LINUX_MIB_TCPABORTONLINGER),
	SNMP_MIB_ITEM("TCPAbortFailed", LINUX_MIB_TCPABORTFAILED),
```

## TCPAbortOnClose

 * クライアント が close する
 * サーバは、送ってきたデータを読み込まずに TCP_CLOSE に遷移
 * サーバは、RST を送り返す

```c
void tcp_close(struct sock *sk, long timeout)
{
	struct sk_buff *skb;
	int data_was_unread = 0;
	int state;

//...

	/* As outlined in RFC 2525, section 2.17, we send a RST here because
	 * data was lost. To witness the awful effects of the old behavior of
	 * always doing a FIN, run an older 2.1.x kernel or 2.0.x, start a bulk
	 * GET in an FTP client, suspend the process, wait for the client to
	 * advertise a zero window, then kill -9 the FTP client, wheee...
	 * Note: timeout is always zero in such a case.
	 */
	if (data_was_unread) {
		/* Unread data was tossed, zap the connection. */
		NET_INC_STATS_USER(sock_net(sk), LINUX_MIB_TCPABORTONCLOSE);
		tcp_set_state(sk, TCP_CLOSE);
		tcp_send_active_reset(sk, sk->sk_allocation);
```

## TCPAbortOnData

 * SO_LINGER が true で、sk_lingertime を使い切った時
 * 切断する

キューイングされたメッセージを送り切らないまんま、接続断 てこと?

```c
void tcp_close(struct sock *sk, long timeout)
{
	struct sk_buff *skb;
	int data_was_unread = 0;
	int state;

//...    

	if (data_was_unread) {
        // ...
	} else if (sock_flag(sk, SOCK_LINGER) && !sk->sk_lingertime) {
		/* Check zero linger _after_ checking for unread data. */
		sk->sk_prot->disconnect(sk, 0);
		NET_INC_STATS_USER(sock_net(sk), LINUX_MIB_TCPABORTONDATA);
```

SO_LINGER の説明

```
有効になっていると、 close(2) や shutdown(2) は、そのソケットにキューイングされたメッセージがすべて送信完了するか、 linger (居残り) タイムアウトになるまで返らない。無効になっていると、 これらのコールはただちに戻り、クローズ動作はバックグラウンドで行われる。 ソケットのクローズを exit(2) の一部として行った場合には、残っているソケットの クローズ動作は必ずバックグラウンドに送られる。
```

close, shutdown の際にブロックするか否か