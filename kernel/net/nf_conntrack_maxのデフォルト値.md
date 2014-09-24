# nf_conntrack_max のデフォルト値

どうやって決定されてるの?

## see also

 * http://tsuchinoko.dmmlabs.com/?p=1016

## nf_conntrack_max の初期値

nf_conntrack_init_init_net で初期化される。nf_conntrack_max のサイズは

```
nf_conntrack_max = 係数(4か8) * ハッシュテーブルのサイズ
```

で計算される。

 1. ハッシュテーブルのサイズを決める
   * RAM が 1GB 以上 だとデフォルトは 16384
 2. ハッシュテーブのサイズと max_factor の値を乗算して `nf_conntrack_max` を決定する
   * 16384 * 4 => 65536

```c
static int nf_conntrack_init_init_net(void)
{
	int max_factor = 8;
	int ret;

	/* Idea from tcp.c: use 1/16384 of memory.  On i386: 32MB
	 * machine has 512 buckets. >= 1GB machines have 16384 buckets. */
	if (!nf_conntrack_htable_size) {
		nf_conntrack_htable_size
			= (((totalram_pages << PAGE_SHIFT) / 16384)
			   / sizeof(struct hlist_head));
		if (totalram_pages > (1024 * 1024 * 1024 / PAGE_SIZE))
			nf_conntrack_htable_size = 16384;
		if (nf_conntrack_htable_size < 32)
			nf_conntrack_htable_size = 32;

		/* Use a max. factor of four by default to get the same max as
		 * with the old struct list_heads. When a table size is given
		 * we use the old value of 8 to avoid reducing the max.
		 * entries. */
		max_factor = 4;
	}
	nf_conntrack_max = max_factor * nf_conntrack_htable_size;

	printk("nf_conntrack version %s (%u buckets, %d max)\n",
	       NF_CONNTRACK_VERSION, nf_conntrack_htable_size,
	       nf_conntrack_max);
```

## nf_conntrack_max の sysctl インタフェース

```c
static ctl_table nf_ct_sysctl_table[] = {
	{
		.ctl_name	= NET_NF_CONNTRACK_MAX,
		.procname	= "nf_conntrack_max",
		.data		= &nf_conntrack_max,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec,
	},
```

