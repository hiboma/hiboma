# netconsole

 * netpoll
   * http://lwn.net/Articles/75944/ 
 * configfs
   * https://www.kernel.org/doc/Documentation/filesystems/configfs/configfs.txt
 * console API

## netpoll とは?

[ゆううきブログ Linuxカーネルにおけるネットワークスタック周りのChangeLog勉強メモ (2.6.0 ~ 2.6.20)](http://yuuki.hatenablog.com/entry/linuxkernel-network-changelog-2.6.0-2.6.20) から引用しております

> Netpollは，I/Oシステムとネットワークシステムが完全には利用できないみたいな不安定な環境でカーネルがパケットを送受信できる仕組みのこと．受信したパケットがnetpoll宛かどうかをTCP/IPのヘッダレベルでNICが判定し，カーネルの受信キューにパケットを積む前にNICが受信処理を行う．
組み込みデバイス環境で使ったりするらしい．

oops 飛ばさないといけない状況だとどこが物故割れてるか分からないし マッチするのかな?

 * 2.6.5-rc1 から
 * ネットワークサブシステム全部を使わない + 割り込み無しでパケットを送受信する low-level の関数
 * kgdbeth, netconsole 

 * Q. 「TCPあるの?」
 * A. 「ないよ」

## struct console

 * printk
 * -> vprintk
 * -> release_console_sem
 * -> call_console_drivers
 * -> _call_console_drivers
 * -> __call_console_drivers で struct console の .write を呼び出す

```c
/*
 * Call the console drivers, asking them to write out
 * log_buf[start] to log_buf[end - 1].
 * The console_sem must be held.
 */
static void call_console_drivers(unsigned start, unsigned end)
{
	unsigned cur_index, start_print;
	static int msg_level = -1;

	BUG_ON(((int)(start - end)) > 0);

	cur_index = start;
	start_print = start;
	while (cur_index != end) {
        // "012345678"
        // "<7> ...." みたいな形式のフォーマットでレベルを決める
		if (msg_level < 0 && ((end - cur_index) > 2) &&
				LOG_BUF(cur_index + 0) == '<' &&
				LOG_BUF(cur_index + 1) >= '0' && // 2文字目がレベル
				LOG_BUF(cur_index + 1) <= '7' && // 2文字目がレベル
				LOG_BUF(cur_index + 2) == '>') {
			msg_level = LOG_BUF(cur_index + 1) - '0';

            // v の文字列を出力するために += 3
            //     vvvvvvv
            // "0123456789"
            // "<7>foo bar"
			cur_index += 3;
			start_print = cur_index;
		}
		while (cur_index != end) {
			char c = LOG_BUF(cur_index);

			cur_index++;
			if (c == '\n') {
				if (msg_level < 0) {
					/*
					 * printk() has already given us loglevel tags in
					 * the buffer.  This code is here in case the
					 * log buffer has wrapped right round and scribbled
					 * on those tags
					 */
					msg_level = default_message_loglevel;
				}
				_call_console_drivers(start_print, cur_index, msg_level);
				msg_level = -1;
				start_print = cur_index;
				break;
			}
		}
	}
	_call_console_drivers(start_print, end, msg_level);
}

/*
 * Write out chars from start to end - 1 inclusive
 */
static void _call_console_drivers(unsigned start,
				unsigned end, int msg_log_level)
{
	if ((msg_log_level < console_loglevel || ignore_loglevel) &&
			console_drivers && start != end) {
		if ((start & LOG_BUF_MASK) > (end & LOG_BUF_MASK)) {
			/* wrapped write */
			__call_console_drivers(start & LOG_BUF_MASK,
						log_buf_len);
			__call_console_drivers(0, end & LOG_BUF_MASK);
		} else {
			__call_console_drivers(start, end);
		}
	}
}

/*
 * Call the console drivers on a range of log_buf
 */
static void __call_console_drivers(unsigned start, unsigned end)
{
	struct console *con;

	for_each_console(con) {
		if ((con->flags & CON_ENABLED) && con->write &&
				(cpu_online(smp_processor_id()) ||
				(con->flags & CON_ANYTIME)))
			con->write(con, &LOG_BUF(start), end - start);
	}
}
``` 

```c
void register_console(struct console *newcon)
```

netconsole も struct console API を利用してメッセージを飛ばす仕組み

 * bootconsoles (early_printk)
   * 何個でも登録できる
 * real console ≠ bootconsoles
   * real console を登録したら bootconsoles は unregister される
   * real console を登録したら bootconsoles は reject される
     * `printk(KERN_INFO "Too late to register bootconsole %s%d\n",`

## struct configfs_subsystem

 * configfs_register_subsystem
 * configfs_unregister_subsystem

configfs で設定値をファイルから書き込める 

```c
/*
 * Our subsystem hierarchy is:
 *
 * /sys/kernel/config/netconsole/
 *				|
 *				<target>/
 *				|	enabled
 *				|	dev_name
 *				|	local_port
 *				|	remote_port
 *				|	local_ip
 *				|	remote_ip
 *				|	local_mac
 *				|	remote_mac
 *				|
 *				<target>/...
 */
```

## struct netconsole

```c
static struct console netconsole = {
	.name	= "netcon",
	.flags	= CON_ENABLED,
	.write	= write_msg,
};
```

.write が汎用API になっているのかな?

## メッセージを書くコード

 * netpoll_send_udp で飛ばしている
 * TCP っぽい文字はひっかからない

```c
static void write_msg(struct console *con, const char *msg, unsigned int len)
{
	int frag, left;
	unsigned long flags;
	struct netconsole_target *nt;
	const char *tmp;

	/* Avoid taking lock and disabling interrupts unnecessarily */
	if (list_empty(&target_list))
		return;

	spin_lock_irqsave(&target_list_lock, flags);
	list_for_each_entry(nt, &target_list, list) {
		netconsole_target_get(nt);
		if (nt->enabled && netif_running(nt->np.dev)) {
			/*
			 * We nest this inside the for-each-target loop above
			 * so that we're able to get as much logging out to
			 * at least one target if we die inside here, instead
			 * of unnecessarily keeping all targets in lock-step.
			 */
			tmp = msg;
			for (left = len; left;) {
				frag = min(left, MAX_PRINT_CHUNK);
				netpoll_send_udp(&nt->np, tmp, frag);
				tmp += frag;
				left -= frag;
			}
		}
		netconsole_target_put(nt);
	}
	spin_unlock_irqrestore(&target_list_lock, flags);
}
```

netpoll API が分からない

```c
void netpoll_send_udp(struct netpoll *np, const char *msg, int len)
{
	int total_len, eth_len, ip_len, udp_len;
	struct sk_buff *skb;
	struct udphdr *udph;
	struct iphdr *iph;
	struct ethhdr *eth;

	udp_len = len + sizeof(*udph);
	ip_len = eth_len = udp_len + sizeof(*iph);
	total_len = eth_len + ETH_HLEN + NET_IP_ALIGN;

	skb = find_skb(np, total_len, total_len - len);
	if (!skb)
		return;

	skb_copy_to_linear_data(skb, msg, len);
	skb->len += len;

	skb_push(skb, sizeof(*udph));
	skb_reset_transport_header(skb);
	udph = udp_hdr(skb);
	udph->source = htons(np->local_port);
	udph->dest = htons(np->remote_port);
	udph->len = htons(udp_len);
	udph->check = 0;
	udph->check = csum_tcpudp_magic(np->local_ip,
					np->remote_ip,
					udp_len, IPPROTO_UDP,
					csum_partial(udph, udp_len, 0));
	if (udph->check == 0)
		udph->check = CSUM_MANGLED_0;

	skb_push(skb, sizeof(*iph));
	skb_reset_network_header(skb);
	iph = ip_hdr(skb);

	/* iph->version = 4; iph->ihl = 5; */
	put_unaligned(0x45, (unsigned char *)iph);
	iph->tos      = 0;
	put_unaligned(htons(ip_len), &(iph->tot_len));
	iph->id       = 0;
	iph->frag_off = 0;
	iph->ttl      = 64;
	iph->protocol = IPPROTO_UDP;
	iph->check    = 0;
	put_unaligned(np->local_ip, &(iph->saddr));
	put_unaligned(np->remote_ip, &(iph->daddr));
	iph->check    = ip_fast_csum((unsigned char *)iph, iph->ihl);

	eth = (struct ethhdr *) skb_push(skb, ETH_HLEN);
	skb_reset_mac_header(skb);
	skb->protocol = eth->h_proto = htons(ETH_P_IP);
	memcpy(eth->h_source, np->dev->dev_addr, ETH_ALEN);
	memcpy(eth->h_dest, np->remote_mac, ETH_ALEN);

	skb->dev = np->dev;

	netpoll_send_skb(np, skb);
}
```

netpoll_send_skb -> netpoll_send_skb_on_dev を呼ぶ

```c
void netpoll_send_skb_on_dev(struct netpoll *np, struct sk_buff *skb,
			     struct net_device *dev)
{
	int status = NETDEV_TX_BUSY;
	unsigned long tries;
	const struct net_device_ops *ops = dev->netdev_ops;
	struct netpoll_info *npinfo = np->dev->npinfo;

	if (!npinfo || !netif_running(dev) || !netif_device_present(dev)) {
		__kfree_skb(skb);
		return;
	}

	/* don't get messages out of order, and no recursion */
	if (skb_queue_len(&npinfo->txq) == 0 && !netpoll_owner_active(dev)) {
		struct netdev_queue *txq;
		unsigned long flags;

		txq = netdev_pick_tx(dev, skb);

		local_irq_save(flags);
		/* try until next clock tick */
		for (tries = jiffies_to_usecs(1)/USEC_PER_POLL;
		     tries > 0; --tries) {
			if (__netif_tx_trylock(txq)) {
				if (!netif_tx_queue_stopped(txq)) {
					dev->priv_flags |= IFF_IN_NETPOLL;
					status = ops->ndo_start_xmit(skb, dev);
					dev->priv_flags &= ~IFF_IN_NETPOLL;
					if (status == NETDEV_TX_OK)
						txq_trans_update(txq);
				}
				__netif_tx_unlock(txq);

				if (status == NETDEV_TX_OK)
					break;

			}

			/* tickle device maybe there is some cleanup */
			netpoll_poll(np);

			udelay(USEC_PER_POLL);
		}

		WARN_ONCE(!irqs_disabled(),
			"netpoll_send_skb(): %s enabled interrupts in poll (%pF)\n",
			dev->name, ops->ndo_start_xmit);

		local_irq_restore(flags);
	}

	if (status != NETDEV_TX_OK) {
		skb_queue_tail(&npinfo->txq, skb);
		schedule_delayed_work(&npinfo->tx_work,0);
	}
}
```