# netconsole

 * Q. 「TCPあるの?」
 * A. 「ないよ」

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