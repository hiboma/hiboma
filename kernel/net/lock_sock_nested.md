# unciorn が lock_sock_nested で TASK_UNINTERRUPTIBLE

時折発生する

```
[hiroya@***]~ % ps ax -ostate,uid,pid,cmd,wchan  | grep unicorn | grep ^D
D  1001 25199 unicorn worker[10] -c /u/ap lock_sock_nested
D  1001 25217 unicorn worker[16] -c /u/ap lock_sock_nested
D  1001 25220 unicorn worker[17] -c /u/ap lock_sock_nested
```

lock_sock_nested の実装は下記の通り (2.6.32***)

```c
void lock_sock_nested(struct sock *sk, int subclass)
{
	might_sleep();
	spin_lock_bh(&sk->sk_lock.slock);
	if (sk->sk_lock.owned)
		__lock_sock(sk);
	sk->sk_lock.owned = 1;
	spin_unlock(&sk->sk_lock.slock);
	/*
	 * The sk_lock has mutex_lock() semantics here:
	 */
	mutex_acquire(&sk->sk_lock.dep_map, subclass, 0, _RET_IP_);
	local_bh_enable();
}
EXPORT_SYMBOL(lock_sock_nested);
```

TCP のコードではインライン関数化されたものが呼び出されている

```
static inline void lock_sock(struct sock *sk)
{
	lock_sock_nested(sk, 0);
}
```

呼び出し箇所がいっぱいあるので、スタックをみないどこでロックが競合しているのかわからないな

```
lock_sock         480 net/ipv4/tcp.c   		lock_sock(sk);
lock_sock         624 net/ipv4/tcp.c   	lock_sock(sk);
lock_sock         668 net/ipv4/tcp.c   		lock_sock(sk);
lock_sock         891 net/ipv4/tcp.c   	lock_sock(sk);
lock_sock         934 net/ipv4/tcp.c   	lock_sock(sk);
lock_sock        1400 net/ipv4/tcp.c   	lock_sock(sk);
lock_sock        1579 net/ipv4/tcp.c   			lock_sock(sk);
lock_sock        1878 net/ipv4/tcp.c   	lock_sock(sk);
lock_sock        2127 net/ipv4/tcp.c   		lock_sock(sk);
lock_sock        2139 net/ipv4/tcp.c   	lock_sock(sk);
lock_sock         117 net/ieee802154/raw.c 	lock_sock(sk);
lock_sock         175 net/ipv4/af_inet.c 	lock_sock(sk);
lock_sock         197 net/ipv4/af_inet.c 	lock_sock(sk);
lock_sock         497 net/ipv4/af_inet.c 	lock_sock(sk);
lock_sock         559 net/ipv4/af_inet.c 		lock_sock(sk);
lock_sock         579 net/ipv4/af_inet.c 	lock_sock(sk);
lock_sock         668 net/ipv4/af_inet.c 	lock_sock(sk2);
lock_sock         778 net/ipv4/af_inet.c 	lock_sock(sk);
```