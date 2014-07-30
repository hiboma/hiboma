# ipset create

## USAGE

```sh
$ sudo ipset create blacklist hash:net
                       |          |
                        \          \
                          name      type
```

ip_set (集合) を新たに追加するコマンド

## ip_set の定義

```c
/* A generic IP set */
struct ip_set {
	/* The name of the set */
	char name[IPSET_MAXNAMELEN];
	/* Lock protecting the set data */
	rwlock_t lock;
	/* References to the set */
	u32 ref;
	/* The core set type */
	struct ip_set_type *type;
	/* The type variant doing the real job */
	const struct ip_set_type_variant *variant;
	/* The actual INET family of the set */
	u8 family;
	/* The type specific data */
	void *data;
};
```

ip_set_type によって細かい挙動を変える。 **hash:nset** の場合は下記の通りの定義

```c
static struct ip_set_type hash_net_type __read_mostly = {
	.name		= "hash:net",
	.protocol	= IPSET_PROTOCOL,
	.features	= IPSET_TYPE_IP,
	.dimension	= IPSET_DIM_ONE,
	.family		= AF_UNSPEC,
	.revision	= 0,
	.create		= hash_net_create,
	.create_policy	= {
		[IPSET_ATTR_HASHSIZE]	= { .type = NLA_U32 },
		[IPSET_ATTR_MAXELEM]	= { .type = NLA_U32 },
		[IPSET_ATTR_PROBES]	= { .type = NLA_U8 },
		[IPSET_ATTR_RESIZE]	= { .type = NLA_U8  },
		[IPSET_ATTR_TIMEOUT]	= { .type = NLA_U32 },
	},
	.adt_policy	= {
		[IPSET_ATTR_IP]		= { .type = NLA_NESTED },
		[IPSET_ATTR_CIDR]	= { .type = NLA_U8 },
		[IPSET_ATTR_TIMEOUT]	= { .type = NLA_U32 },
	},
	.me		= THIS_MODULE,
};
```

## ip_set_create

netlink ソケットで呼び出される

 * ip_set を kzalloc
 * ip_set_type を探す
 * ip_set_type の .create で、タイプ?に応じて初期化

ip_set, ip_set_type の初期化が目的で、何かを制御するのは `ipset add` 等でなされる

```c
static int
ip_set_create(struct sock *ctnl, struct sk_buff *skb,
	      const struct nlmsghdr *nlh,
	      const struct nlattr * const attr[])
{
	struct ip_set *set, *clash = NULL;
	ip_set_id_t index = IPSET_INVALID_ID;
	struct nlattr *tb[IPSET_ATTR_CREATE_MAX+1] = {};
	const char *name, *typename;
	u8 family, revision;
	u32 flags = flag_exist(nlh);
	int ret = 0;

	if (unlikely(protocol_failed(attr) ||
		     attr[IPSET_ATTR_SETNAME] == NULL ||
		     attr[IPSET_ATTR_TYPENAME] == NULL ||
		     attr[IPSET_ATTR_REVISION] == NULL ||
		     attr[IPSET_ATTR_FAMILY] == NULL ||
		     (attr[IPSET_ATTR_DATA] != NULL &&
		      !flag_nested(attr[IPSET_ATTR_DATA]))))
		return -IPSET_ERR_PROTOCOL;

	name = nla_data(attr[IPSET_ATTR_SETNAME]);
	typename = nla_data(attr[IPSET_ATTR_TYPENAME]);
	family = nla_get_u8(attr[IPSET_ATTR_FAMILY]);
	revision = nla_get_u8(attr[IPSET_ATTR_REVISION]);
	pr_debug("setname: %s, typename: %s, family: %s, revision: %u\n",
		 name, typename, family_name(family), revision);

	/*
	 * First, and without any locks, allocate and initialize
	 * a normal base set structure.
	 */
	set = kzalloc(sizeof(struct ip_set), GFP_KERNEL);
	if (!set)
		return -ENOMEM;
	rwlock_init(&set->lock);
	strlcpy(set->name, name, IPSET_MAXNAMELEN);
	set->family = family;

	/*
	 * Next, check that we know the type, and take
	 * a reference on the type, to make sure it stays available
	 * while constructing our new set.
	 *
	 * After referencing the type, we try to create the type
	 * specific part of the set without holding any locks.
	 */
	ret = find_set_type_get(typename, family, revision, &(set->type));
	if (ret)
		goto out;

	/*
	 * Without holding any locks, create private part.
	 */
	if (attr[IPSET_ATTR_DATA] &&
	    nla_parse_nested(tb, IPSET_ATTR_CREATE_MAX, attr[IPSET_ATTR_DATA],
			     set->type->create_policy)) {
	    	ret = -IPSET_ERR_PROTOCOL;
	    	goto put_out;
	}

	ret = set->type->create(set, tb, flags);
	if (ret != 0)
		goto put_out;

	/* BTW, ret==0 here. */

	/*
	 * Here, we have a valid, constructed set and we are protected
	 * by the nfnl mutex. Find the first free index in ip_set_list
	 * and check clashing.
	 */
	if ((ret = find_free_id(set->name, &index, &clash)) != 0) {
		/* If this is the same set and requested, ignore error */
		if (ret == -EEXIST &&
		    (flags & IPSET_FLAG_EXIST) &&
		    STREQ(set->type->name, clash->type->name) &&
		    set->type->family == clash->type->family &&
		    set->type->revision == clash->type->revision &&
		    set->variant->same_set(set, clash))
			ret = 0;
		goto cleanup;
	}

	/*
	 * Finally! Add our shiny new set to the list, and be done.
	 */
	pr_debug("create: '%s' created with index %u!\n", set->name, index);
	ip_set_list[index] = set;

	return ret;

cleanup:
	set->variant->destroy(set);
put_out:
	module_put(set->type->me);
out:
	kfree(set);
	return ret;
}
```