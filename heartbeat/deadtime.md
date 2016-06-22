# deadtime

## 設定箇所

config->deadtime_ms に保持

```c
/* Set the dead timeout */
static int
set_deadtime_ms(const char * value)
{
	config->deadtime_ms = cl_get_msec(value);
	if (config->deadtime_ms >= 0) {
		return(HA_OK);
	}
	return(HA_FAIL);
}
```

## 参照箇所

 * `CRITICAL "Late heartbeat: Node %s: interval %ld ms (> deadtime)"`
   * 3.0.3 ではこのログはでない
   * mark_node_dead で ノードを dead とする
 * `WARNING  "Late heartbeat: Node %s: interval %ld ms"`
   * ログを出すけだけで何もしない
 
```c
/* Process status update (i.e., "heartbeat") message? */
static void
HBDoMsg_T_STATUS(const char * type, struct node_info * fromnode
,	TIME_T msgtime, seqno_t seqno, const char * iface, struct ha_msg * msg)
{

	const char *	status;
	longclock_t		messagetime = time_longclock();
	const char	*tmpstr;
	long		deadtime;
	int		protover;

	status = ha_msg_value(msg, F_STATUS);
	if (status == NULL)  {
		cl_log(LOG_ERR, "HBDoMsg_T_STATUS: "
		"status update without "
		F_STATUS " field");
		return;
	}
	
	/* Does it contain F_PROTOCOL field?*/
	

	/* Do we already have a newer status? */
	if (msgtime < fromnode->rmt_lastupdate
	&&		seqno < fromnode->status_seqno) {
		return;
	}

	/* Have we seen an update from here before? */
	if (fromnode->nodetype != PINGNODE_I
	    && enable_flow_control 
	    && ha_msg_value_int(msg, F_PROTOCOL, &protover) != HA_OK){		
		cl_log(LOG_INFO, "flow control disabled due to different version heartbeat");
		enable_flow_control = FALSE;
		hb_remove_msg_callback(T_ACKMSG);
	}

	if (fromnode->local_lastupdate) {
		long		heartbeat_ms;
		heartbeat_ms = longclockto_ms(sub_longclock
		(	messagetime, fromnode->local_lastupdate));

		if (heartbeat_ms > config->deadtime_ms) {
			cl_log(LOG_CRIT
			,	"Late heartbeat: Node %s:"
			" interval %ld ms (> deadtime)"
			,	fromnode->nodename
			,	heartbeat_ms);
			/* something delayed us so badly that
			 * check_for_timeouts() was not run in time to detect
			 * the node as dead. Now, it turns out it was not dead
			 * after all, anyways.
			 * Maybe it detected us as being dead, though,
			 * and sees us rejoining after partition.
			 *
			 * Can we really get away by simply tickling the ccm?
			 */
			if (fromnode != curnode)
				mark_node_dead(fromnode);

		} else if (heartbeat_ms > config->warntime_ms) {
			cl_log(LOG_WARNING
			,	"Late heartbeat: Node %s:"
			" interval %ld ms"
			,	fromnode->nodename
			,	heartbeat_ms);
		}
	}
```

## mark_node_dead

 * `WARNING "node %s: is dead", hip->nodename;`
 * hb_rsc_recover_dead_resources is ?
 * reset_seqtrack とやらで何かをリセットする

```c
/* Mark the given node dead */
static void
mark_node_dead(struct node_info *hip)
{
	cl_log(LOG_WARNING, "node %s: is dead", hip->nodename);

	if (hip == curnode) {
		/* Uh, oh... we're dead! */
		cl_log(LOG_ERR, "No local heartbeat. Forcing restart.");
		cl_log(LOG_INFO, "See URL: %s"
		,	HAURL("FAQ#No_Local_Heartbeat"));

		if (!shutdown_in_progress) {
			cause_shutdown_restart();
		}
		return;
	}

	if (hip->nodetype == NORMALNODE_I
	&&	STRNCMP_CONST(hip->status, DEADSTATUS) != 0
	&&	STRNCMP_CONST(hip->status, INITSTATUS) != 0) {
		--live_node_count;
	}
	strncpy(hip->status, DEADSTATUS, sizeof(hip->status));
	

	/* THIS IS RESOURCE WORK!  FIXME */
	hb_rsc_recover_dead_resources(hip);
	
	hip->rmt_lastupdate = 0L;
	hip->anypacketsyet  = 0;
	reset_seqtrack(hip);
}
```

## ping_write

 * heartbeat = ICMP パケットを飛ばす
 * ICMP_ECHO パケトッを自分で作って sendto(2)

