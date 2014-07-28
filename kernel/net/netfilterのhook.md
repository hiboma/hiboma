# netfilter のフック

```c
/*
 * 	Deliver IP Packets to the higher protocol layers.
 */
int ip_local_deliver(struct sk_buff *skb)
{
	/*
	 *	Reassemble IP fragments.
	 */

	if (ip_hdr(skb)->frag_off & htons(IP_MF | IP_OFFSET)) {
		if (ip_defrag(skb, IP_DEFRAG_LOCAL_DELIVER))
			return 0;
	}

	return NF_HOOK(PF_INET, NF_INET_LOCAL_IN, skb, skb->dev, NULL,
		       ip_local_deliver_finish);
}
```

NF_HOOK から -> NF_HOOK_THRESH -> nf_hook_thresh -> nf_hook_slow を呼び出す

## nf_hook_slow

```c
/* Returns 1 if okfn() needs to be executed by the caller,
 * -EPERM for NF_DROP, 0 otherwise. */
int nf_hook_slow(u_int8_t pf, unsigned int hook, struct sk_buff *skb,
		 struct net_device *indev,
		 struct net_device *outdev,
		 int (*okfn)(struct sk_buff *),
		 int hook_thresh)
{
	struct list_head *elem;
	unsigned int verdict; /* 判定、という意味 */
	int ret = 0;

	/* We may already have this, but read-locks nest anyway */
	rcu_read_lock();

	elem = &nf_hooks[pf][hook];
next_hook:
	verdict = nf_iterate(&nf_hooks[pf][hook], skb, hook, indev,
			     outdev, &elem, okfn, hook_thresh);
	if (verdict == NF_ACCEPT || verdict == NF_STOP) {
		ret = 1;
	} else if ((verdict & NF_VERDICT_MASK) == NF_DROP) {
		kfree_skb(skb);
		ret = NF_DROP_GETERR(verdict);
		if (ret == 0)
			ret = -EPERM;
	} else if ((verdict & NF_VERDICT_MASK) == NF_QUEUE) {
		ret = nf_queue(skb, elem, pf, hook, indev, outdev, okfn,
			       verdict >> NF_VERDICT_QBITS);
		if (ret < 0) {
			if (ret == -ECANCELED)
				goto next_hook;
			if (ret == -ESRCH &&
			   (verdict & NF_VERDICT_FLAG_QUEUE_BYPASS))
				goto next_hook;
			kfree_skb(skb);
		}
		ret = 0;
	}
	rcu_read_unlock();
	return ret;
}
EXPORT_SYMBOL(nf_hook_slow);
```