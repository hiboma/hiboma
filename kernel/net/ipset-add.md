# ipset add <name> <entry>

## USAGE

```
# type は hash:net 
$ sudo ipset add blacklist 192.168.69.0/24
```

## netlink で ip_set_add を呼ぶ

ip_set_add の中で、エントリ?を足す ip_set を探す

 * ip_set を見つけたら ip_set_type_variant? の .kadt でエントリを追加するa

```c
int
ip_set_add(ip_set_id_t index, const struct sk_buff *skb,
	   u8 family, u8 dim, u8 flags)
{
	struct ip_set *set = ip_set_list[index];
	int ret;

	BUG_ON(set == NULL);
	pr_debug("set %s, index %u\n", set->name, index);

	if (dim < set->type->dimension ||
	    !(family == set->family || set->family == AF_UNSPEC))
		return 0;

	write_lock_bh(&set->lock);
	ret = set->variant->kadt(set, skb, IPSET_ADD, family, dim, flags);
	write_unlock_bh(&set->lock);

	return ret;
}
EXPORT_SYMBOL_GPL(ip_set_add);
```

## INET + hash:net の kadt

 * **kadt = kernelspace add/del/test**
 * **uadt = userspace add/del/test**

```c
static intq
hash_net4_kadt(struct ip_set *set, const struct sk_buff *skb,
	       enum ipset_adt adt, u8 pf, u8 dim, u8 flags)
{
	const struct ip_set_hash *h = set->data;
	ipset_adtfn adtfn = set->variant->adt[adt];
	struct hash_net4_elem data = {
		.cidr = h->nets[0].cidr ? h->nets[0].cidr : HOST_MASK
	};

	if (data.cidr == 0)
		return -EINVAL;
	if (adt == IPSET_TEST)
		data.cidr = HOST_MASK;

	ip4addrptr(skb, flags & IPSET_DIM_ONE_SRC, &data.ip);
	data.ip &= ip_set_netmask(data.cidr);

	return adtfn(set, &data, h->timeout, flags);
}
```

 * ip_set_type と ip_set_type_variant の関係がよう分からん 
 * hash:net の adtfn の実装が見つからんなー