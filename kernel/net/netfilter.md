# netfilter

## フックの定義

```
  [INPUT]--->[1]--->[ROUTE]--->[3]--->[4]--->[OUTPUT]
                       |            ^
                       |            |
                       |         [ROUTE]
                       v            |
                      [2]          [5]
                       |            ^
                       |            |
                       v            |
                    [INPUT*]    [OUTPUT*]
[1]  NF_IP_PRE_ROUTING
[2]  NF_IP_LOCAL_IN
[3]  NF_IP_FORWARD
[4]  NF_IP_POST_ROUTING
[5]  NF_IP_LOCAL_OUT
[*]  Network Stack       
```

quote from http://www.linuxjournal.com/node/7184/print

... 上記は iptables 古い定義で、 NF_INET_*** な prefix に変わっている

```c
enum nf_inet_hooks {
	NF_INET_PRE_ROUTING,
	NF_INET_LOCAL_IN,
	NF_INET_FORWARD,
	NF_INET_LOCAL_OUT,
	NF_INET_POST_ROUTING,
	NF_INET_NUMHOOKS
};
```

#### NF_HOOK + NF_INET_PRE_ROUTING が挿入されている場所

```c
/*
 * 	Main IP Receive routine.
 */
int ip_rcv(struct sk_buff *skb, struct net_device *dev, struct packet_type *pt, struct net_device *orig_dev)
{
	struct iphdr *iph;
	u32 len;

	/* When the interface is in promisc. mode, drop all the crap
	 * that it receives, do not try to analyse it.
	 */
	if (skb->pkt_type == PACKET_OTHERHOST)
		goto drop;


	IP_UPD_PO_STATS_BH(dev_net(dev), IPSTATS_MIB_IN, skb->len);

	if ((skb = skb_share_check(skb, GFP_ATOMIC)) == NULL) {
		IP_INC_STATS_BH(dev_net(dev), IPSTATS_MIB_INDISCARDS);
		goto out;
	}

	if (!pskb_may_pull(skb, sizeof(struct iphdr)))
		goto inhdr_error;

	iph = ip_hdr(skb);

	/*
	 *	RFC1122: 3.2.1.2 MUST silently discard any IP frame that fails the checksum.
	 *
	 *	Is the datagram acceptable?
	 *
	 *	1.	Length at least the size of an ip header
	 *	2.	Version of 4
	 *	3.	Checksums correctly. [Speed optimisation for later, skip loopback checksums]
	 *	4.	Doesn't have a bogus length
	 */

	if (iph->ihl < 5 || iph->version != 4)
		goto inhdr_error;

	if (!pskb_may_pull(skb, iph->ihl*4))
		goto inhdr_error;

	iph = ip_hdr(skb);

	if (unlikely(ip_fast_csum((u8 *)iph, iph->ihl)))
		goto inhdr_error;

	len = ntohs(iph->tot_len);
	if (skb->len < len) {
		IP_INC_STATS_BH(dev_net(dev), IPSTATS_MIB_INTRUNCATEDPKTS);
		goto drop;
	} else if (len < (iph->ihl*4))
		goto inhdr_error;

	/* Our transport medium may have padded the buffer out. Now we know it
	 * is IP we can trim to the true length of the frame.
	 * Note this now means skb->len holds ntohs(iph->tot_len).
	 */
	if (pskb_trim_rcsum(skb, len)) {
		IP_INC_STATS_BH(dev_net(dev), IPSTATS_MIB_INDISCARDS);
		goto drop;
	}

	/* Remove any debris in the socket control block */
	memset(IPCB(skb), 0, sizeof(struct inet_skb_parm));

	/* Must drop socket now because of tproxy. */
	skb_orphan(skb);

    /* ここだよー */
	return NF_HOOK(PF_INET, NF_INET_PRE_ROUTING, skb, dev, NULL,
		       ip_rcv_finish);

inhdr_error:
	IP_INC_STATS_BH(dev_net(dev), IPSTATS_MIB_INHDRERRORS);
drop:
	kfree_skb(skb);
out:
	return NET_RX_DROP;
}
```

