# ipset

ユーザ空間とのやりとり (setの add, del, list ...) は AF_NETLINK を使っている

```c
static struct nfnetlink_subsystem ip_set_netlink_subsys __read_mostly = {
	.name		= "ip_set",
	.subsys_id	= NFNL_SUBSYS_IPSET,
	.cb_count	= IPSET_MSG_MAX,
	.cb		= ip_set_netlink_subsys_cb,
};
```

ip_set_netlink_subsys_cb で以下のコールバックが定義されるようだ

```c
static const struct nfnl_callback ip_set_netlink_subsys_cb[IPSET_MSG_MAX] = {
	[IPSET_CMD_NONE]	= {
		.call		= ip_set_none,
		.attr_count	= IPSET_ATTR_CMD_MAX,
	},
	[IPSET_CMD_CREATE]	= {
		.call		= ip_set_create,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_create_policy,
	},
	[IPSET_CMD_DESTROY]	= {
		.call		= ip_set_destroy,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_setname_policy,
	},
	[IPSET_CMD_FLUSH]	= {
		.call		= ip_set_flush,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_setname_policy,
	},
	[IPSET_CMD_RENAME]	= {
		.call		= ip_set_rename,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_setname2_policy,
	},
	[IPSET_CMD_SWAP]	= {
		.call		= ip_set_swap,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_setname2_policy,
	},
	[IPSET_CMD_LIST]	= {
		.call		= ip_set_dump,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_setname_policy,
	},
	[IPSET_CMD_SAVE]	= {
		.call		= ip_set_dump,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_setname_policy,
	},
	[IPSET_CMD_ADD]	= {
		.call		= ip_set_uadd,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_adt_policy,
	},
	[IPSET_CMD_DEL]	= {
		.call		= ip_set_udel,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_adt_policy,
	},
	[IPSET_CMD_TEST]	= {
		.call		= ip_set_utest,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_adt_policy,
	},
	[IPSET_CMD_HEADER]	= {
		.call		= ip_set_header,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_setname_policy,
	},
	[IPSET_CMD_TYPE]	= {
		.call		= ip_set_type,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_type_policy,
	},
	[IPSET_CMD_PROTOCOL]	= {
		.call		= ip_set_protocol,
		.attr_count	= IPSET_ATTR_CMD_MAX,
		.policy		= ip_set_protocol_policy,
	},
};
```
