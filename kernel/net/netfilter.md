# netfilter

## ターゲットの登録

```
 --jump	-j target
				target for rule (may load target extension)
```

### xt_register_target

 * struct xt_target を追加する
 * xt_target は address family ごとにリスト構造を取っている

```
/* Registration hooks for targets. */
int
xt_register_target(struct xt_target *target)
{
	u_int8_t af = target->family;
	int ret;

	ret = mutex_lock_interruptible(&xt[af].mutex);
	if (ret != 0)
		return ret;
	list_add(&target->list, &xt[af].target);
	mutex_unlock(&xt[af].mutex);
	return ret;
}
EXPORT_SYMBOL(xt_register_target);
```

**REJECT** ターゲットの登録例は次の通り

```c
// net/ipv4/netfilter/ipt_REJECT.c

static struct xt_target reject_tg_reg __read_mostly = {
	.name		= "REJECT",
	.family		= NFPROTO_IPV4,
	.target		= reject_tg,
	.targetsize	= sizeof(struct ipt_reject_info),
	.table		= "filter",
	.hooks		= (1 << NF_INET_LOCAL_IN) | (1 << NF_INET_FORWARD) |
			  (1 << NF_INET_LOCAL_OUT),
	.checkentry	= reject_tg_check,
	.me		= THIS_MODULE,
};

static int __init reject_tg_init(void)
{
	return xt_register_target(&reject_tg_reg);
}
```

## match の登録

```
  --match	-m match
				extended match (may load extension)
```

#### xt_register_match

 * xt_match のリストを登録
 * xt_match はアドレスファミリごとに別れている

```c
int
xt_register_match(struct xt_match *match)
{
	u_int8_t af = match->family;
	int ret;

	ret = mutex_lock_interruptible(&xt[af].mutex);
	if (ret != 0)
		return ret;

	list_add(&match->list, &xt[af].match);
	mutex_unlock(&xt[af].mutex);

	return ret;
}
EXPORT_SYMBOL(xt_register_match);
```

**mac** マッチャー? の登録例と実装例

 * sk_buff から mac アドレスを取り出しての比較
   * skb_mac_header で mac アドレスを抜き出し
   * compare_ether_addr で一致するかどうか

```c
static bool mac_mt(const struct sk_buff *skb, const struct xt_match_param *par)
{
    const struct xt_mac_info *info = par->matchinfo;

    /* Is mac pointer valid? */
    return skb_mac_header(skb) >= skb->head &&
	   skb_mac_header(skb) + ETH_HLEN <= skb->data
	   /* If so, compare... */
	   && ((!compare_ether_addr(eth_hdr(skb)->h_source, info->srcaddr))
		^ info->invert);
}

static struct xt_match mac_mt_reg __read_mostly = {
	.name      = "mac",
	.revision  = 0,
	.family    = NFPROTO_UNSPEC,
	.match     = mac_mt,
	.matchsize = sizeof(struct xt_mac_info),
	.hooks     = (1 << NF_INET_PRE_ROUTING) | (1 << NF_INET_LOCAL_IN) |
	             (1 << NF_INET_FORWARD),
	.me        = THIS_MODULE,
};

static int __init mac_mt_init(void)
{
	return xt_register_match(&mac_mt_reg);
}
```

## フックの登録

 * nf_hook_ops がフックの実装
 * nf_hook_ops .list にふっくを繋げていく

```c
int nf_register_hook(struct nf_hook_ops *reg)
{
	struct nf_hook_ops *elem;
	int err;

	err = mutex_lock_interruptible(&nf_hook_mutex);
	if (err < 0)
		return err;
	list_for_each_entry(elem, &nf_hooks[reg->pf][reg->hooknum], list) {
        /* 優先度によってフックを登録 */
		if (reg->priority < elem->priority)
			break;
	}
    /* nf_hook_ops のリストでフックを繋げる */
	list_add_rcu(&reg->list, elem->list.prev);
	mutex_unlock(&nf_hook_mutex);
	return 0;
}
EXPORT_SYMBOL(nf_register_hook);
```

CentOS4 だと nf_register_hook でいろいろ登録しているけど、 CentOS6 だと少ない。API 変わってる?

```c
	ret = nf_register_hook(&ip_conntrack_defrag_ops);
	if (ret < 0) {
		printk("ip_conntrack: can't register pre-routing defrag hook.\n");
		goto cleanup_proc_stat;
	}
	ret = nf_register_hook(&ip_conntrack_defrag_local_out_ops);
	if (ret < 0) {
		printk("ip_conntrack: can't register local_out defrag hook.\n");
		goto cleanup_defragops;
	}
	ret = nf_register_hook(&ip_conntrack_in_ops);
	if (ret < 0) {
		printk("ip_conntrack: can't register pre-routing hook.\n");
		goto cleanup_defraglocalops;
	}
```

see also: http://www.gsx.co.jp/tts/activity/110707.html