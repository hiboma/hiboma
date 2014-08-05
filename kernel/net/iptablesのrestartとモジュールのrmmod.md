# iptables の restart とカーネルモジュールの rmmod

とある CentOS4

## IPTABLES_MODULES_UNLOAD

/etc/init.d/iptables の挙動を左右する環境変数で、 stop の際に参照されている
IPTABLES_MODULES_UNLOAD=yes の場合は モジュールを rmmod する (依存のモジュールも rmmod する)

```sh
stop() {
    # Do not stop if iptables module is not loaded.
    [ -e "$PROC_IPTABLES_NAMES" ] || return 1

    flush_n_delete
    set_policy ACCEPT

    if [ "x$IPTABLES_MODULES_UNLOAD" = "xyes" ]; then
        echo -n $"Unloading $IPTABLES modules: "
        ret=0
        rmmod_r ${IPV}_tables
        let ret+=$?;
        rmmod_r ${IPV}_conntrack
        let ret+=$?;
        [ $ret -eq 0 ] && success || failure
        echo
    fi

    rm -f $VAR_SUBSYS_IPTABLES
    return $ret
}
```

rmmod する前に flush_n_delete で ルールを消しまくるらしい

```sh
flush_n_delete() {
    # Flush firewall rules and delete chains.
    [ -e "$PROC_IPTABLES_NAMES" ] || return 1

    # Check if firewall is configured (has tables)
    tables=`cat $PROC_IPTABLES_NAMES 2>/dev/null`
    [ -z "$tables" ] && return 1

    echo -n $"Flushing firewall rules: "
    ret=0
    # For all tables
    for i in $tables; do
        # Flush firewall rules.
        $IPTABLES -t $i -F;
        let ret+=$?;

        # Delete firewall chains.
        $IPTABLES -t $i -X;
        let ret+=$?;

        # Set counter to zero.
        $IPTABLES -t $i -Z;
        let ret+=$?;
    done

    [ $ret -eq 0 ] && success || failure
    echo
    return $ret
}
```

flush_n_delete した後に ip_tables, ip_filters を rmmod する。 ここで依存するモジュールも rmmod される

## rmmod されるモジュール群

依存して rmmod されるモジュールは /proc/modules で確認できる

```
[vagrant@users001 ~]$ cat /proc/modules  | grep ip_
ip_conntrack_ftp 76529 0 - Live 0xf0a64000
ip_conntrack 45829 2 ip_conntrack_ftp,ipt_state, Live 0xf0973000
ip_tables 22337 4 ipt_LOG,ipt_REJECT,ipt_state,iptable_filter, Live 0xf0933000
```

検証している VM では下記のモジュールが読み込まれていた

 * ip_conntrack
   * ip_conntrack_ftp
 * ip_tables
   * ipt_LOG
   * ipt_REJECT
   * ipt_state
   * iptable_filter

これらカーネルモジュールの unload 時の挙動を見て行く   

## ip_conntrack の __exit

```c
static void __exit fini(void)
{
	ipt_unregister_match(&conntrack_match);
}
```

```c
void
ipt_unregister_match(struct ipt_match *match)
{
	down(&ipt_mutex);
	LIST_DELETE(&ipt_match, match);
	up(&ipt_mutex);
}
```

ipt_match のリストを消すだけ

## ipt_ables

```c
static void __exit fini(void)
{
	nf_unregister_sockopt(&ipt_sockopts);
#ifdef CONFIG_PROC_FS
	{
	int i;
	for (i = 0; ipt_proc_entry[i].name; i++)
		proc_net_remove(ipt_proc_entry[i].name);
	}
#endif
}
```

nf_sockopt_ops_wrapper を消して回っているが何????

```c
void nf_unregister_sockopt(struct nf_sockopt_ops *reg)
{
	struct nf_sockopt_ops_wrapper *wrapper;
	struct list_head *i;

	/* No point being interruptible: we're probably in cleanup_module() */
	down(&nf_sockopt_mutex);
	list_for_each(i, &nf_sockopts) {
		wrapper = (struct nf_sockopt_ops_wrapper *)i;
		if (wrapper->ops == reg) {
			list_del(&wrapper->list);
			kfree(wrapper);
			goto out;
		}
	}
 out:
	up(&nf_sockopt_mutex);
}
```

## ipt_LOG


