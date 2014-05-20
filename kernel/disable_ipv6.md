# disable IPv6

## TODO

ユーザランドから AF_INET6 を使うかはどうやって決定されるか?
 
## /etc/moroprobe.d で無効にする

/etc/modprobe.d/disable-ipv6.conf とか作って `options ipv6 disable` するとブート時に下記の dmesg が出る

```
IPv6: Loaded, but administratively disabled, reboot required to enable
```

**Loaded** とあるけど、カーネルモジュールの init が実行されてるだけで IPv6 機能は無効

```c
// net/ipv6/af_inet6.c
static int __init inet6_init(void)
{
	struct sk_buff *dummy_skb;
	struct list_head *r;
	int err = 0;

	BUILD_BUG_ON(sizeof(struct inet6_skb_parm) > sizeof(dummy_skb->cb));

	/* Register the socket-side information for inet6_create.  */
	for(r = &inetsw6[0]; r < &inetsw6[SOCK_MAX]; ++r)
		INIT_LIST_HEAD(r);

	if (disable_ipv6_mod) {
		printk(KERN_INFO
		       "IPv6: Loaded, but administratively disabled, "
		       "reboot required to enable\n");
		goto out;
	}

// ...    

out:
	return err;

// ...    
    
}
module_init(inet6_init);
```

## sysctl interface で無効にする

ブート後に無効にできる

```sh
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
```

#### 実装

sysctl の定義は次の通り

```c
		{
			.ctl_name	=	CTL_UNNUMBERED,
			.procname	=	"disable_ipv6",
			.data		=	&ipv6_devconf.disable_ipv6,
			.maxlen		=	sizeof(int),
			.mode		=	0644,
			.proc_handler	=	addrconf_sysctl_disable,
			.strategy	=	sysctl_intvec,
		},
```

 * addrconf_sysctl_disable がハンドラとして呼び出される
 * `sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1` で IPv6 のアドレスが消えるのもこれの作用?

addrconf_sysctl_disable から掘り下げていきます

```c
static
int addrconf_sysctl_disable(ctl_table *ctl, int write,
			    void __user *buffer, size_t *lenp, loff_t *ppos)
{
	int *valp = ctl->data;
	int val = *valp;
	loff_t pos = *ppos;
	int ret;

	ret = proc_dointvec(ctl, write, buffer, lenp, ppos);

	if (write)
        // ->
		ret = addrconf_disable_ipv6(ctl, valp, val);
	if (ret)
		*ppos = pos;
	return ret;
}
```

```c
static int addrconf_disable_ipv6(struct ctl_table *table, int *p, int old)
{
	struct net *net;

	net = (struct net *)table->extra2;

	if (p == &net->ipv6.devconf_dflt->disable_ipv6)
		return 0;

	if (!rtnl_trylock()) {
		/* Restore the original values before restarting */
		*p = old;
		return restart_syscall();
	}

	if (p == &net->ipv6.devconf_all->disable_ipv6) {
		__s32 newf = net->ipv6.devconf_all->disable_ipv6;
		net->ipv6.devconf_dflt->disable_ipv6 = newf;
        // ->
		addrconf_disable_change(net, newf);
	} else if ((!*p) ^ (!old))
        // ->
		dev_disable_change((struct inet6_dev *)table->extra1);

	rtnl_unlock();
	return 0;
}
```

 * デバイスをイテレートして dev_disable_change で IPv6 を止めてる
 * net_device から inet6_dev を取り出せるらしい

```c
static void addrconf_disable_change(struct net *net, __s32 newf)
{
	struct net_device *dev;
	struct inet6_dev *idev;

	read_lock(&dev_base_lock);
    /* イテレート */
	for_each_netdev(net, dev) {
		rcu_read_lock();
		idev = __in6_dev_get(dev);
		if (idev) {
			int changed = (!idev->cnf.disable_ipv6) ^ (!newf);
			idev->cnf.disable_ipv6 = newf;
			if (changed)
                // ->
				dev_disable_change(idev);
		}
		rcu_read_unlock();
	}
	read_unlock(&dev_base_lock);
}
```

 * inet6_dev インタフェースの DOWN/UP を切り替えるメソッド
 * addrconf_notify(NETDEV_DOWN) で IPv6 の停止になる様子

```c
static void dev_disable_change(struct inet6_dev *idev)
{
	if (!idev || !idev->dev)
		return;

	if (idev->cnf.disable_ipv6)
        // ->
		addrconf_notify(NULL, NETDEV_DOWN, idev->dev);
	else
		addrconf_notify(NULL, NETDEV_UP, idev->dev);
}
```

 * NETDEV_DOWN と NETDEV_UNREGISTER の違いは?

