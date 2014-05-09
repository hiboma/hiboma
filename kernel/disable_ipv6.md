# disable IPv6

## TODO

ユーザランドから AF_INET6 を使うかはどうやって決定されるか?
 
## /etc/modprobe.d で無効にする

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
		addrconf_disable_change(net, newf);
	} else if ((!*p) ^ (!old))
		dev_disable_change((struct inet6_dev *)table->extra1);

	rtnl_unlock();
	return 0;
}
```

デバイスをイテレートして IPv6 を止める

```c
static void addrconf_disable_change(struct net *net, __s32 newf)
{
	struct net_device *dev;
	struct inet6_dev *idev;

	read_lock(&dev_base_lock);
	for_each_netdev(net, dev) {
		rcu_read_lock();
		idev = __in6_dev_get(dev);
		if (idev) {
			int changed = (!idev->cnf.disable_ipv6) ^ (!newf);
			idev->cnf.disable_ipv6 = newf;
			if (changed)
				dev_disable_change(idev);
		}
		rcu_read_unlock();
	}
	read_unlock(&dev_base_lock);
}
```

addrconf_notify(NETDEV_DOWN) で IPv6 の停止になる様子

```c
static void dev_disable_change(struct inet6_dev *idev)
{
	if (!idev || !idev->dev)
		return;

	if (idev->cnf.disable_ipv6)
		addrconf_notify(NULL, NETDEV_DOWN, idev->dev);
	else
		addrconf_notify(NULL, NETDEV_UP, idev->dev);
}
```

NETDEV_DOWN と NETDEV_UNREGISTER の違いは?

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
		addrconf_ifdown(dev, event != NETDEV_DOWN);
		break;
```
