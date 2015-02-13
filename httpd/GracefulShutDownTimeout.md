# GracefulShutDownTimeout

http://httpd.apache.org/docs/2.2/ja/mod/mpm_common.html

```
 GracefulShutdownTimeout には サーバーが "graceful-stop" シグナルを受け取ってから現在の リクエストの処理を最大で何秒間続けるかを指定します。
この値をゼロに設定すると、処理中として残っているリクエストが 全て完了するまでサーバーは終了しません。
```

## httpd.2.2

server/mpm/worker/worker.c

```c
1805         /* Don't really exit until each child has finished */
1806         shutdown_pending = 0;
1807         do {
1808             /* Pause for a second */
1809             apr_sleep(apr_time_from_sec(1));
1810 
1811             /* Relieve any children which have now exited */
1812             ap_relieve_child_processes();
1813 
1814             active_children = 0;
1815             for (index = 0; index < ap_daemons_limit; ++index) {
1816                 if (ap_mpm_safe_kill(MPM_CHILD_PID(index), 0) == APR_SUCCESS) {
1817                     active_children = 1;
1818                     /* Having just one child is enough to stay around */
1819                     break;
1820                 }
1821             }
1822         } while (!shutdown_pending && active_children &&
1823                  (!ap_graceful_shutdown_timeout || apr_time_now() < cutoff));
```

## httpd 2.0

実装されていない

```
1687     if (shutdown_pending) {
1688         /* Time to gracefully shut down:
1689          * Kill child processes, tell them to call child_exit, etc...
1690          * (By "gracefully" we don't mean graceful in the same sense as 
1691          * "apachectl graceful" where we allow old connections to finish.)
1692          */
1693         ap_mpm_pod_killpg(pod, ap_daemons_limit, FALSE);
1694         ap_reclaim_child_processes(1);                /* Start with SIGTERM */
1695 
1696         if (!child_fatal) {
1697             /* cleanup pid file on normal shutdown */
1698             const char *pidfile = NULL;
1699             pidfile = ap_server_root_relative (pconf, ap_pid_fname);
1700             if ( pidfile != NULL && unlink(pidfile) == 0)
1701                 ap_log_error(APLOG_MARK, APLOG_INFO, 0,
1702                              ap_server_conf,
1703                              "removed PID file %s (pid=%ld)",
1704                              pidfile, (long)getpid());
1705 
1706             ap_log_error(APLOG_MARK, APLOG_NOTICE, 0,
1707                          ap_server_conf, "caught SIGTERM, shutting down");
1708         }
1709         return 1;

....

1726    
1727     if (is_graceful) {
1728         ap_log_error(APLOG_MARK, APLOG_NOTICE, 0, ap_server_conf,
1729                      AP_SIG_GRACEFUL_STRING " received.  Doing graceful restart");
1730         /* wake up the children...time to die.  But we'll have more soon */
1731         ap_mpm_pod_killpg(pod, ap_daemons_limit, TRUE);
```