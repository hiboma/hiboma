# netfilter のフック

nf_hook_ops ↓ が実行される仕組みを見て行きます

```c
static struct nf_hook_ops ipt_ops[] __read_mostly = {
	{
		.hook		= ipt_local_in_hook,
		.owner		= THIS_MODULE,
		.pf		= NFPROTO_IPV4,
		.hooknum	= NF_INET_LOCAL_IN,
		.priority	= NF_IP_PRI_FILTER,
	},
	{
		.hook		= ipt_hook,
		.owner		= THIS_MODULE,
		.pf		= NFPROTO_IPV4,
		.hooknum	= NF_INET_FORWARD,
		.priority	= NF_IP_PRI_FILTER,
	},
	{
		.hook		= ipt_local_out_hook,
		.owner		= THIS_MODULE,
		.pf		= NFPROTO_IPV4,
		.hooknum	= NF_INET_LOCAL_OUT,
		.priority	= NF_IP_PRI_FILTER,
	},
};
```

## INPUT = NF_INET_LOCAL_IN の場合

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

## nf_hook_slow とは?

nf_iterate でフックの処理を回す?

 * NF_ACCEPT, NF_STOP
 * NF_DROP
   * パケットを DROP するので、 kfree_skb(skb) している
 * NF_QUEUE
   * `-j QUEUE` ターゲットでユーザ空間に転送するやつ。複雑なので後で。

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

    /* NF_ACCEPT, NF_STOP */
	if (verdict == NF_ACCEPT || verdict == NF_STOP) {
		ret = 1;

    /* NF_DROP 
	} else if ((verdict & NF_VERDICT_MASK) == NF_DROP) {
		kfree_skb(skb);
		ret = NF_DROP_GETERR(verdict);
		if (ret == 0)
			ret = -EPERM;

    /* NF_QUEUE */
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

## nf_iterate とは?

 * nf_hook_ops をイテレートして hook() メソッドを呼び出す
 * hook() が NF_ACCEPT, NF_DROP, ... を返す
   * NF_REPEAT なら hook を繰り返し処理していく

```c
unsigned int nf_iterate(struct list_head *head,
			struct sk_buff *skb,
			unsigned int hook,
			const struct net_device *indev,
			const struct net_device *outdev,
			struct list_head **i,
			int (*okfn)(struct sk_buff *),
			int hook_thresh)
{
	unsigned int verdict;

	/*
	 * The caller must not block between calls to this
	 * function because of risk of continuing from deleted element.
	 */
	list_for_each_continue_rcu(*i, head) {
		struct nf_hook_ops *elem = (struct nf_hook_ops *)*i;

		if (hook_thresh > elem->priority)
			continue;

		/* Optimization: we don't need to hold module
		   reference here, since function can't sleep. --RR */
		verdict = elem->hook(hook, skb, indev, outdev, okfn);
		if (verdict != NF_ACCEPT) {
#ifdef CONFIG_NETFILTER_DEBUG
			if (unlikely((verdict & NF_VERDICT_MASK)
							> NF_MAX_VERDICT)) {
				NFDEBUG("Evil return from %p(%u).\n",
					elem->hook, hook);
				continue;
			}
#endif
			if (verdict != NF_REPEAT)
				return verdict;
			*i = (*i)->prev;
		}
	}
	return NF_ACCEPT;
}
```

> nf_hook_ops をイテレートして hook() メソッドを呼び出す

NF_INET_LOCAL_IN の場合は **ipt_local_in_hook** が .hook 実装になる

```c
static struct nf_hook_ops ipt_ops[] __read_mostly = {
	{
		.hook		= ipt_local_in_hook,
		.owner		= THIS_MODULE,
		.pf		= NFPROTO_IPV4,
		.hooknum	= NF_INET_LOCAL_IN,
		.priority	= NF_IP_PRI_FILTER,
	},
```

## ipt_local_in_hook の実装

```c
/* The work comes in here from netfilter.c. */
static unsigned int
ipt_local_in_hook(unsigned int hook,
		  struct sk_buff *skb,
		  const struct net_device *in,
		  const struct net_device *out,
		  int (*okfn)(struct sk_buff *))
{
	return ipt_do_table(skb, hook, in, out,
			    dev_net(in)->ipv4.iptable_filter);
}
```

ipt_do_table が肝。つえー

 * NF_INET_LOCAL_IN の場合はテーブルが ipv4.iptable_filter = filter になる
 * struct ipt_entry ( **ルール** ) をイテレートして ip_packet_match でマッチするエントリを探す
   * t->u.kernel.target->target でターゲットを評価
     * IPT_CONTINUE を返したら次のルール/ターゲットを探す

```c
/* Returns one of the generic firewall policies, like NF_ACCEPT. */
unsigned int
ipt_do_table(struct sk_buff *skb,
	     unsigned int hook,
	     const struct net_device *in,
	     const struct net_device *out,
	     struct xt_table *table)
{
#define tb_comefrom ((struct ipt_entry *)table_base)->comefrom

	static const char nulldevname[IFNAMSIZ] __attribute__((aligned(sizeof(long))));
	const struct iphdr *ip;
	bool hotdrop = false;
	/* Initializing verdict to NF_DROP keeps gcc happy. */
	unsigned int verdict = NF_DROP;
	const char *indev, *outdev;
	void *table_base;

    /* ルール */
	struct ipt_entry *e, *back;
	struct xt_table_info *private;
	struct xt_match_param mtpar;
	struct xt_target_param tgpar;

	/* Initialization */
	ip = ip_hdr(skb);
	indev = in ? in->name : nulldevname;
	outdev = out ? out->name : nulldevname;
	/* We handle fragments by dealing with the first fragment as
	 * if it was a normal packet.  All other fragments are treated
	 * normally, except that they will NEVER match rules that ask
	 * things we don't know, ie. tcp syn flag or ports).  If the
	 * rule is also a fragment-specific rule, non-fragments won't
	 * match it. */
	mtpar.fragoff = ntohs(ip->frag_off) & IP_OFFSET;
	mtpar.thoff   = ip_hdrlen(skb);

    /* NF_DROP 返すかどうか */
	mtpar.hotdrop = &hotdrop;
	mtpar.in      = tgpar.in  = in;
	mtpar.out     = tgpar.out = out;
	mtpar.family  = tgpar.family = NFPROTO_IPV4;
	mtpar.hooknum = tgpar.hooknum = hook;

	IP_NF_ASSERT(table->valid_hooks & (1 << hook));
	xt_info_rdlock_bh();
	private = table->private;
	table_base = private->entries[smp_processor_id()];

	e = get_entry(table_base, private->hook_entry[hook]);

	/* For return from builtin chain */
	back = get_entry(table_base, private->underflow[hook]);

	do {
        /* ターゲット */
		struct ipt_entry_target *t;

		IP_NF_ASSERT(e);
		IP_NF_ASSERT(back);

        /* ルールにマッチするかどうか? */
		if (!ip_packet_match(ip, indev, outdev,
		    &e->ip, mtpar.fragoff) ||
		    IPT_MATCH_ITERATE(e, do_match, skb, &mtpar) != 0) {
			e = ipt_next_entry(e);
			continue;
		}

		ADD_COUNTER(e->counters, ntohs(ip->tot_len), 1);

        /* ルールからターゲットを取り出す */
		t = ipt_get_target(e);
		IP_NF_ASSERT(t->u.kernel.target);

		/* Standard target? */
		if (!t->u.kernel.target->target) {
			int v;

			v = ((struct ipt_standard_target *)t)->verdict;
			if (v < 0) {
				/* Pop from stack? */
				if (v != IPT_RETURN) {
					verdict = (unsigned)(-v) - 1;
					break;
				}
				e = back;
				back = get_entry(table_base, back->comefrom);
				continue;
			}
			if (table_base + v != ipt_next_entry(e)
			    && !(e->ip.flags & IPT_F_GOTO)) {
				/* Save old back ptr in next entry */
				struct ipt_entry *next = ipt_next_entry(e);
				next->comefrom = (void *)back - table_base;
				/* set back pointer to next entry */
				back = next;
			}

			e = get_entry(table_base, v);
			continue;
		}

		/* Targets which reenter must return
		   abs. verdicts */
		tgpar.target   = t->u.kernel.target;
		tgpar.targinfo = t->data;

        /* ターゲットの評価と判定結果 */
        /* 例として REJECT ターゲットの場合は reject_tg を呼ぶ */
		verdict = t->u.kernel.target->target(skb, &tgpar);

		/* Target might have changed stuff. */
		ip = ip_hdr(skb);

        /* 次のルールを探す */
		if (verdict == IPT_CONTINUE)
			e = ipt_next_entry(e);
		else
			/* Verdict 判定終わり */
			break;
	} while (!hotdrop);
	xt_info_rdunlock_bh();

	if (hotdrop)
		return NF_DROP;
	else return verdict;
}
```