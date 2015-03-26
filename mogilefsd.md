## Watchdog killing worker

突然だが、queryworker を SIGSTOP してみよう

```sh
sudo kill -STOP `pgrep -f queryworker`
```

すると 親 mogilefsd がこんなログを出して、 子 queryworker を SIGKILL で止める

```
[Fri Mar 27 00:03:14 2015] Watchdog killing worker 13929 (queryworker)
[Fri Mar 27 00:03:14 2015] Child 13929 (queryworker) died: 9 (expected)
[Fri Mar 27 00:03:14 2015] Job queryworker has only 0, wants 1, making 1.
[Fri Mar 27 00:04:20 2015] Watchdog killing worker 14243 (queryworker)
[Fri Mar 27 00:04:20 2015] Child 14243 (queryworker) died: 9 (expected)
[Fri Mar 27 00:04:20 2015] Job queryworker has only 0, wants 1, making 1.
```

#### なんで?

queryworker を strace すると、親 mogilefsd と heartbeat 的なことをやっているのが観測できる。

```
[vagrant@vagrant-centos6 ~]$ sudo strace -p `pgrep -f queryworker`
Process 14311 attached - interrupt to quit
select(16, [14], NULL, NULL, {1, 183274}) = 0 (Timeout)
write(14, ":still_alive\r\n", 14)       = 14
select(16, [14], NULL, NULL, {5, 0})    = 1 (in [14], left {4, 185818})
read(14, ":monitor_has_run\r\n", 1024)  = 18
select(16, [14], NULL, NULL, {5, 0})    = 1 (in [14], left {2, 92906})
read(14, ":monitor_has_run\r\n", 1024)  = 18
select(16, [14], NULL, NULL, {5, 0})    = 0 (Timeout)
write(14, ":still_alive\r\n", 14)       = 14
select(16, [14], NULL, NULL, {5, 0})    = 1 (in [14], left {3, 985254})
read(14, ":monitor_has_run\r\n", 1024)  = 18
select(16, [14], NULL, NULL, {5, 0}^C <unfinished ...>
Process 14311 detached
```

この heartbeart での応答が遅延してしまうと Watchdog = 親 mogilefsd が殺しに来るのだ

下記は 親mogilefsd の Watchdog 発火を strace したものである

```
write(1, "[Fri Mar 27 00:21:11 2015] Watchdog killing worker 15210 (queryworker)\n", 71) = 71
kill(15210, SIGKILL)                    = 0 ★ コロスケ
--- SIGCHLD (Child exited) @ 0 (0) ---
wait4(-1, [{WIFSIGNALED(s) && WTERMSIG(s) == SIGKILL}], WNOHANG, NULL) = 15210
stat("/etc/localtime", {st_mode=S_IFREG|0644, st_size=333, ...}) = 0
write(1, "[Fri Mar 27 00:21:11 2015] Child 15210 (queryworker) died: 9 (expected)\n", 72) = 72
epoll_ctl(6, EPOLL_CTL_DEL, 9, {EPOLLIN|EPOLLERR|EPOLLHUP|0x20, {u32=9, u64=9}}) = 0
wait4(-1, 0x7fff4acf108c, WNOHANG, NULL) = 0
stat("/etc/localtime", {st_mode=S_IFREG|0644, st_size=333, ...}) = 0
write(1, "[Fri Mar 27 00:21:11 2015] Job queryworker has only 0, wants 1, making 1.\n", 74) = 74
rt_sigprocmask(SIG_BLOCK, [INT], NULL, 8) = 0
socketpair(PF_FILE, SOCK_STREAM, 0, [13, 14]) = 0
ioctl(13, SNDCTL_TMR_TIMEBASE or TCGETS, 0x7fff4acf0e50) = -1 EINVAL (Invalid argument)
lseek(13, 0, SEEK_CUR)                  = -1 ESPIPE (Illegal seek)
ioctl(13, SNDCTL_TMR_TIMEBASE or TCGETS, 0x7fff4acf0e50) = -1 EINVAL (Invalid argument)
lseek(13, 0, SEEK_CUR)                  = -1 ESPIPE (Illegal seek)
ioctl(14, SNDCTL_TMR_TIMEBASE or TCGETS, 0x7fff4acf0e50) = -1 EINVAL (Invalid argument)
lseek(14, 0, SEEK_CUR)                  = -1 ESPIPE (Illegal seek)
ioctl(14, SNDCTL_TMR_TIMEBASE or TCGETS, 0x7fff4acf0e50) = -1 EINVAL (Invalid argument)
lseek(14, 0, SEEK_CUR)                  = -1 ESPIPE (Illegal seek)
fcntl(13, F_SETFD, FD_CLOEXEC)          = 0
fcntl(14, F_SETFD, FD_CLOEXEC)          = 0
rt_sigprocmask(SIG_SETMASK, ~[RTMIN RT_1], [INT], 8) = 0
clone(child_stack=0, flags=CLONE_CHILD_CLEARTID|CLONE_CHILD_SETTID|SIGCHLD, child_tidptr=0x7fbcb12b19d0) = 15255 ★ ここで子プロセス作り直し
rt_sigprocmask(SIG_SETMASK, [INT], NULL, 8) = 0
rt_sigprocmask(SIG_UNBLOCK, [INT], NULL, 8) = 0
close(14)                               = 0
```

Watchdog で死んだ queryworker は、mogilefsd から fork(2) して生まれ変わる

```
mogile   28644  0.1  2.4 206092 24804 ?        S    Mar26   0:12  \_ mogilefsd
mogile   28651  0.0  2.1 205960 21928 ?        SN   Mar26   0:02      \_ mogilefsd [fsck]
mogile   13927  0.0  2.1 206084 22440 ?        S    Mar26   0:00      \_ mogilefsd [monitor]
mogile   13928  0.0  2.1 205960 21712 ?        S    Mar26   0:00      \_ mogilefsd [reaper]
mogile   13930  0.0  2.1 206088 22260 ?        S    Mar26   0:00      \_ mogilefsd [delete]
mogile   13931  0.1  2.1 206084 22416 ?        S    Mar26   0:01      \_ mogilefsd [job_master]
mogile   13932  0.0  2.1 205960 21648 ?        S    Mar26   0:00      \_ mogilefsd [replicate]
mogile   14386  0.0  2.1 206092 21552 ?        S    00:06   0:00      \_ mogilefsd [queryworker]
```

#### その他

とある、不具合の原因もこれで分かる。 nice 値に注目

```
F   UID   PID  PPID PRI  NI    VSZ   RSS WCHAN  STAT TTY        TIME COMMAND
4   501 28644 20325   0 -20 206092 24812 ep_pol S<   ?          0:12  \_ mogilefsd                   ★ 
1   501 28651 28644  30  10 205960 21928 hrtime SN   ?          0:02      \_ mogilefsd [fsck]
1   501 13927 28644  20   0 206084 22440 ep_pol S    ?          0:00      \_ mogilefsd [monitor]
1   501 13928 28644  20   0 205960 21712 ep_pol S    ?          0:00      \_ mogilefsd [reaper]
1   501 13930 28644  20   0 206088 22260 hrtime S    ?          0:00      \_ mogilefsd [delete]
1   501 13931 28644  20   0 206084 22416 hrtime S    ?          0:01      \_ mogilefsd [job_master]
1   501 13932 28644  20   0 205960 21648 hrtime S    ?          0:00      \_ mogilefsd [replicate]
1   501 14506 28644   0 -20 206092 21556 poll_s S<   ?          0:00      \_ mogilefsd [queryworker] ★ 親の nice -20 を引き継いだ子プロセス
```