```c
/*
 * Send a heartbeat packet over ICMP ping channel
 *
 * The peculiar thing here is that we don't send the packet we're given at all
 *
 * Instead, we send out the packet we want to hear back from them, just
 * as though we were they ;-)  That's what comes of having such a dumb
 * device as a "member" of our cluster...
 *
 * We ignore packets we're given to write that aren't "status" packets.
 *
 */

static int
ping_write(struct hb_media* mp, void *p, int len)
{
	struct ping_private *	ei;
	int			rc;
	char*			pkt;
	union{
		char*			buf;
		struct icmp		ipkt;
	}*icmp_pkt;
	size_t			size;
	struct icmp *		icp;
	size_t			pktsize;
	const char *		type;
	const char *		ts;
	struct ha_msg *		nmsg;
	struct ha_msg *		msg;
	static gboolean		needroot = FALSE;
	
	
	msg = wirefmt2msg(p, len, MSG_NEEDAUTH);
	if( !msg){
		PILCallLog(LOG, PIL_CRIT, "ping_write(): cannot convert wirefmt to msg");
		return(HA_FAIL);
	}
	
	PINGASSERT(mp);
	ei = (struct ping_private *) mp->pd;
	type = ha_msg_value(msg, F_TYPE);
	
	if (type == NULL || strcmp(type, T_STATUS) != 0 
	|| ((ts = ha_msg_value(msg, F_TIME)) == NULL)) {
		ha_msg_del(msg);
		return HA_OK;
	}

	/*
	 * We populate the following fields in the packet we create:
	 *
	 * F_TYPE:	T_NS_STATUS
	 * F_STATUS:	ping
	 * F_COMMENT:	ping
	 * F_ORIG:	destination name
	 * F_TIME:	local timestamp (from "msg")
	 * F_AUTH:	added by add_msg_auth()
	 */
	if ((nmsg = ha_msg_new(5)) == NULL) {
		PILCallLog(LOG, PIL_CRIT, "cannot create new message");
		ha_msg_del(msg);
		return(HA_FAIL);
	}

	if (ha_msg_add(nmsg, F_TYPE, T_NS_STATUS) != HA_OK
	||	ha_msg_add(nmsg, F_STATUS, PINGSTATUS) != HA_OK
	||	ha_msg_add(nmsg, F_COMMENT, PIL_PLUGIN_S) != HA_OK
	||	ha_msg_add(nmsg, F_ORIG, mp->name) != HA_OK
	||	ha_msg_add(nmsg, F_TIME, ts) != HA_OK) {
		ha_msg_del(nmsg); nmsg = NULL;
		PILCallLog(LOG, PIL_CRIT, "cannot add fields to message");
		ha_msg_del(msg);
		return HA_FAIL;
	}

	if (add_msg_auth(nmsg) != HA_OK) {
		PILCallLog(LOG, PIL_CRIT, "cannot add auth field to message");
		ha_msg_del(nmsg); nmsg = NULL;
		ha_msg_del(msg);
		return HA_FAIL;
	}
	
	if ((pkt = msg2wirefmt(nmsg, &size)) == NULL)  {
		PILCallLog(LOG, PIL_CRIT, "cannot convert message to string");
		ha_msg_del(msg);
		return HA_FAIL;
	}
	ha_msg_del(nmsg); nmsg = NULL;


	pktsize = size + ICMP_HDR_SZ;

	if ((icmp_pkt = MALLOC(pktsize)) == NULL) {
		PILCallLog(LOG, PIL_CRIT, "out of memory");
		free(pkt);
		ha_msg_del(msg);
		return HA_FAIL;
	}

	icp = &(icmp_pkt->ipkt);
	icp->icmp_type = ICMP_ECHO;
	icp->icmp_code = 0;
	icp->icmp_cksum = 0;
	icp->icmp_seq = htons(ei->iseq);
	icp->icmp_id = ei->ident;	/* Only used by us */
	++ei->iseq;

	memcpy(icp->icmp_data, pkt, size);
	free(pkt); pkt = NULL;

	/* Compute the ICMP checksum */
	icp->icmp_cksum = in_cksum((u_short *)icp, pktsize);

retry:
	if (needroot) {
		return_to_orig_privs();
	}

	if ((rc=sendto(ei->sock, (void *) icmp_pkt, pktsize, MSG_DONTWAIT
	,	(struct sockaddr *)&ei->addr
	,	sizeof(struct sockaddr))) != (ssize_t)pktsize) {
		if (errno == EPERM && !needroot) {
			needroot=TRUE;
			goto retry;
		}
		if (!mp->suppresserrs) {
			PILCallLog(LOG, PIL_CRIT, "Error sending packet: %s", strerror(errno));
			PILCallLog(LOG, PIL_INFO, "euid=%lu egid=%lu"
			,	(unsigned long) geteuid()
			,	(unsigned long) getegid());
		}
		FREE(icmp_pkt);
		ha_msg_del(msg);
		return(HA_FAIL);
	}
	if (needroot) {
		return_to_dropped_privs();
	}

	if (DEBUGPKT) {
		PILCallLog(LOG, PIL_DEBUG, "sent %d bytes to %s"
		,	rc, inet_ntoa(ei->addr.sin_addr));
   	}
	if (DEBUGPKTCONT) {
		PILCallLog(LOG, PIL_DEBUG, "ping pkt: %s"
		,	icp->icmp_data);
   	}
	FREE(icmp_pkt);
	ha_msg_del(msg);
	return HA_OK;
  
}
```

