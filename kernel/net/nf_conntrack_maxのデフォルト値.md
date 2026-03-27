# nf_conntrack_max のデフォルト値

どうやって決定されてるのか? コードを読めば分かる!!!

## SEE ALSO

 * http://tsuchinoko.dmmlabs.com/?p=1016

## 初期値を決めるコード

**nf_conntrack_init_init_net** で初期化される。

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

#### 初期値生成のロジック

**nf_conntrack_max** のサイズを決める式は下記の通り

```
nf_conntrack_max = 係数(4 or 8) * ハッシュテーブルのサイズ
```

#### 係数とハッシュテーブルのサイズは可変

係数とハッシュテーブルのサイズは (= **nf_conntrack_htable_size** ) は下記のロジックで決める

 * カーネルモジュールのロード時のパラメータで指定された場合
   * 係数が 8 になる
   * `sudo modprobe nf_conntrack hashsize=100000` みたいにして指定できる
 * カーネルモジュールのパラメータ指定がない場合は、RAM のサイズを元に決定する
   * 1GB以上だと 16384 に固定
   * 係数が 4 になる

#### まとめ

ということで nf_conntrack_max のデフォルト値は

 1. ハッシュテーブルのサイズは RAM が 1GB 以上 で ***16384***
 1. 係数は ***4***
 1. ハッシュテーブのサイズと係数 の値を乗算
   * 16384 * 4 => ***65536***
 1. 65536 が `nf_conntrack_max` のデフォルト値になる

と導き出せる。ややこしいので、コード読んで理解してください

#### その他

なお、ツチノコブログで 1/8 で計算をしているのは、 modprobe 等で ***nf_conntrack hashsize*** を指定した場合は 係数(max_factor) が 8 になるからである

> ちなみにnf_conntrack_maxの値を200000にする場合は
> hashsizeで8分の1の値(25000)を設定しておけば20万となります。

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

