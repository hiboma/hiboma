# AcceptMutex

## 2.2.6/core/prefork.c

```c
        /* Lock around "accept", if necessary */
        SAFE_ACCEPT(accept_mutex_on());

        if (num_listensocks == 1) {
            /* There is only one listener record, so refer to that one. */
            lr = ap_listeners;
        }
        else {
            /* multiple listening sockets - need to poll */
            for (;;) {
                apr_int32_t numdesc;
                const apr_pollfd_t *pdesc;

                /* check for termination first so we don't sleep for a while in
                 * poll if already signalled
                 */
                if (one_process && shutdown_pending) {
                    SAFE_ACCEPT(accept_mutex_off());
                    return;
                }
                else if (die_now) {
                    /* In graceful stop/restart; drop the mutex
                     * and terminate the child. */
                    SAFE_ACCEPT(accept_mutex_off());
                    clean_child_exit(0);
                }
                /* timeout == 10 seconds to avoid a hang at graceful restart/stop
                 * caused by the closing of sockets by the signal handler
                 */
                status = apr_pollset_poll(pollset, apr_time_from_sec(10), 
                                          &numdesc, &pdesc);
                if (status != APR_SUCCESS) {
                    if (APR_STATUS_IS_TIMEUP(status) ||
                        APR_STATUS_IS_EINTR(status)) {
                        continue;
                    }
                    /* Single Unix documents select as returning errnos
                     * EBADF, EINTR, and EINVAL... and in none of those
                     * cases does it make sense to continue.  In fact
                     * on Linux 2.0.x we seem to end up with EFAULT
                     * occasionally, and we'd loop forever due to it.
                     */
                    ap_log_error(APLOG_MARK, APLOG_ERR, status,
                                 ap_server_conf, "apr_pollset_poll: (listen)");
                    SAFE_ACCEPT(accept_mutex_off());
                    clean_child_exit(APEXIT_CHILDSICK);
                }

                /* We can always use pdesc[0], but sockets at position N
                 * could end up completely starved of attention in a very
                 * busy server. Therefore, we round-robin across the
                 * returned set of descriptors. While it is possible that
                 * the returned set of descriptors might flip around and
                 * continue to starve some sockets, we happen to know the
                 * internal pollset implementation retains ordering
                 * stability of the sockets. Thus, the round-robin should
                 * ensure that a socket will eventually be serviced.
                 */
                if (last_poll_idx >= numdesc)
                    last_poll_idx = 0;

                /* Grab a listener record from the client_data of the poll
                 * descriptor, and advance our saved index to round-robin
                 * the next fetch.
                 *
                 * ### hmm... this descriptor might have POLLERR rather
                 * ### than POLLIN
                 */
                lr = pdesc[last_poll_idx++].client_data;
                goto got_fd;
            }
        }
    got_fd:
        /* if we accept() something we don't want to die, so we have to
         * defer the exit
         */
        status = lr->accept_func(&csd, lr, ptrans);

        SAFE_ACCEPT(accept_mutex_off());      /* unlock after "accept" */
```

### SAFE_ACCEPT

```c
/* On some architectures it's safe to do unserialized accept()s in the single
 * Listen case.  But it's never safe to do it in the case where there's
 * multiple Listen statements.  Define SINGLE_LISTEN_UNSERIALIZED_ACCEPT
 * when it's safe in the single Listen case.
 */
#ifdef SINGLE_LISTEN_UNSERIALIZED_ACCEPT
#define SAFE_ACCEPT(stmt) do {if (ap_listeners->next) {stmt;}} while(0)
#else
#define SAFE_ACCEPT(stmt) do {stmt;} while(0)
#endif
```

### 2.2.26/core/prefork accept_mutex_on, accept_mutex_off

```c
static void accept_mutex_on(void)
{
    apr_status_t rv = apr_proc_mutex_lock(accept_mutex);
    if (rv != APR_SUCCESS) {
        const char *msg = "couldn't grab the accept mutex";

        if (ap_my_generation !=
            ap_scoreboard_image->global->running_generation) {
            ap_log_error(APLOG_MARK, APLOG_DEBUG, rv, NULL, "%s", msg);
            clean_child_exit(0);
        }
        else {
            ap_log_error(APLOG_MARK, APLOG_EMERG, rv, NULL, "%s", msg);
            exit(APEXIT_CHILDFATAL);
        }
    }
}

static void accept_mutex_off(void)
{
    apr_status_t rv = apr_proc_mutex_unlock(accept_mutex);
    if (rv != APR_SUCCESS) {
        const char *msg = "couldn't release the accept mutex";

        if (ap_my_generation !=
            ap_scoreboard_image->global->running_generation) {
            ap_log_error(APLOG_MARK, APLOG_DEBUG, rv, NULL, "%s", msg);
            /* don't exit here... we have a connection to
             * process, after which point we'll see that the
             * generation changed and we'll exit cleanly
             */
        }
        else {
            ap_log_error(APLOG_MARK, APLOG_EMERG, rv, NULL, "%s", msg);
            exit(APEXIT_CHILDFATAL);
        }
    }
}
```

### 2.2.26/srclib/apr/locks/unix/


```c
APR_DECLARE(apr_status_t) apr_proc_mutex_lock(apr_proc_mutex_t *mutex)
{
    return mutex->meth->acquire(mutex);
}
```

