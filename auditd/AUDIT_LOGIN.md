# AUDIT_LOGIN ( type=LOGIN ) 

/proc/self/loginuid に write すると記録されるイベント

```
type=LOGIN msg=audit(1727786101.781:162): pid=4232 uid=0 subj=unconfined old-auid=4294967295 auid=0 tty=(none) old-ses=4294967295 ses=3 res=1UID="root" OLD-AUID="unset" AUID="root"
```

## include/uapi/linux/audit.h

AUDIT_LOGIN 定数から追いかけていく。


```c
#define AUDIT_LOGIN             1006    /* Define the login id and information */
```

AUDIT_LOGIN は audit_set_loginuid() で登場する (後述)。ユーザランドがら追う場合は /proc/self/loginuid の実装から潜っていくのがいいか

```
USERLAND

----- /proc/self/loginuid ------------------

システムコール や VFS のレイヤは省略

-> proc_loginuid_write
  -> audit_set_loginuid
  .. audit_set_loginuid_perm
   -> audit_log_set_loginuid // AUDIT_LOGIN
```

### /proc/self/loginuid

```
$ ls -hal /proc/self/loginuid 
-rw-r--r-- 1 hiboma hiboma 0 Oct  1 22:33 /proc/self/loginuid
```

fs/proc/base.c に loginuid の定義がある

```
REG("loginuid",  S_IWUSR|S_IRUGO, proc_loginuid_operations),
```

loginuid の file_operations は下記の通り

```
static const struct file_operations proc_loginuid_operations = {
        .read           = proc_loginuid_read,
        .write          = proc_loginuid_write,
        .llseek         = generic_file_llseek,
};
```

proc_loginuid_write 以下に潜っていく

### proc_loginuid_write()

procfs レイヤと audit のレイヤを橋渡しするような役割になっている。write されたバッファから loginuid を読み取る。

```c
static ssize_t proc_loginuid_write(struct file * file, const char __user * buf,
				   size_t count, loff_t *ppos)
{
	struct inode * inode = file_inode(file);
	uid_t loginuid;
	kuid_t kloginuid;
	int rv;

	/* Don't let kthreads write their own loginuid */
	if (current->flags & PF_KTHREAD)
		return -EPERM;

	rcu_read_lock();
	if (current != pid_task(proc_pid(inode), PIDTYPE_PID)) {
		rcu_read_unlock();
		return -EPERM;
	}
	rcu_read_unlock();

	if (*ppos != 0) {
		/* No partial writes. */
		return -EINVAL;
	}

	rv = kstrtou32_from_user(buf, count, 10, &loginuid);
	if (rv < 0)
		return rv;

	/* is userspace tring to explicitly UNSET the loginuid? */
	if (loginuid == AUDIT_UID_UNSET) {
		kloginuid = INVALID_UID;
	} else {
		kloginuid = make_kuid(file->f_cred->user_ns, loginuid);
		if (!uid_valid(kloginuid))
			return -EINVAL;
	}

	rv = audit_set_loginuid(kloginuid); ⬇️
	if (rv < 0)
		return rv;
	return count;
}
```

### audit_set_loginuid()

 * 権限の確認
 * sessionid の生成
 * current->sessionid をセット
 * current->logind をセット

```c
/**
 * audit_set_loginuid - set current task's loginuid
 * @loginuid: loginuid value
 *
 * Returns 0.
 *
 * Called (set) from fs/proc/base.c::proc_loginuid_write().
 */
int audit_set_loginuid(kuid_t loginuid)
{
	unsigned int oldsessionid, sessionid = AUDIT_SID_UNSET;
	kuid_t oldloginuid;
	int rc;

	oldloginuid = audit_get_loginuid(current); ✍️
	oldsessionid = audit_get_sessionid(current); ✍️

	rc = audit_set_loginuid_perm(loginuid); ✍️
	if (rc)
		goto out;

	/* are we setting or clearing? */
	if (uid_valid(loginuid)) {
		sessionid = (unsigned int)atomic_inc_return(&session_id); ✍️
		if (unlikely(sessionid == AUDIT_SID_UNSET))
			sessionid = (unsigned int)atomic_inc_return(&session_id);
	}

	current->sessionid = sessionid;
	current->loginuid = loginuid;
out:
	audit_log_set_loginuid(oldloginuid, loginuid, oldsessionid, sessionid, rc); ⬇️
	return rc;
}
```

✍️ audit_get_sessionid, audit_get_sessionid はインライン関数

```
static inline kuid_t audit_get_loginuid(struct task_struct *tsk)
{
        return tsk->loginuid;
}

static inline unsigned int audit_get_sessionid(struct task_struct *tsk)
{
        return tsk->sessionid;
}
```

✍️ audit_set_loginuid_perm は 権限の確認を入れている。値がセットされてなければ権限が必要ない。

 * AUDIT_FEATURE_LOGINUID_IMMUTABLE
 * CAP_AUDIT_CONTROL
 * AUDIT_FEATURE_ONLY_UNSET_LOGINUID

