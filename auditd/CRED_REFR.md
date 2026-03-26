# CRED_REFR

```
type=CRED_REFR msg=audit(1727849821.073:1873): pid=25155 uid=0 auid=0 ses=135 subj=unconfined msg='op=PAM:setcred grantors=pam_permit,pam_cap acct="root" exe="/usr/sbin/cron" hostname=? addr=? terminal=cron res=success'UID="root" AUID="root"
```

lib/audit-records.h
64:#define AUDIT_CRED_REFR         1110    /* User credential refreshed */

lib/msg_typetab.h
_S(AUDIT_CRED_REFR,                  "CRED_REFR"                     )

[Linux-PAM/libpam/pam_audit.c at 60e9641fa47bebcec10b94dee92f8257c09eb45d · Distrotech/Linux-PAM](https://github.com/Distrotech/Linux-PAM/blob/60e9641fa47bebcec10b94dee92f8257c09eb45d/libpam/pam_audit.c#L120)

```
  case PAM_SETCRED:
    message = "setcred";
    if (flags & PAM_ESTABLISH_CRED)
	type = AUDIT_CRED_ACQ;
    else if ((flags & PAM_REINITIALIZE_CRED) || (flags & PAM_REFRESH_CRED))
	type = AUDIT_CRED_REFR;
    else if (flags & PAM_DELETE_CRED)
	type = AUDIT_CRED_DISP;
    else
        type = AUDIT_USER_ERR;
    break;
```

[pam_setcred(3) - Linux manual page](https://man7.org/linux/man-pages/man3/pam_setcred.3.html)

# 派生で調べ物

## [audit_open(3) - Linux manual page](https://man7.org/linux/man-pages/man3/audit_open.3.html)

```
       #include <libaudit.h>

       int audit_open(void);
```

> audit_open creates a NETLINK_AUDIT socket for communication withthe kernel part of the Linux Audit Subsystem. The audit systemuses the ACK feature of netlink. This means that every message tothe kernel will return a netlink status packet even if theoperation succeeds.

## [audit_log_acct_message(3) - Linux manual page](https://man7.org/linux/man-pages/man3/audit_log_acct_message.3.html)


```
       This function will log a message to the audit system using a
       predefined message format. It should be used for all account
       manipulation operations. The function parameters are as follows:

              audit_fd - The fd returned by audit_open

              type - type of message: AUDIT_USER_CHAUTHTOK for changing
              any account attributes.

              pgname - program's name, if NULL will attempt to figure
              out

              op  -  operation. Ex: "adding-user", "changing-finger-
              info", "deleting-group". This value should have a dash or
              underscore between the words so that report parsers group
              them together.

              name - user's account or group name. If not available use
              NULL.

              id  -  uid or gid that the operation is being performed
              on. If the user is unknown, pass a -1 and fill in the name
              parameter. This is used only when user is NULL.

              host - The hostname if known. If not available pass a
              NULL.

              addr - The network address of the user. If not available
              pass a NULL.

              tty  - The tty of the user, if NULL will attempt to figure
              out

              result - 1 is "success" and 0 is "failed"
```
