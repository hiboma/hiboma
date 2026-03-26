# AUDIT_SYSCALL 

システムコール呼び出しをすると記録されるイベント

```
# sendto(2)
type=SYSCALL msg=audit(1727851217.302:1922): arch=c000003e syscall=44 success=yes exit=1080 a0=a a1=7ffdf7a42340 a2=438 a3=0 items=0 ppid=1 pid=25425 auid=4294967295 uid=0 gid=112 euid=0 suid=0 fsuid=0 egid=112 sgid=112 fsgid=112 tty=(none) ses=4294967295 comm="wazuh-syscheckd" exe="/var/ossec/bin/wazuh-syscheckd" subj=unconfined key=(null) ARCH=x86_64 SYSCALL=sendto AUID="unset" UID="root" GID="wazuh" EUID="root" SUID="root" FSUID="root" EGID="wazuh" SGID="wazuh" FSGID="wazuh"

# mkdirat(2)
type=SYSCALL msg=audit(1727863623.516:2326): arch=c000003e syscall=258 success=no exit=-17 a0=ffffff9c a1=61f2336deb80 a2=1ed a3=0 items=1 ppid=1 pid=32862 auid=4294967295 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=(none) ses=4294967295 comm="(fwupd)" exe="/usr/lib/systemd/systemd-executor" subj=unconfined key="wazuh_fim"ARCH=x86_64 SYSCALL=mkdirat AUID="unset" UID="root" GID="root" EUID="root" SUID="root" FSUID="root" EGID="root" SGID="root" FSGID="root"

# unlink(2)
type=SYSCALL msg=audit(1727851339.970:2053): arch=c000003e syscall=87 success=yes exit=0 a0=5ded040be840 a1=5ded040be840 a2=8000 a3=100 items=2 ppid=29563 pid=29574 auid=1000 uid=0 gid=0 euid=0 suid=0 fsuid=0 egid=0 sgid=0 fsgid=0 tty=pts3 ses=131 comm="dpkg" exe="/usr/bin/dpkg" subj=unconfined key="wazuh_fim"ARCH=x86_64 SYSCALL=unlink AUID="hiboma" UID="root" GID="root" EUID="root" SUID="root" FSUID="root" EGID="root" SGID="root" FSGID="root"
```

### include/uapi/linux/audit.h

AUDIT_LOGIN 定数から追いかけていく

```
:#define AUDIT_SYSCALL		1300	/* Syscall event */
```