```c
static void __exit fini(void)
{
	if (nflog)
		nf_log_unregister(PF_INET, &ipt_logfn);
	ipt_unregister_target(&ipt_log_reg);
}
```

ログ用の関数ポインタを NULL で上書きしていってる

```c
void nf_log_unregister(int pf, nf_logfn *logfn)
{
	spin_lock(&nf_log_lock);
	if (nf_logging[pf] == logfn)
		nf_logging[pf] = NULL;
	spin_unlock(&nf_log_lock);

	/* Give time to concurrent readers. */
	synchronize_net();
}		
```

ipt_target のリストを削除する

```c
void
ipt_unregister_target(struct ipt_target *target)
{
	down(&ipt_mutex);
	LIST_DELETE(&ipt_target, target);
	up(&ipt_mutex);
}
```

## ipt_REJECT


```c
static void __exit fini(void)
{
	ipt_unregister_target(&ipt_reject_reg);
}
```

```c
void
ipt_unregister_target(struct ipt_target *target)
{
	down(&ipt_mutex);
	LIST_DELETE(&ipt_target, target);
	up(&ipt_mutex);
}
```


## ipt_state

```c
static void __exit fini(void)
{
	ipt_unregister_match(&state_match);
}
```

```c
void
ipt_unregister_match(struct ipt_match *match)
{
	down(&ipt_mutex);
	LIST_DELETE(&ipt_match, match);
	up(&ipt_mutex);
}
```

## iptables_filter

```c
static void __exit fini(void)
{
	unsigned int i;

	for (i = 0; i < sizeof(ipt_ops)/sizeof(struct nf_hook_ops); i++)
		nf_unregister_hook(&ipt_ops[i]);

	ipt_unregister_table(&packet_filter);
}
```

```c
void nf_unregister_hook(struct nf_hook_ops *reg)
{
	spin_lock_bh(&nf_hook_lock);
	list_del_rcu(&reg->list);
	spin_unlock_bh(&nf_hook_lock);

	synchronize_net();
}
```

```c
void ipt_unregister_table(struct ipt_table *table)
{
	down(&ipt_mutex);
	LIST_DELETE(&ipt_tables, table);
	up(&ipt_mutex);

	/* Decrease module usage counts and free resources */
	IPT_ENTRY_ITERATE(table->private->tblentries[0], table->private->size,
			  cleanup_entry, NULL);
	ipt_free_table_info(table->private);
}
```

cleanup_entry は各ターゲットの destroy を呼び出す。どんな風に destroy するかはターゲット次第だなー

```c
static inline int
cleanup_entry(struct ipt_entry *e, unsigned int *i)
{
	struct ipt_entry_target *t;

	if (i && (*i)-- == 0)
		return 1;

	/* Cleanup all matches */
	IPT_MATCH_ITERATE(e, cleanup_match, NULL);
	t = ipt_get_target(e);
	if (t->u.kernel.target->destroy)
		t->u.kernel.target->destroy(t->data,
					    t->u.target_size - sizeof(*t));
	module_put(t->u.kernel.target->me);
	return 0;
}
```

```c
static inline int
cleanup_match(struct ipt_entry_match *m, unsigned int *i)
{
	if (i && (*i)-- == 0)
		return 1;

	if (m->u.kernel.match->destroy)
		m->u.kernel.match->destroy(m->data,
					   m->u.match_size - sizeof(*m));
	module_put(m->u.kernel.match->me);
	return 0;
}
```

ipt_free_table_info は kfree, vfree を呼び出して回る。


```c
void ipt_free_table_info(struct ipt_table_info *info)
{
	int cpu;
	for_each_cpu(cpu) {
		if (info->size <= PAGE_SIZE)
			kfree(info->tblentries[cpu]);
		else
			vfree(info->tblentries[cpu]);
	}
	kfree(info);
}
```

```
ip_conntrack_core.c:	conntrack->ct_general.destroy = destroy_conntrack;
ip_conntrack_proto_sctp.c:	.destroy 	 = NULL, 
ipt_SAME.c:	.destroy	= same_destroy,
ipt_connlimit.c:	.destroy    = connlimit_mt_destroy,
ipt_iprange.c:	.destroy = NULL, 
ipt_recent.c:	.destroy	= ipt_recent_destroy,
ipt_sctp.c:	.destroy = NULL,
```

