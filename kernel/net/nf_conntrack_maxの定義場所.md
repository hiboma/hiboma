
netfilter/core.c

```c
struct ctl_path nf_net_netfilter_sysctl_path[] = {

        /* /proc/sys/net/ かな? */
        { .procname = "net", .ctl_name = CTL_NET, },

        /* /proc/sys/net/netfilter かな? */
        { .procname = "netfilter", .ctl_name = NET_NETFILTER, },
        { } 
};
```

netfilter/nf_conntrack_standalone.c

```c
/* /proc/sysctl/net/netfiter/nf_conntrack_max */
static ctl_table nf_ct_sysctl_table[] = { 
        {   
                .ctl_name       = NET_NF_CONNTRACK_MAX,
                .procname       = "nf_conntrack_max",
                .data           = &nf_conntrack_max,
                .maxlen         = sizeof(int),
                .mode           = 0644,
                .proc_handler   = proc_dointvec,
        },
        {
                 //...
        },
        
//...

/* /proc/sysctl/net/nf_conntrack_max のこと */
static ctl_table nf_ct_netfilter_table[] = { 
        {   
                .ctl_name       = NET_NF_CONNTRACK_MAX,
                .procname       = "nf_conntrack_max",
                .data           = &nf_conntrack_max,
                .maxlen         = sizeof(int),
                .mode           = 0644,
                .proc_handler   = proc_dointvec,
        },  
        { .ctl_name = 0 } 
};
```

```c
static struct ctl_path nf_ct_path[] = {
	{ .procname = "net", .ctl_name = CTL_NET, },
	{ }
};

static int nf_conntrack_standalone_init_sysctl(struct net *net)
{
	struct ctl_table *table;

    /* /proc/sysctl/net/ が生える */
	if (net_eq(net, &init_net)) {
		nf_ct_netfilter_header =
		       register_sysctl_paths(nf_ct_path, nf_ct_netfilter_table);
		if (!nf_ct_netfilter_header)
			goto out;
	}

	table = kmemdup(nf_ct_sysctl_table, sizeof(nf_ct_sysctl_table),
			GFP_KERNEL);
	if (!table)
		goto out_kmemdup;

	table[1].data = &net->ct.count;
	table[2].data = &net->ct.htable_size;
	table[3].data = &net->ct.sysctl_checksum;
	table[4].data = &net->ct.sysctl_log_invalid;

    /* /proc/sysctl/net/netfilter が生える */    
	net->ct.sysctl_header = register_net_sysctl_table(net,
					nf_net_netfilter_sysctl_path, table);
	if (!net->ct.sysctl_header)
		goto out_unregister_netfilter;

	return 0;

```