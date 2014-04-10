## cgrulesengd

Cgroup Rules Engine Daemon

 * シングルプロセス
   * netlink の読み取り、cgroup の書き出しも直列
 * Process Event Connector
   * sturct proc_event でカーネルから通知されるイベント

``` 
struct proc_event {
	enum what {
		/* Use successive bits so the enums can be used to record
		 * sets of events as well
		 */
		PROC_EVENT_NONE = 0x00000000,
		PROC_EVENT_FORK = 0x00000001,
		PROC_EVENT_EXEC = 0x00000002,
		PROC_EVENT_UID  = 0x00000004,
		PROC_EVENT_GID  = 0x00000040,
		PROC_EVENT_SID  = 0x00000080,
		/* "next" should be 0x00000400 */
		/* "last" is the last process event: exit */
		PROC_EVENT_EXIT = 0x80000000
	} what;
	__u32 cpu;
	__u64 __attribute__((aligned(8))) timestamp_ns;
		/* Number of nano seconds since system boot */
	union { /* must be last field of proc_event struct */
		struct {
			__u32 err;
		} ack;

		struct fork_proc_event {
			__kernel_pid_t parent_pid;
			__kernel_pid_t parent_tgid;
			__kernel_pid_t child_pid;
			__kernel_pid_t child_tgid;
		} fork;

		struct exec_proc_event {
			__kernel_pid_t process_pid;
			__kernel_pid_t process_tgid;
		} exec;

		struct id_proc_event {
			__kernel_pid_t process_pid;
			__kernel_pid_t process_tgid;
			union {
				__u32 ruid; /* task uid */
				__u32 rgid; /* task gid */
			} r;
			union {
				__u32 euid;
				__u32 egid;
			} e;
		} id;

		struct sid_proc_event {
			__kernel_pid_t process_pid;
			__kernel_pid_t process_tgid;
		} sid;

		struct exit_proc_event {
			__kernel_pid_t process_pid;
			__kernel_pid_t process_tgid;
			__u32 exit_code, exit_signal;
		} exit;
	} event_data;
};
``` 

## 要点   

 * cgre_create_netlink_socket_process_msg
   * socket(PF_NETLINK + SOCK_DGRAM + NETLINK_CONNECTOR) + PROC_CN_MCAST_LISTEN;
     * プロセスの fork, exec, setuid, setgid, exit をソケットから read
      * struct proc_event = Process Event Connector
        * http://lwn.net/Articles/157150/
     * 該当する pid をイベント cgconfig.conf に従って /cgroup に移す
   * - プロセスのイベントと完全に同期している訳ではない
   * - cgrulesengd 起動前のプロセスは対象外
 * cgroup_reload_cached_templates     
   * SIGUSR1 で /etc/cgconfig.conf のキャッシュをリロード

#### カーネル
   
 * cn_add_callback

``` c
/*
 * cn_proc_init - initialization entry point
 *
 * Adds the connector callback to the connector driver.
 */
static int __init cn_proc_init(void)
{
	int err;

	if ((err = cn_add_callback(&cn_proc_event_id, "cn_proc",
	 			   &cn_proc_mcast_ctl))) {
		printk(KERN_WARNING "cn_proc failed to register\n");
		return err;
	}
	return 0;
}
```

 * proc_fork_connector の中身
   * cn_netlink_send でメッセージをユーザランドに飛ばす
   * ソケット周りのめんどくさい実装はしなくていい様子