```c
static int addrconf_notify(struct notifier_block *this, unsigned long event,
			   void * data)
{
	struct net_device *dev = (struct net_device *) data;

	case NETDEV_DOWN:
	case NETDEV_UNREGISTER:
		/*
		 *	Remove all addresses from this interface.
		 */
        // ->
		addrconf_ifdown(dev, event != NETDEV_DOWN);
		break;
```

 * コメントにステップが記載されているので参考にして読む

```c
/* Step 1: remove reference to ipv6 device from parent device. Do not dev_put! */
/* Step 1.5: remove snmp6 entry */
/* Step 2: clear hash table */
/* Step 3: clear flags for stateless addrconf */
/* Step 4: clear address list */
/* clear tempaddr list */
/* Step 5: Discard multicast list */
/* Shot the device (if unregistered) */
```

 * rt6_ifdown
   * IPv6 の routing 情報? を down
 * neigh_ifdown
   * ?

```c
static int addrconf_ifdown(struct net_device *dev, int how)
{
	struct inet6_dev *idev;
	struct inet6_ifaddr *ifa, **bifa;
	struct net *net = dev_net(dev);
	int state;
	int i;

	ASSERT_RTNL();

	rt6_ifdown(net, dev);
	neigh_ifdown(&nd_tbl, dev);

	idev = __in6_dev_get(dev);
	if (idev == NULL)
		return -ENODEV;

	/* Step 1: remove reference to ipv6 device from parent device.
		   Do not dev_put!
	 */
	if (how) {
		idev->dead = 1;

		/* protected by rtnl_lock */
		rcu_assign_pointer(dev->ip6_ptr, NULL);

		/* Step 1.5: remove snmp6 entry */
		snmp6_unregister_dev(idev);

	}

	/* Step 2: clear hash table */
	for (i=0; i<IN6_ADDR_HSIZE; i++) {
		bifa = &inet6_addr_lst[i];

		write_lock_bh(&addrconf_hash_lock);
		while ((ifa = *bifa) != NULL) {
			if (ifa->idev == idev) {
				*bifa = ifa->lst_next;
				ifa->lst_next = NULL;
				addrconf_del_timer(ifa);
				in6_ifa_put(ifa);
				continue;
			}
			bifa = &ifa->lst_next;
		}
		write_unlock_bh(&addrconf_hash_lock);
	}

	write_lock_bh(&idev->lock);

	/* Step 3: clear flags for stateless addrconf */
	if (!how)
		idev->if_flags &= ~(IF_RS_SENT|IF_RA_RCVD|IF_READY);

	/* Step 4: clear address list */
#ifdef CONFIG_IPV6_PRIVACY
	if (how && del_timer(&idev->regen_timer))
		in6_dev_put(idev);

	/* clear tempaddr list */
	while ((ifa = idev->tempaddr_list) != NULL) {
		idev->tempaddr_list = ifa->tmp_next;
		ifa->tmp_next = NULL;
		write_unlock_bh(&idev->lock);
		spin_lock_bh(&ifa->lock);

		if (ifa->ifpub) {
			in6_ifa_put(ifa->ifpub);
			ifa->ifpub = NULL;
		}
		spin_unlock_bh(&ifa->lock);
		in6_ifa_put(ifa);
		write_lock_bh(&idev->lock);
	}
#endif
	while ((ifa = idev->addr_list) != NULL) {
		idev->addr_list = ifa->if_next;
		ifa->if_next = NULL;
		addrconf_del_timer(ifa);
		write_unlock_bh(&idev->lock);
		spin_lock_bh(&ifa_state_lock);
		state = ifa->dead;
		ifa->dead = INET6_IFADDR_STATE_DEAD;
		spin_unlock_bh(&ifa_state_lock);

		if (state == INET6_IFADDR_STATE_DEAD)
			goto put_ifa;


		__ipv6_ifa_notify(RTM_DELADDR, ifa);
		atomic_notifier_call_chain(&inet6addr_chain, NETDEV_DOWN, ifa);

put_ifa:
		in6_ifa_put(ifa);

		write_lock_bh(&idev->lock);
	}
	write_unlock_bh(&idev->lock);

	/* Step 5: Discard multicast list */

	if (how)
		ipv6_mc_destroy_dev(idev);
	else
		ipv6_mc_down(idev);

	idev->tstamp = jiffies;

	/* Shot the device (if unregistered) */

	if (how) {
		addrconf_sysctl_unregister(idev);
		neigh_parms_release(&nd_tbl, idev->nd_parms);
		neigh_ifdown(&nd_tbl, dev);
		in6_dev_put(idev);
	}
	return 0;
}
```