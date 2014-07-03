
## SIGSEGV と $_siginfo

SIGSEGV を出した際に ***$_siginfo*** を参照すると si_code から **SEGV_MAPERR** なのか **SEGV_ACCERR** なのかとか、アドレスだったりあれこれ取れるのだった

#### サンプルソース

```
static char *readonly_string = "abcdefghijklmn\n";

int main()
{
	readonly_string[0] = '0';
	return 0;
}
```

#### gdb の実行例

```
(gdb) r
Starting program: /vagrant/a.out 

Program received signal SIGSEGV, Segmentation fault.
0x000000000040047f in main ()
Missing separate debuginfos, use: debuginfo-install glibc-2.12-1.132.el6.x86_64
(gdb) p $_siginfo
$1 = {si_signo = 11, si_errno = 0, si_code = 2, _sifields = {_pad = {4195720, 0, 0, 0, 0, 0, 22880976, 0, 22817632, 0, 0, 0, 2061, -1, 7, 1, -1909095040, 32767, 4195455, 0, 
      -1909095040, 32767, 0, 0, 22880976, 0, 0, 0}, _kill = {si_pid = 4195720, si_uid = 0}, _timer = {si_tid = 4195720, si_overrun = 0, si_sigval = {sival_int = 0, 
        sival_ptr = 0x0}}, _rt = {si_pid = 4195720, si_uid = 0, si_sigval = {sival_int = 0, sival_ptr = 0x0}}, _sigchld = {si_pid = 4195720, si_uid = 0, si_status = 0, 
      si_utime = 0, si_stime = 98273043620560896}, _sigfault = {si_addr = 0x400588}, _sigpoll = {si_band = 4195720, si_fd = 0}}}

(gdb) p $_siginfo.si_code
$5 = 2

(gdb) p $_siginfo._sifields._sigfault.si_addr 
$4 = (void *) 0x400588

(gdb) x/10s $_siginfo._sifields._sigfault.si_addr 
0x400588 <__dso_handle+8>:	 "abcdefghijklmn\n"
0x400598:	 "\001\033\003;$"
0x40059e:	 ""
0x40059f:	 ""
0x4005a0:	 "\003"
0x4005a2:	 ""
0x4005a3:	 ""
0x4005a4:	 "\334\376\377\377@"
0x4005aa:	 ""
0x4005ab:	 ""
```

 * $_siginfo.si_code = 2 で SEGV_ACCERR が原因
 * $_siginfo._sifields._sigfault.si_addr  = 0x4005f8 がフォールトを起こしたアドレス

と探していける 。


ヌルポだと `_sigfault = {si_addr = 0x0}` になる