```c
void proc_fork_connector(struct task_struct *task)
{
	struct cn_msg *msg;
	struct proc_event *ev;
	__u8 buffer[CN_PROC_MSG_SIZE];
	struct timespec ts;

	if (atomic_read(&proc_event_num_listeners) < 1)
		return;

	msg = (struct cn_msg*)buffer;
	ev = (struct proc_event*)msg->data;
	get_seq(&msg->seq, &ev->cpu);
	ktime_get_ts(&ts); /* get high res monotonic timestamp */
	put_unaligned(timespec_to_ns(&ts), (__u64 *)&ev->timestamp_ns);
	ev->what = PROC_EVENT_FORK;
	ev->event_data.fork.parent_pid = task->real_parent->pid;
	ev->event_data.fork.parent_tgid = task->real_parent->tgid;
	ev->event_data.fork.child_pid = task->pid;
	ev->event_data.fork.child_tgid = task->tgid;

	memcpy(&msg->id, &cn_proc_event_id, sizeof(msg->id));
	msg->ack = 0; /* not used */
	msg->len = sizeof(*ev);
	/*  If cn_netlink_send() failed, the data is not sent */
	cn_netlink_send(msg, CN_IDX_PROC, GFP_KERNEL);
}
```

## ソース

cgre_create_netlink_socket_process_msg
 
```c   
static int cgre_create_netlink_socket_process_msg(void)
{
	int sk_nl = 0, sk_unix = 0, sk_max;
	struct sockaddr_nl my_nla;
	char buff[BUFF_SIZE];
	int rc = -1;
	struct nlmsghdr *nl_hdr;
	struct cn_msg *cn_hdr;
	enum proc_cn_mcast_op *mcop_msg;
	struct sockaddr_un saddr;
	fd_set fds, readfds;
	sigset_t sigset;

	/*
	 * Create an endpoint for communication. Use the kernel user
	 * interface device (PF_NETLINK) which is a datagram oriented
	 * service (SOCK_DGRAM). The protocol used is the connector
	 * protocol (NETLINK_CONNECTOR)
	 */
	sk_nl = socket(PF_NETLINK, SOCK_DGRAM, NETLINK_CONNECTOR);
	if (sk_nl == -1) {
		flog(LOG_ERR, "Error: error opening netlink socket: %s\n",
				strerror(errno));
		return rc;
	}

	my_nla.nl_family = AF_NETLINK;
	my_nla.nl_groups = CN_IDX_PROC;
	my_nla.nl_pid = getpid();
	my_nla.nl_pad = 0;

	if (bind(sk_nl, (struct sockaddr *)&my_nla, sizeof(my_nla)) < 0) {
		flog(LOG_ERR, "Error: error binding netlink socket: %s\n",
				strerror(errno));
		goto close_and_exit;
	}

	nl_hdr = (struct nlmsghdr *)buff;
	cn_hdr = (struct cn_msg *)NLMSG_DATA(nl_hdr);
	mcop_msg = (enum proc_cn_mcast_op*)&cn_hdr->data[0];
	flog(LOG_DEBUG, "Sending proc connector: PROC_CN_MCAST_LISTEN...\n");
	memset(buff, 0, sizeof(buff));
	*mcop_msg = PROC_CN_MCAST_LISTEN;

	/* fill the netlink header */
	nl_hdr->nlmsg_len = SEND_MESSAGE_LEN;
	nl_hdr->nlmsg_type = NLMSG_DONE;
	nl_hdr->nlmsg_flags = 0;
	nl_hdr->nlmsg_seq = 0;
	nl_hdr->nlmsg_pid = getpid();

	/* fill the connector header */
	cn_hdr->id.idx = CN_IDX_PROC;
	cn_hdr->id.val = CN_VAL_PROC;
	cn_hdr->seq = 0;
	cn_hdr->ack = 0;
	cn_hdr->len = sizeof(enum proc_cn_mcast_op);
	flog(LOG_DEBUG, "Sending netlink message len=%d, cn_msg len=%d\n",
		nl_hdr->nlmsg_len, (int) sizeof(struct cn_msg));
	if (send(sk_nl, nl_hdr, nl_hdr->nlmsg_len, 0) != nl_hdr->nlmsg_len) {
		flog(LOG_ERR,
				"Error: failed to send netlink message (mcast ctl op): %s\n",
				strerror(errno));
		goto close_and_exit;
	}
	flog(LOG_DEBUG, "Message sent\n");
```

cgre_receive_netlink_msg で netlink のメッセージを recvfrom