#### -A INPUT*** のフックが挿入されている箇所

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

    /* ここだよー */
	return NF_HOOK(PF_INET, NF_INET_LOCAL_IN, skb, skb->dev, NULL,
		       ip_local_deliver_finish);
}
```

## テーブルの登録

```
  --table	-t table	table to manipulate (default: `filter')
```

```c
$ sudo cat /proc/net/ip_tables_names 
filter
nat
```

### テーブルの定義は struct xt_table

```c
/* Furniture shopping... */
struct xt_table
{
	struct list_head list;

	/* What hooks you will enter on */
	unsigned int valid_hooks;

	/* Man behind the curtain... */
	struct xt_table_info *private;

	/* Set this to THIS_MODULE if you are a module, otherwise NULL */
	struct module *me;

	u_int8_t af;		/* address/protocol family */

	/* A unique name... */
	const char name[XT_TABLE_MAXNAMELEN];
};
```

デフォルトの **filter** テーブルが登録されるのを見て行きます

```c
static const struct xt_table packet_filter = {
	.name		= "filter", 
	.valid_hooks	= FILTER_VALID_HOOKS, // INPUT, FORWARD, OUTPUT のこと
	.me		= THIS_MODULE,
	.af		= NFPROTO_IPV4,
};
```

**filter** テーブルは packet_filter として ipt_register_table で登録される

```c
static int __net_init iptable_filter_net_init(struct net *net)
{
	/* Register table */
	net->ipv4.iptable_filter =
		ipt_register_table(net, &packet_filter, &initial_table.repl);
	if (IS_ERR(net->ipv4.iptable_filter))
		return PTR_ERR(net->ipv4.iptable_filter);
	return 0;
}
```

ipt_register_table の中で xt_register_table を呼んで tables を追加する

```c
struct xt_table *xt_register_table(struct net *net,
				   const struct xt_table *input_table,
				   struct xt_table_info *bootstrap,
				   struct xt_table_info *newinfo)
{
	int ret;
	struct xt_table_info *private;
	struct xt_table *t, *table;

	/* Don't add one object to multiple lists. */
	table = kmemdup(input_table, sizeof(struct xt_table), GFP_KERNEL);
	if (!table) {
		ret = -ENOMEM;
		goto out;
	}

	ret = mutex_lock_interruptible(&xt[table->af].mutex);
	if (ret != 0)
		goto out_free;

	/* Don't autoload: we'd eat our tail... */
	list_for_each_entry(t, &net->xt.tables[table->af], list) {
		if (strcmp(t->name, table->name) == 0) {
			ret = -EEXIST;
			goto unlock;
		}
	}

	/* Simplifies replace_table code. */
	table->private = bootstrap;

	if (!xt_replace_table(table, 0, newinfo, &ret))
		goto unlock;

	private = table->private;
	duprintf("table->private->number = %u\n", private->number);

	/* save number of initial entries */
	private->initial_entries = private->number;

	list_add(&table->list, &net->xt.tables[table->af]);
	mutex_unlock(&xt[table->af].mutex);
	return table;

 unlock:
	mutex_unlock(&xt[table->af].mutex);
out_free:
	kfree(table);
out:
	return ERR_PTR(ret);
}
EXPORT_SYMBOL_GPL(xt_register_table);
```

## ターゲットの登録

```
 --jump	-j target
				target for rule (may load target extension)
```

```sh
$ sudo cat /proc/net/ip_tables_targets 
REJECT
MASQUERADE
DNAT
SNAT
ERROR
```

### xt_register_target

 * struct xt_target を追加する
 * xt_target は address family ごとにリスト構造を取っている

```c
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

拡張として扱われる match

```
  --match	-m match
				extended match (may load extension)
```

```sh
$ sudo cat /proc/net/ip_tables_matches 
conntrack
conntrack
addrtype
addrtype
icmp
udplite
udp
tcp
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