## port 0番

```c
/* Obtain a reference to a local port for the given sock,
 * if snum is zero it means select any available local port.
 */
int inet_csk_get_port(struct sock *sk, unsigned short snum)
{
	struct inet_hashinfo *hashinfo = sk->sk_prot->h.hashinfo;
	struct inet_bind_hashbucket *head;
	struct hlist_node *node;
	struct inet_bind_bucket *tb;
	int ret, attempts = 5;
	struct net *net = sock_net(sk);
	int smallest_size = -1, smallest_rover;
	uid_t uid = sock_i_uid(sk);

	local_bh_disable();
	if (!snum) {
		int remaining, rover, low, high;

again:
        /* sysctl */
		inet_get_local_port_range(&low, &high);
		remaining = (high - low) + 1;
		smallest_rover = rover = net_random() % remaining + low;

		smallest_size = -1;
		do {
			if (inet_is_reserved_local_port(rover))
				goto next_nolock;
			head = &hashinfo->bhash[inet_bhashfn(net, rover,
					hashinfo->bhash_size)];
			spin_lock(&head->lock);
			inet_bind_bucket_for_each(tb, node, &head->chain)
				if (ib_net(tb) == net && tb->port == rover) {
					if (((tb->fastreuse > 0 &&
					      sk->sk_reuse &&
					      sk->sk_state != TCP_LISTEN) ||
					     (tb->fastreuseport > 0 &&
					      sk->sk_reuseport &&
					      tb->fastuid == uid)) &&
					    (tb->num_owners < smallest_size || smallest_size == -1)) {
						smallest_size = tb->num_owners;
						smallest_rover = rover;
						if (atomic_read(&hashinfo->bsockets) > (high - low) + 1 &&
						    !inet_csk(sk)->icsk_af_ops->bind_conflict(sk, tb)) {
							snum = smallest_rover;
							goto tb_found;
						}
					}
					if (!inet_csk(sk)->icsk_af_ops->bind_conflict(sk, tb)) {
						snum = rover;
						goto tb_found;
					}
					goto next;
				}
			break;
		next:
			spin_unlock(&head->lock);
		next_nolock:
			if (++rover > high)
				rover = low;
		} while (--remaining > 0);

		/* Exhausted local port range during search?  It is not
		 * possible for us to be holding one of the bind hash
		 * locks if this test triggers, because if 'remaining'
		 * drops to zero, we broke out of the do/while loop at
		 * the top level, not from the 'break;' statement.
		 */
		ret = 1;
		if (remaining <= 0) {
			if (smallest_size != -1) {
				snum = smallest_rover;
				goto have_snum;
			}
			goto fail;
		}
		/* OK, here is the one we will use.  HEAD is
		 * non-NULL and we hold it's mutex.
		 */
		snum = rover;
	} else {
have_snum:
		head = &hashinfo->bhash[inet_bhashfn(net, snum,
				hashinfo->bhash_size)];
		spin_lock(&head->lock);
		inet_bind_bucket_for_each(tb, node, &head->chain)
			if (ib_net(tb) == net && tb->port == snum)
				goto tb_found;
	}
	tb = NULL;
	goto tb_not_found;
tb_found:
	if (!hlist_empty(&tb->owners)) {
		if (((tb->fastreuse > 0 &&
		      sk->sk_reuse && sk->sk_state != TCP_LISTEN) ||
		     (tb->fastreuseport > 0 &&
		      sk->sk_reuseport && tb->fastuid == uid)) &&
		    smallest_size == -1) {
			goto success;
		} else {
			ret = 1;
			if (inet_csk_bind_conflict_relax(sk, tb)) {
				if (((sk->sk_reuse && sk->sk_state != TCP_LISTEN) ||
				     (sk->sk_reuseport && tb->fastuid == uid)) &&
				    smallest_size != -1 && --attempts >= 0) {
					spin_unlock(&head->lock);
					goto again;
				}
				goto fail_unlock;
			}
		}
	}
tb_not_found:
	ret = 1;
	if (!tb && (tb = inet_bind_bucket_create(hashinfo->bind_bucket_cachep,
					net, head, snum)) == NULL)
		goto fail_unlock;
	if (hlist_empty(&tb->owners)) {
		if (sk->sk_reuse && sk->sk_state != TCP_LISTEN)
			tb->fastreuse = 1;
		else
			tb->fastreuse = 0;
		if (sk->sk_reuseport) {
			tb->fastreuseport = 1;
			tb->fastuid = uid;
		} else {
			tb->fastreuseport = 0;
			tb->fastuid = 0;
		}
	} else {
		if (tb->fastreuse &&
		    (!sk->sk_reuse || sk->sk_state == TCP_LISTEN))
			tb->fastreuse = 0;
		if (tb->fastreuseport &&
		    (!sk->sk_reuseport || tb->fastuid != uid)) {
			tb->fastreuseport = 0;
			tb->fastuid = 0;
		}
	}
success:
	if (!inet_csk(sk)->icsk_bind_hash)
		inet_bind_hash(sk, tb, snum);
	WARN_ON(inet_csk(sk)->icsk_bind_hash != tb);
	ret = 0;

fail_unlock:
	spin_unlock(&head->lock);
fail:
	local_bh_enable();
	return ret;
}

EXPORT_SYMBOL_GPL(inet_csk_get_port);
```