```c
static int cgre_receive_netlink_msg(int sk_nl)
{
	char buff[BUFF_SIZE];
	size_t recv_len;
	struct sockaddr_nl from_nla;
	socklen_t from_nla_len;
	struct nlmsghdr *nlh;
	struct cn_msg *cn_hdr;

	memset(buff, 0, sizeof(buff));
	from_nla_len = sizeof(from_nla);

    // netlink のソケット
	recv_len = recvfrom(sk_nl, buff, sizeof(buff), 0,
		(struct sockaddr *)&from_nla, &from_nla_len);
	if (recv_len == ENOBUFS) {
		flog(LOG_ERR, "ERROR: NETLINK BUFFER FULL, MESSAGE DROPPED!\n");
		return 0;
	}
	if (recv_len < 1)
		return 0;

	if (from_nla_len != sizeof(from_nla)) {
		flog(LOG_ERR, "Bad address size reading netlink socket\n");
		return 0;
	}
	if (from_nla.nl_groups != CN_IDX_PROC
	    || from_nla.nl_pid != 0)
		return 0;

	nlh = (struct nlmsghdr *)buff;
	while (NLMSG_OK(nlh, recv_len)) {
		cn_hdr = NLMSG_DATA(nlh);
		if (nlh->nlmsg_type == NLMSG_NOOP) {
			nlh = NLMSG_NEXT(nlh, recv_len);
			continue;
		}
		if ((nlh->nlmsg_type == NLMSG_ERROR) ||
				(nlh->nlmsg_type == NLMSG_OVERRUN))
			break;
		if (cgre_handle_msg(cn_hdr) < 0)
			return 1;
		if (nlh->nlmsg_type == NLMSG_DONE)
			break;
		nlh = NLMSG_NEXT(nlh, recv_len);
	}
	return 0;
}
```

cgre_handle_msg で イベントに応じてあれこれする

 * struct proc_event の .what でイベント内容を取れる
 * uid/gid が変わったとか fork されたとかで cgroup に入れたり削除したり

```c
/**
 * Handle a netlink message.  In the event of PROC_EVENT_UID or PROC_EVENT_GID,
 * we pass the event along to cgre_process_event for further processing.  All
 * other events are ignored.
 * 	@param cn_hdr The netlink message
 * 	@return 0 on success, > 0 on error
 */
static int cgre_handle_msg(struct cn_msg *cn_hdr)
{
	/* The event to consider */
	struct proc_event *ev;

	/* Return codes */
	int ret = 0;

	/* Get the event data.  We only care about two event types. */
	ev = (struct proc_event*)cn_hdr->data;
	switch (ev->what) {
	case PROC_EVENT_UID:
		flog(LOG_DEBUG,
				"UID Event: PID = %d, tGID = %d, rUID = %d, eUID = %d\n",
				ev->event_data.id.process_pid,
				ev->event_data.id.process_tgid,
				ev->event_data.id.r.ruid,
				ev->event_data.id.e.euid);
		ret = cgre_process_event(ev, PROC_EVENT_UID);
		break;
	case PROC_EVENT_GID:
		flog(LOG_DEBUG,
				"GID Event: PID = %d, tGID = %d, rGID = %d, eGID = %d\n",
				ev->event_data.id.process_pid,
				ev->event_data.id.process_tgid,
				ev->event_data.id.r.rgid,
				ev->event_data.id.e.egid);
		ret = cgre_process_event(ev, PROC_EVENT_GID);
		break;
	case PROC_EVENT_FORK:
		ret = cgre_process_event(ev, PROC_EVENT_FORK);
		break;
	case PROC_EVENT_EXIT:
		ret = cgre_process_event(ev, PROC_EVENT_EXIT);
		break;
	case PROC_EVENT_EXEC:
		flog(LOG_DEBUG, "EXEC Event: PID = %d, tGID = %d\n",
				ev->event_data.exec.process_pid,
				ev->event_data.exec.process_tgid);
		ret = cgre_process_event(ev, PROC_EVENT_EXEC);
		break;
	default:
		break;
	}

	return ret;
}
```
 