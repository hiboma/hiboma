# iptables REJECT

## sample

```
iptables -A FORWARD -p TCP --dport 22 -j REJECT --reject-with tcp-reset
```

## ソース

_net/ipv4/netfilter/ipt_REJECT.c_ に実装がある。何となく意味を類推して読めるレベル。ターゲットがどのようにして呼び出されるかは複雑そうだけど、ターゲット個別に見ると処理はシンプル (...?)

ところでよく対比の対象となる DROPターゲットの ipt_DROP.c は無い。 ( NF_DROP を辿るのがよさそ)

## reject_tg_reg

 * **struct xt_target** が iptables のターゲット ?
 * reject_tg_reg として扱われている

```c
static struct xt_target reject_tg_reg __read_mostly = {
	.name		= "REJECT",
	.family		= NFPROTO_IPV4,
    /* ターゲットにマッチした際の処理 */
	.target		= reject_tg,

	.targetsize	= sizeof(struct ipt_reject_info),

    /* 有効なテーブル */
	.table		= "filter",

    /* 有効なフックの種類か? /
	.hooks		= (1 << NF_INET_LOCAL_IN) | (1 << NF_INET_FORWARD) |
			  (1 << NF_INET_LOCAL_OUT),

    /* エントリ追加時のバリデーション */
	.checkentry	= reject_tg_check,
	.me		= THIS_MODULE,
};

static int __init reject_tg_init(void)
{
	return xt_register_target(&reject_tg_reg);
}

static void __exit reject_tg_exit(void)
{
	xt_unregister_target(&reject_tg_reg);
}

module_init(reject_tg_init);
module_exit(reject_tg_exit);
```

struct ipt_reject_info とその中身.  **--reject-with** をどれにするかしか保持していない

```c
#ifndef _IPT_REJECT_H
#define _IPT_REJECT_H

enum ipt_reject_with {
	IPT_ICMP_NET_UNREACHABLE,
	IPT_ICMP_HOST_UNREACHABLE,
	IPT_ICMP_PROT_UNREACHABLE,
	IPT_ICMP_PORT_UNREACHABLE,
	IPT_ICMP_ECHOREPLY,
	IPT_ICMP_NET_PROHIBITED,
	IPT_ICMP_HOST_PROHIBITED,
	IPT_TCP_RESET,
	IPT_ICMP_ADMIN_PROHIBITED
};

struct ipt_reject_info {
	enum ipt_reject_with with;      /* reject type */
};

#endif /*_IPT_REJECT_H*/
```

## --reject-with

 * icmp-net-unreachable,
 * icmp-host-unreachable
 * icmp-proto-unreachable 
 * icmp-port-unreachable
 * icmp-net-prohibited
 * icmp-host-prohibited
 * tcp-reset
 * echo-reply

**--reject-with** によって下記の通りに応答を返す分岐が実装されているが、 reject_tg を見ると案外分かりやすい。それぞれの詳細は ICMP のプロトコル仕様と TCP RST を追うのがよいかな

```c
static unsigned int
reject_tg(struct sk_buff *skb, const struct xt_target_param *par)
{
	const struct ipt_reject_info *reject = par->targinfo;

	/* WARNING: This code causes reentry within iptables.
	   This means that the iptables jump stack is now crap.  We
	   must return an absolute verdict. --RR */
	switch (reject->with) {
	case IPT_ICMP_NET_UNREACHABLE:
		send_unreach(skb, ICMP_NET_UNREACH);
		break;
	case IPT_ICMP_HOST_UNREACHABLE:
		send_unreach(skb, ICMP_HOST_UNREACH);
		break;
	case IPT_ICMP_PROT_UNREACHABLE:
		send_unreach(skb, ICMP_PROT_UNREACH);
		break;
	case IPT_ICMP_PORT_UNREACHABLE:
		send_unreach(skb, ICMP_PORT_UNREACH);
		break;
	case IPT_ICMP_NET_PROHIBITED:
		send_unreach(skb, ICMP_NET_ANO);
		break;
	case IPT_ICMP_HOST_PROHIBITED:
		send_unreach(skb, ICMP_HOST_ANO);
		break;
	case IPT_ICMP_ADMIN_PROHIBITED:
		send_unreach(skb, ICMP_PKT_FILTERED);
		break;
	case IPT_TCP_RESET:
		send_reset(skb, par->hooknum);
	case IPT_ICMP_ECHOREPLY:
		/* Doesn't happen. */
		break;
	}

	return NF_DROP;
}
```

## .checkentry is なに?

ルール(エントリ?)追加時のバリデーションなのかな?

```c
static bool reject_tg_check(const struct xt_tgchk_param *par)
{
	const struct ipt_reject_info *rejinfo = par->targinfo;
	const struct ipt_entry *e = par->entryinfo;

	if (rejinfo->with == IPT_ICMP_ECHOREPLY) {
		printk("ipt_REJECT: ECHOREPLY no longer supported.\n");
		return false;
	} else if (rejinfo->with == IPT_TCP_RESET) {
		/* Must specify that it's a TCP packet */
		if (e->ip.proto != IPPROTO_TCP
		    || (e->ip.invflags & XT_INV_PROTO)) {
			printk("ipt_REJECT: TCP_RESET invalid for non-tcp\n");
			return false;
		}
	}
	return true;
}
```