```
# __exit(2) のパス

-> void __noreturn do_exit(long code)
  -> static inline void audit_free(struct task_struct *task)
    -> void __audit_free(struct task_struct *tsk)
     -> static void audit_log_exit(void) // AUDIT_SYSCALL
       ...

# システムコール呼び出しのパス
->__visible noinstr bool do_fast_syscall_32(struct pt_regs *regs)
 -> static noinstr bool __do_fast_syscall_32(struct pt_regs *regs)
  -> __visible noinstr void syscall_exit_to_user_mode(struct pt_regs *regs) ✍️
   -> void syscall_exit_to_user_mode_work(struct pt_regs *regs)
    ->static __always_inline void __syscall_exit_to_user_mode_work(struct pt_regs *regs)
     -> static void syscall_exit_to_user_mode_prepare(struct pt_regs *regs)
       -> static void syscall_exit_work(struct pt_regs *regs, unsigned long work)
         -> static inline void audit_syscall_exit(void *pt_regs)
           -> void __audit_syscall_exit(int success, long return_code) 
            -> static void audit_log_exit(void) // AUDIT_SYSCALL
              ...
```

 * noinstr ... [Entry/exit handling for exceptions, interrupts, syscalls and KVM — The Linux Kernel documentation](https://docs.kernel.org/core-api/entry.html)

## audit_log_exit()

システムコールの呼び出し記録する。システムコールに応じて予備情報を付加していく。

```c
static void audit_log_exit(void)
{
	int i, call_panic = 0;
	struct audit_context *context = audit_context();
	struct audit_buffer *ab;
	struct audit_aux_data *aux;
	struct audit_names *n;

	context->personality = current->personality;

	switch (context->context) {
	case AUDIT_CTX_SYSCALL:
		ab = audit_log_start(context, GFP_KERNEL, AUDIT_SYSCALL);
		if (!ab)
			return;
		audit_log_format(ab, "arch=%x syscall=%d",
				 context->arch, context->major);
		if (context->personality != PER_LINUX)
			audit_log_format(ab, " per=%lx", context->personality); ✍️
		if (context->return_valid != AUDITSC_INVALID)
			audit_log_format(ab, " success=%s exit=%ld",
					 (context->return_valid == AUDITSC_SUCCESS ?
					  "yes" : "no"),
					 context->return_code);
		audit_log_format(ab,
				 " a0=%lx a1=%lx a2=%lx a3=%lx items=%d",
				 context->argv[0],
				 context->argv[1],
				 context->argv[2],
				 context->argv[3],
				 context->name_count);
		audit_log_task_info(ab); ✍️
		audit_log_key(ab, context->filterkey); ✍️
		audit_log_end(ab);
		break;
	case AUDIT_CTX_URING:
		audit_log_uring(context);
		break;
	default:
		BUG();
		break;
	}
    
	for (aux = context->aux; aux; aux = aux->next) {

		ab = audit_log_start(context, GFP_KERNEL, aux->type);
		if (!ab)
			continue; /* audit_panic has been called */

		switch (aux->type) {

		case AUDIT_BPRM_FCAPS: {
			struct audit_aux_data_bprm_fcaps *axs = (void *)aux;

			audit_log_format(ab, "fver=%x", axs->fcap_ver);
			audit_log_cap(ab, "fp", &axs->fcap.permitted);
			audit_log_cap(ab, "fi", &axs->fcap.inheritable);
			audit_log_format(ab, " fe=%d", axs->fcap.fE);
			audit_log_cap(ab, "old_pp", &axs->old_pcap.permitted);
			audit_log_cap(ab, "old_pi", &axs->old_pcap.inheritable);
			audit_log_cap(ab, "old_pe", &axs->old_pcap.effective);
			audit_log_cap(ab, "old_pa", &axs->old_pcap.ambient);
			audit_log_cap(ab, "pp", &axs->new_pcap.permitted);
			audit_log_cap(ab, "pi", &axs->new_pcap.inheritable);
			audit_log_cap(ab, "pe", &axs->new_pcap.effective);
			audit_log_cap(ab, "pa", &axs->new_pcap.ambient);
			audit_log_format(ab, " frootid=%d",
					 from_kuid(&init_user_ns,
						   axs->fcap.rootid));
			break; }

		}
		audit_log_end(ab);
	}

	if (context->type)
		show_special(context, &call_panic); ✍️

	if (context->fds[0] >= 0) {
		ab = audit_log_start(context, GFP_KERNEL, AUDIT_FD_PAIR);
		if (ab) {
			audit_log_format(ab, "fd0=%d fd1=%d",
					context->fds[0], context->fds[1]);
			audit_log_end(ab);
		}
	}

	if (context->sockaddr_len) {
		ab = audit_log_start(context, GFP_KERNEL, AUDIT_SOCKADDR);
		if (ab) {
			audit_log_format(ab, "saddr=");
			audit_log_n_hex(ab, (void *)context->sockaddr,
					context->sockaddr_len);
			audit_log_end(ab);
		}
	}

	for (aux = context->aux_pids; aux; aux = aux->next) {
		struct audit_aux_data_pids *axs = (void *)aux;

		for (i = 0; i < axs->pid_count; i++)
			if (audit_log_pid_context(context, axs->target_pid[i],
						  axs->target_auid[i],
						  axs->target_uid[i],
						  axs->target_sessionid[i],
						  axs->target_sid[i],
						  axs->target_comm[i]))
				call_panic = 1;
	}

	if (context->target_pid &&
	    audit_log_pid_context(context, context->target_pid,
				  context->target_auid, context->target_uid,
				  context->target_sessionid,
				  context->target_sid, context->target_comm))
			call_panic = 1;

    // カレントディレクトリ
	if (context->pwd.dentry && context->pwd.mnt) {
		ab = audit_log_start(context, GFP_KERNEL, AUDIT_CWD);
		if (ab) {
			audit_log_d_path(ab, "cwd=", &context->pwd);
			audit_log_end(ab);
		}
	}

	i = 0;
	list_for_each_entry(n, &context->names_list, list) {
		if (n->hidden)
			continue;
		audit_log_name(context, n, NULL, i++, &call_panic);
	}

    // proctitle の記録
	if (context->context == AUDIT_CTX_SYSCALL)
		audit_log_proctitle();

	/* Send end of event record to help user space know we are finished */
	ab = audit_log_start(context, GFP_KERNEL, AUDIT_EOE);
	if (ab)
		audit_log_end(ab);
	if (call_panic)
		audit_panic("error in audit_log_exit()");
}
```

### ✍️ [personality(2) - Linux manual page](https://www.man7.org/linux/man-pages/man2/personality.2.html)

### ✍️ audit_log_task_info

 * current->cred の *id の記録
 * currren->mm->exe_file の記録
 * TTY の記録

```c
void audit_log_task_info(struct audit_buffer *ab)
{
	const struct cred *cred;
	char comm[sizeof(current->comm)];
	struct tty_struct *tty;

	if (!ab)
		return;

	cred = current_cred();
	tty = audit_get_tty();
	audit_log_format(ab,
			 " ppid=%d pid=%d auid=%u uid=%u gid=%u"
			 " euid=%u suid=%u fsuid=%u"
			 " egid=%u sgid=%u fsgid=%u tty=%s ses=%u",
			 task_ppid_nr(current),
			 task_tgid_nr(current),
			 from_kuid(&init_user_ns, audit_get_loginuid(current)),
			 from_kuid(&init_user_ns, cred->uid),
			 from_kgid(&init_user_ns, cred->gid),
			 from_kuid(&init_user_ns, cred->euid),
			 from_kuid(&init_user_ns, cred->suid),
			 from_kuid(&init_user_ns, cred->fsuid),
			 from_kgid(&init_user_ns, cred->egid),
			 from_kgid(&init_user_ns, cred->sgid),
			 from_kgid(&init_user_ns, cred->fsgid),
			 tty ? tty_name(tty) : "(none)",
			 audit_get_sessionid(current));
	audit_put_tty(tty);
	audit_log_format(ab, " comm=");
	audit_log_untrustedstring(ab, get_task_comm(comm, current));
	audit_log_d_path_exe(ab, current->mm);
	audit_log_task_context(ab);
}
EXPORT_SYMBOL(audit_log_task_info);
```

### ✍️ audit_log_key

```
void audit_log_key(struct audit_buffer *ab, char *key)
{
	audit_log_format(ab, " key=");
	if (key)
		audit_log_untrustedstring(ab, key);
	else
		audit_log_format(ab, "(null)");
}
```

### ✍️ show_special()

context->type に応じて情報を付加する
   * AUDIT_IPC, AUDIT_EXECVE, AUDIT_MMAP ... など
     * AUDIT_EXECVE の場合は、 audit_log_execve_info() を呼び出す

```c
static void show_special(struct audit_context *context, int *call_panic)
{
	struct audit_buffer *ab;
	int i;

	ab = audit_log_start(context, GFP_KERNEL, context->type);
	if (!ab)
		return;

	switch (context->type) {
	case AUDIT_SOCKETCALL: {
		int nargs = context->socketcall.nargs;

		audit_log_format(ab, "nargs=%d", nargs);
		for (i = 0; i < nargs; i++)
			audit_log_format(ab, " a%d=%lx", i,
				context->socketcall.args[i]);
		break; }
	case AUDIT_IPC: {
		u32 osid = context->ipc.osid;

		audit_log_format(ab, "ouid=%u ogid=%u mode=%#ho",
				 from_kuid(&init_user_ns, context->ipc.uid),
				 from_kgid(&init_user_ns, context->ipc.gid),
				 context->ipc.mode);
		if (osid) {
			char *ctx = NULL;
			u32 len;

			if (security_secid_to_secctx(osid, &ctx, &len)) {
				audit_log_format(ab, " osid=%u", osid);
				*call_panic = 1;
			} else {
				audit_log_format(ab, " obj=%s", ctx);
				security_release_secctx(ctx, len);
			}
		}
		if (context->ipc.has_perm) {
			audit_log_end(ab);
			ab = audit_log_start(context, GFP_KERNEL,
					     AUDIT_IPC_SET_PERM);
			if (unlikely(!ab))
				return;
			audit_log_format(ab,
				"qbytes=%lx ouid=%u ogid=%u mode=%#ho",
				context->ipc.qbytes,
				context->ipc.perm_uid,
				context->ipc.perm_gid,
				context->ipc.perm_mode);
		}
		break; }
	case AUDIT_MQ_OPEN:
		audit_log_format(ab,
			"oflag=0x%x mode=%#ho mq_flags=0x%lx mq_maxmsg=%ld "
			"mq_msgsize=%ld mq_curmsgs=%ld",
			context->mq_open.oflag, context->mq_open.mode,
			context->mq_open.attr.mq_flags,
			context->mq_open.attr.mq_maxmsg,
			context->mq_open.attr.mq_msgsize,
			context->mq_open.attr.mq_curmsgs);
		break;
	case AUDIT_MQ_SENDRECV:
		audit_log_format(ab,
			"mqdes=%d msg_len=%zd msg_prio=%u "
			"abs_timeout_sec=%lld abs_timeout_nsec=%ld",
			context->mq_sendrecv.mqdes,
			context->mq_sendrecv.msg_len,
			context->mq_sendrecv.msg_prio,
			(long long) context->mq_sendrecv.abs_timeout.tv_sec,
			context->mq_sendrecv.abs_timeout.tv_nsec);
		break;
	case AUDIT_MQ_NOTIFY:
		audit_log_format(ab, "mqdes=%d sigev_signo=%d",
				context->mq_notify.mqdes,
				context->mq_notify.sigev_signo);
		break;
	case AUDIT_MQ_GETSETATTR: {
		struct mq_attr *attr = &context->mq_getsetattr.mqstat;

		audit_log_format(ab,
			"mqdes=%d mq_flags=0x%lx mq_maxmsg=%ld mq_msgsize=%ld "
			"mq_curmsgs=%ld ",
			context->mq_getsetattr.mqdes,
			attr->mq_flags, attr->mq_maxmsg,
			attr->mq_msgsize, attr->mq_curmsgs);
		break; }
	case AUDIT_CAPSET:
		audit_log_format(ab, "pid=%d", context->capset.pid);
		audit_log_cap(ab, "cap_pi", &context->capset.cap.inheritable);
		audit_log_cap(ab, "cap_pp", &context->capset.cap.permitted);
		audit_log_cap(ab, "cap_pe", &context->capset.cap.effective);
		audit_log_cap(ab, "cap_pa", &context->capset.cap.ambient);
		break;
	case AUDIT_MMAP:
		audit_log_format(ab, "fd=%d flags=0x%x", context->mmap.fd,
				 context->mmap.flags);
		break;
	case AUDIT_OPENAT2:
		audit_log_format(ab, "oflag=0%llo mode=0%llo resolve=0x%llx",
				 context->openat2.flags,
				 context->openat2.mode,
				 context->openat2.resolve);
		break;
	case AUDIT_EXECVE:
		audit_log_execve_info(context, &ab); ✍️
		break;
	case AUDIT_KERN_MODULE:
		audit_log_format(ab, "name=");
		if (context->module.name) {
			audit_log_untrustedstring(ab, context->module.name);
		} else
			audit_log_format(ab, "(null)");

		break;
	case AUDIT_TIME_ADJNTPVAL:
	case AUDIT_TIME_INJOFFSET:
		/* this call deviates from the rest, eating the buffer */
		audit_log_time(context, &ab);
		break;
	}
	audit_log_end(ab);
}
```

✍️ audit_log_execve_info()

```c
static void audit_log_execve_info(struct audit_context *context,
				  struct audit_buffer **ab)
{
	long len_max;
	long len_rem;
	long len_full;
	long len_buf;
	long len_abuf = 0;
	long len_tmp;
	bool require_data;
	bool encode;
	unsigned int iter;
	unsigned int arg;
	char *buf_head;
	char *buf;
	const char __user *p = (const char __user *)current->mm->arg_start;

	/* NOTE: this buffer needs to be large enough to hold all the non-arg
	 *       data we put in the audit record for this argument (see the
	 *       code below) ... at this point in time 96 is plenty */
	char abuf[96];

	/* NOTE: we set MAX_EXECVE_AUDIT_LEN to a rather arbitrary limit, the
	 *       current value of 7500 is not as important as the fact that it
	 *       is less than 8k, a setting of 7500 gives us plenty of wiggle
	 *       room if we go over a little bit in the logging below */
	WARN_ON_ONCE(MAX_EXECVE_AUDIT_LEN > 7500);
	len_max = MAX_EXECVE_AUDIT_LEN;

	/* scratch buffer to hold the userspace args */
	buf_head = kmalloc(MAX_EXECVE_AUDIT_LEN + 1, GFP_KERNEL);
	if (!buf_head) {
		audit_panic("out of memory for argv string");
		return;
	}
	buf = buf_head;

	audit_log_format(*ab, "argc=%d", context->execve.argc);

	len_rem = len_max;
	len_buf = 0;
	len_full = 0;
	require_data = true;
	encode = false;
	iter = 0;
	arg = 0;
	do {
		/* NOTE: we don't ever want to trust this value for anything
		 *       serious, but the audit record format insists we
		 *       provide an argument length for really long arguments,
		 *       e.g. > MAX_EXECVE_AUDIT_LEN, so we have no choice but
		 *       to use strncpy_from_user() to obtain this value for
		 *       recording in the log, although we don't use it
		 *       anywhere here to avoid a double-fetch problem */
		if (len_full == 0)
			len_full = strnlen_user(p, MAX_ARG_STRLEN) - 1;

		/* read more data from userspace */
		if (require_data) {
			/* can we make more room in the buffer? */
			if (buf != buf_head) {
				memmove(buf_head, buf, len_buf);
				buf = buf_head;
			}

			/* fetch as much as we can of the argument */
			len_tmp = strncpy_from_user(&buf_head[len_buf], p,
						    len_max - len_buf);
			if (len_tmp == -EFAULT) {
				/* unable to copy from userspace */
				send_sig(SIGKILL, current, 0);
				goto out;
			} else if (len_tmp == (len_max - len_buf)) {
				/* buffer is not large enough */
				require_data = true;
				/* NOTE: if we are going to span multiple
				 *       buffers force the encoding so we stand
				 *       a chance at a sane len_full value and
				 *       consistent record encoding */
				encode = true;
				len_full = len_full * 2;
				p += len_tmp;
			} else {
				require_data = false;
				if (!encode)
					encode = audit_string_contains_control(
								buf, len_tmp);
				/* try to use a trusted value for len_full */
				if (len_full < len_max)
					len_full = (encode ?
						    len_tmp * 2 : len_tmp);
				p += len_tmp + 1;
			}
			len_buf += len_tmp;
			buf_head[len_buf] = '\0';

			/* length of the buffer in the audit record? */
			len_abuf = (encode ? len_buf * 2 : len_buf + 2);
		}

		/* write as much as we can to the audit log */
		if (len_buf >= 0) {
			/* NOTE: some magic numbers here - basically if we
			 *       can't fit a reasonable amount of data into the
			 *       existing audit buffer, flush it and start with
			 *       a new buffer */
			if ((sizeof(abuf) + 8) > len_rem) {
				len_rem = len_max;
				audit_log_end(*ab);
				*ab = audit_log_start(context,
						      GFP_KERNEL, AUDIT_EXECVE);
				if (!*ab)
					goto out;
			}

			/* create the non-arg portion of the arg record */
			len_tmp = 0;
			if (require_data || (iter > 0) ||
			    ((len_abuf + sizeof(abuf)) > len_rem)) {
				if (iter == 0) {
					len_tmp += snprintf(&abuf[len_tmp],
							sizeof(abuf) - len_tmp,
							" a%d_len=%lu",
							arg, len_full);
				}
				len_tmp += snprintf(&abuf[len_tmp],
						    sizeof(abuf) - len_tmp,
						    " a%d[%d]=", arg, iter++);
			} else
				len_tmp += snprintf(&abuf[len_tmp],
						    sizeof(abuf) - len_tmp,
						    " a%d=", arg);
			WARN_ON(len_tmp >= sizeof(abuf));
			abuf[sizeof(abuf) - 1] = '\0';

			/* log the arg in the audit record */
			audit_log_format(*ab, "%s", abuf);
			len_rem -= len_tmp;
			len_tmp = len_buf;
			if (encode) {
				if (len_abuf > len_rem)
					len_tmp = len_rem / 2; /* encoding */
				audit_log_n_hex(*ab, buf, len_tmp);
				len_rem -= len_tmp * 2;
				len_abuf -= len_tmp * 2;
			} else {
				if (len_abuf > len_rem)
					len_tmp = len_rem - 2; /* quotes */
				audit_log_n_string(*ab, buf, len_tmp);
				len_rem -= len_tmp + 2;
				/* don't subtract the "2" because we still need
				 * to add quotes to the remaining string */
				len_abuf -= len_tmp;
			}
			len_buf -= len_tmp;
			buf += len_tmp;
		}

		/* ready to move to the next argument? */
		if ((len_buf == 0) && !require_data) {
			arg++;
			iter = 0;
			len_full = 0;
			require_data = true;
			encode = false;
		}
	} while (arg < context->execve.argc);

	/* NOTE: the caller handles the final audit_log_end() call */
out:
	kfree(buf_head);
}
```
