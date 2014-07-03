
## SIGSEGV と $_siginfo

SIGSEGV を出した際に ***$_siginfo*** を参照すると si_code から **SEGV_MAPERR** なのか **SEGV_ACCERR** なのかとか、アドレスだったりあれこれ取れるのだった

```
(gdb) r
Starting program: /vagrant/a.out 

Program received signal SIGSEGV, Segmentation fault.
0x00000000004004ed in main ()
Missing separate debuginfos, use: debuginfo-install glibc-2.12-1.132.el6.x86_64
(gdb) p $_siginfo
$1 = {si_signo = 11, si_errno = 0, si_code = 2, _sifields = {_pad = {4195832, 0, 0, 0, 0, 0, 30930208, 0, 30866336, 0, 0, 0, 1995, -1, 7, 1, -1792949920, 32767, 4195565, 0, -1792949920, 32767, 0, 0, 30930208, 0, 0, 0}, _kill = {
      si_pid = 4195832, si_uid = 0}, _timer = {si_tid = 4195832, si_overrun = 0, si_sigval = {sival_int = 0, sival_ptr = 0x0}}, _rt = {si_pid = 4195832, si_uid = 0, si_sigval = {sival_int = 0, sival_ptr = 0x0}}, _sigchld = {
      si_pid = 4195832, si_uid = 0, si_status = 0, si_utime = 0, si_stime = 132844231818477568}, _sigfault = {si_addr = 0x4005f8}, _sigpoll = {si_band = 4195832, si_fd = 0}}}
(gdb)

(gdb) x/5s 0x4005f8
0x4005f8 <__dso_handle+8>:	 '@' <repeats 13 times>
0x400606:	 ""
0x400607:	 ""
0x400608:	 "\001\033\003;,"
0x40060e:	 ""
```

 * si_code = 2 で SEGV_ACCERR が原因
 * si_addr = 0x4005f8 が原因のアドレス

と探していける 。ヌルポだと `_sigfault = {si_addr = 0x0}` になる