```c
static int audit_set_loginuid_perm(kuid_t loginuid)
{
	/* if we are unset, we don't need privs */
	if (!audit_loginuid_set(current))
		return 0;
	/* if AUDIT_FEATURE_LOGINUID_IMMUTABLE means never ever allow a change*/
	if (is_audit_feature_set(AUDIT_FEATURE_LOGINUID_IMMUTABLE))
		return -EPERM;
	/* it is set, you need permission */
	if (!capable(CAP_AUDIT_CONTROL))
		return -EPERM;
	/* reject if this is not an unset and we don't allow that */
	if (is_audit_feature_set(AUDIT_FEATURE_ONLY_UNSET_LOGINUID)
				 && uid_valid(loginuid))
		return -EPERM;
	return 0;
}
```

✍️ session_id は static atomic_t で管理されてる

```
/* global counter which is incremented every time something logs in */
static atomic_t session_id = ATOMIC_INIT(0);
```

### audit_log_set_loginuid()

audit_log_start() 〜 audit_log_format 〜 audit_log_end() で audit_buffer バッファに文字列を書き込んでいく。バッファを扱う実装は複雑なので、別記する

```c
static void audit_log_set_loginuid(kuid_t koldloginuid, kuid_t kloginuid,
				   unsigned int oldsessionid,
				   unsigned int sessionid, int rc)
{
	struct audit_buffer *ab;
	uid_t uid, oldloginuid, loginuid;
	struct tty_struct *tty;

	if (!audit_enabled)
		return;

err	ab = audit_log_start(audit_context(), GFP_KERNEL, AUDIT_LOGIN);
	if (!ab)
		return;

	uid = from_kuid(&init_user_ns, task_uid(current));
	oldloginuid = from_kuid(&init_user_ns, koldloginuid);
	loginuid = from_kuid(&init_user_ns, kloginuid);
	tty = audit_get_tty();

	audit_log_format(ab, "pid=%d uid=%u", task_tgid_nr(current), uid);
	audit_log_task_context(ab);
	audit_log_format(ab, " old-auid=%u auid=%u tty=%s old-ses=%u ses=%u res=%d",
			 oldloginuid, loginuid, tty ? tty_name(tty) : "(none)",
			 oldsessionid, sessionid, !rc);
	audit_put_tty(tty);
	audit_log_end(ab);
}
```

# 派生で調べ物

## [pam_loginuid(8) - Linux manual page](https://www.man7.org/linux/man-pages/man8/pam_loginuid.8.html)

> The pam_loginuid module sets the loginuid process attribute forthe process that was authenticated. This is necessary forapplications to be correctly audited. This PAM module should onlybe used for entry point applications like: login, sshd, gdm,vsftpd, crond and atd. There are probably other entry pointapplications besides these. You should not use it forapplications like sudo or su as that defeats the purpose bychanging the loginuid to the account they just switched to.


```
root@develop-hiboma:~# grep -R pam_loginuid /etc/
/etc/pam.d/login:session    required     pam_loginuid.so
/etc/pam.d/cron:session    required     pam_loginuid.so
/etc/pam.d/sshd:session    required     pam_loginuid.so
```

## [kernel.org/doc/Documentation/ABI/stable/procfs-audit_loginuid](https://www.kernel.org/doc/Documentation/ABI/stable/procfs-audit_loginuid)

 * AUDIT_FEATURE_LOGINUID_IMMUTABLE
 * AUDIT_FEATURE_ONLY_UNSET_LOGINUID

```
What:		Audit Login UID
Date:		2005-02-01
KernelVersion:	2.6.11-rc2 1e2d1492e178 ("[PATCH] audit: handle loginuid through proc")
Contact:	linux-audit@redhat.com
Users:		audit and login applications
Description:
		The /proc/$pid/loginuid pseudofile is written to set and
		read to get the audit login UID of process $pid as a
		decimal unsigned int (%u, u32).  If it is unset,
		permissions are not needed to set it.  The accessor must
		have CAP_AUDIT_CONTROL in the initial user namespace to
		write it if it has been set.  It cannot be written again
		if AUDIT_FEATURE_LOGINUID_IMMUTABLE is enabled.  It
		cannot be unset if AUDIT_FEATURE_ONLY_UNSET_LOGINUID is
		enabled.

What:		Audit Login Session ID
Date:		2008-03-13
KernelVersion:	2.6.25-rc7 1e0bd7550ea9 ("[PATCH] export sessionid alongside the loginuid in procfs")
Contact:	linux-audit@redhat.com
Users:		audit and login applications
Description:
		The /proc/$pid/sessionid pseudofile is read to get the
		audit login session ID of process $pid as a decimal
		unsigned int (%u, u32).  It is set automatically,
		serially assigned with each new login.
```

## [CAP_AUDIT_CONTROL](https://man7.org/linux/man-pages/man7/capabilities.7.html)

```
       CAP_AUDIT_CONTROL (since Linux 2.6.11)
              Enable and disable kernel auditing; change auditing filter
              rules; retrieve auditing status and filtering rules.
```

一般ユーザで write しようとすると EPERM を返す

```
hiboma@pcamp-develop-hiboma:~$ echo 1000 > /proc/self/loginuid 
-bash: echo: write error: Operation not permitted
```