```
/*
 *	List of functions provided by implementations of the heartbeat media
 *	interface.
 */
struct hb_media_fns {
	struct hb_media*(*new)		(const char * token);
	int		(*parse)	(const char * options);
	int		(*mopen)	(struct hb_media *mp);
	int		(*close)	(struct hb_media *mp);
	void*		(*read)		(struct hb_media *mp, int *len );
	int		(*write)	(struct hb_media *mp
					 ,	void *msg, int len);
	int		(*mtype)	(char **buffer);
	int		(*descr)	(char **buffer);
	int		(*isping)	(void);
};
```

## ping_read

 * recvfrom(2) で ICMP_ECHOREPLY を受け取る
 * タイムアウトはない?

```
/*
 * Receive a heartbeat ping reply packet.
 * NOTE: This code only needs to run once for ALL ping nodes.
 * FIXME!!
 */

static char ping_pkt[MAXLINE];
static void *
ping_read(struct hb_media* mp, int *lenp)
{
	struct ping_private *	ei;
	union {
		char		cbuf[MAXLINE+ICMP_HDR_SZ];
		struct ip	ip;
	}buf;
	const char *		bufmax = ((char *)&buf)+sizeof(buf);
	char *			msgstart;
	socklen_t		addr_len = sizeof(struct sockaddr);
   	struct sockaddr_in	their_addr; /* connector's addr information */
	struct ip *		ip;
	struct icmp		icp;
	int			numbytes;
	int			hlen;
	struct ha_msg *		msg;
	const char 		*comment;
	int			pktlen;
	
	PINGASSERT(mp);
	ei = (struct ping_private *) mp->pd;

ReRead:	/* We recv lots of packets that aren't ours */
	
	if ((numbytes=recvfrom(ei->sock, (void *) &buf.cbuf
	,	sizeof(buf.cbuf)-1, 0,	(struct sockaddr *)&their_addr
	,	&addr_len)) < 0) {
		if (errno != EINTR) {
			PILCallLog(LOG, PIL_CRIT, "Error receiving from socket: %s"
			,	strerror(errno));
		}
		return NULL;
	}
	/* Avoid potential buffer overruns */
	buf.cbuf[numbytes] = EOS;

	/* Check the IP header */
	ip = &buf.ip;
	hlen = ip->ip_hl * 4;

	if (numbytes < hlen + ICMP_MINLEN) {
		PILCallLog(LOG, PIL_WARN, "ping packet too short (%d bytes) from %s"
		,	numbytes
		,	inet_ntoa(*(struct in_addr *)
		&		their_addr.sin_addr.s_addr));
		return NULL;
	}
	
	/* Now the ICMP part */	/* (there may be a better way...) */
	memcpy(&icp, (buf.cbuf + hlen), sizeof(icp));
	
	if (icp.icmp_type != ICMP_ECHOREPLY || icp.icmp_id != ei->ident) {
		goto ReRead;	/* Not one of ours */
	}

	if (DEBUGPKT) {
		PILCallLog(LOG, PIL_DEBUG, "got %d byte packet from %s"
		,	numbytes, inet_ntoa(their_addr.sin_addr));
	}
	msgstart = (buf.cbuf + hlen + ICMP_HDR_SZ);

	if (DEBUGPKTCONT && numbytes > 0) {
		PILCallLog(LOG, PIL_DEBUG, "%s", msgstart);
	}
	
	pktlen = numbytes - hlen - ICMP_HDR_SZ;

	memcpy(ping_pkt, buf.cbuf + hlen + ICMP_HDR_SZ, pktlen);
	ping_pkt[pktlen] = 0;
	*lenp = pktlen + 1;
	
	msg = wirefmt2msg(msgstart, bufmax - msgstart, MSG_NEEDAUTH);
	if (msg == NULL) {
		errno = EINVAL;
		return(NULL);
	}
	comment = ha_msg_value(msg, F_COMMENT);
	if (comment == NULL || strcmp(comment, PIL_PLUGIN_S) != 0) {
		ha_msg_del(msg);
		errno = EINVAL;
		return(NULL);
	}
	
	ha_msg_del(msg);
	return (ping_pkt);
}
```