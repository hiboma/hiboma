# netstat の Recv-Q

netstat の Recv-Q の数値が何なのかを調べる

## とある td-agent サーバの netstat 

Recv-Q のサイズがやたら大きいですね。プロトコルは UDP です

```
[root@*** ~]# netstat -aun 
Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address               Foreign Address             State      
udp        0      0 0.0.0.0:651                 0.0.0.0:*                               
udp   229120      0 0.0.0.0:24224               0.0.0.0:*                               
udp        0      0 :::111                      :::*                                    
```

netstat は `/proc/net/udp` を読んでいるので、ここから netstatとカーネルの実装を辿れます

```
[root@*** ~]# cat /proc/net/udp
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode ref pointer drops             
  54: 00000000:007B 00000000:0000 07 00000000:00000000 00:00000000 00000000     0        0 12117 2 ffff88106989da80 0          
  70: 00000000:028B 00000000:0000 07 00000000:00000000 00:00000000 00000000     0        0 11660 2 ffff88086aca83c0 0          
  91: 00000000:5EA0 00000000:0000 07 00000000:00037F00 00:00000000 00000000   494        0 13359 2 ffff88086aca8a40 0          
```

**Recv-Q** は **rx_queue** の数値を読んでる様子です

## カーネルから rx_queue を元に探す

grep でがんばる

### IPv4 + UDP の場合

**udp4_format_sock** で **sk_rmem_alloc_get** の数値を読んで出力しているのが /proc/net/udp なのだと分かる

```c
static void udp4_format_sock(struct sock *sp, struct seq_file *f,
		int bucket, int *len)
{
	struct inet_sock *inet = inet_sk(sp);
	__be32 dest = inet->daddr;
	__be32 src  = inet->rcv_saddr;
	__u16 destp	  = ntohs(inet->dport);
	__u16 srcp	  = ntohs(inet->sport);

	seq_printf(f, "%4d: %08X:%04X %08X:%04X"
		" %02X %08X:%08X %02X:%08lX %08X %5d %8d %lu %d %p %d%n",
		bucket, src, srcp, dest, destp, sp->sk_state,
		sk_wmem_alloc_get(sp),   /* これが tx_queue */
		sk_rmem_alloc_get(sp),   /* これが rx_queue */
		0, 0L, 0, sock_i_uid(sp), 0, sock_i_ino(sp),
		atomic_read(&sp->sk_refcnt), sp,
		atomic_read(&sp->sk_drops), len);
}

/* /proc/net/udp のヘッダを出力 */
int udp4_seq_show(struct seq_file *seq, void *v)
{
	if (v == SEQ_START_TOKEN)
		seq_printf(seq, "%-127s\n",
			   "  sl  local_address rem_address   st tx_queue "
			   "rx_queue tr tm->when retrnsmt   uid  timeout "
			   "inode ref pointer drops");
	else {
		struct udp_iter_state *state = seq->private;
		int len;

		udp4_format_sock(v, seq, state->bucket, &len);
		seq_printf(seq, "%*s\n", 127 - len, "");
	}
	return 0;
}
```

sk_rmem_alloc_get の中身は下記の通りで、 **sock->sk_rmem_alloc** である。単位は bytes なはず

```
/**
 * sk_rmem_alloc_get - returns read allocations
 * @sk: socket
 *
 * Returns sk_rmem_alloc
 */
static inline int sk_rmem_alloc_get(const struct sock *sk)
{
	return atomic_read(&sk->sk_rmem_alloc);
	
}
```

sk->sk_rmem_alloc が何なのか? 長いので別で調べます