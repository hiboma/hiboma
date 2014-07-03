
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

(gdb) info proc mapping
process 2061
cmdline = '/vagrant/a.out'
cwd = '/vagrant'
exe = '/vagrant/a.out'
Mapped address spaces:

          Start Addr           End Addr       Size     Offset objfile
            0x400000           0x401000     0x1000          0                                  /vagrant/a.out
            0x600000           0x601000     0x1000          0                                  /vagrant/a.out
      0x7ffff7a49000     0x7ffff7bd4000   0x18b000          0                        /lib64/libc-2.12.so
      0x7ffff7bd4000     0x7ffff7dd3000   0x1ff000   0x18b000                        /lib64/libc-2.12.so
      0x7ffff7dd3000     0x7ffff7dd7000     0x4000   0x18a000                        /lib64/libc-2.12.so
      0x7ffff7dd7000     0x7ffff7dd8000     0x1000   0x18e000                        /lib64/libc-2.12.so
      0x7ffff7dd8000     0x7ffff7ddd000     0x5000          0        
      0x7ffff7ddd000     0x7ffff7dfd000    0x20000          0                        /lib64/ld-2.12.so
      0x7ffff7ff2000     0x7ffff7ff5000     0x3000          0        
      0x7ffff7ffa000     0x7ffff7ffb000     0x1000          0        
      0x7ffff7ffb000     0x7ffff7ffc000     0x1000          0                           [vdso]
      0x7ffff7ffc000     0x7ffff7ffd000     0x1000    0x1f000                        /lib64/ld-2.12.so
      0x7ffff7ffd000     0x7ffff7ffe000     0x1000    0x20000                        /lib64/ld-2.12.so
      0x7ffff7ffe000     0x7ffff7fff000     0x1000          0        
      0x7ffffffea000     0x7ffffffff000    0x15000          0                           [stack]
  0xffffffffff600000 0xffffffffff601000     0x1000          0                   [vsyscall]
```

 * $_siginfo.si_code = 2 で SEGV_ACCERR が原因
 * $_siginfo._sifields._sigfault.si_addr  = 0x4005f8 がフォールトを起こしたアドレス
 * info proc mapping から、アドレスが mmap されたリージョンが分かる
   * リージョンのパーミッションの表示が無いのだな

と探していける

## ヌルポ

#### サンプルソース

```c
#include <stdlib.h>

static char *null_string = NULL;

int main()
{
	null_string[0] = '0';
	return 0;
}
```

### gdb 実行例

```
Program received signal SIGSEGV, Segmentation fault.
0x000000000040047f in main ()
Missing separate debuginfos, use: debuginfo-install glibc-2.12-1.132.el6.x86_64
(gdb) bt
#0  0x000000000040047f in main ()
(gdb) p p $_siginfo
No symbol table is loaded.  Use the "file" command.
(gdb) p $_siginfo
$1 = {si_signo = 11, si_errno = 0, si_code = 1, _sifields = {_pad = {0, 0, 0, 0, 0, 0, 34542288, 0, 34478944, 0, 0, 0, 2075, -1, 7, 1, -2027080368, 32767, 4195455, 0, -2027080368, 
      32767, 0, 0, 34542288, 0, 0, 0}, _kill = {si_pid = 0, si_uid = 0}, _timer = {si_tid = 0, si_overrun = 0, si_sigval = {sival_int = 0, sival_ptr = 0x0}}, _rt = {si_pid = 0, 
      si_uid = 0, si_sigval = {sival_int = 0, sival_ptr = 0x0}}, _sigchld = {si_pid = 0, si_uid = 0, si_status = 0, si_utime = 0, si_stime = 148357997289013248}, _sigfault = {
      si_addr = 0x0}, _sigpoll = {si_band = 0, si_fd = 0}}}
(gdb) p p $_siginfo.si_code
No symbol table is loaded.  Use the "file" command.
(gdb) p $_siginfo.si_code
$2 = 1
(gdb) p $_siginfo._sifields._sigfault.si_addr 
$3 = (void *) 0x0
```

`_sigfault = {si_addr = 0x0}` になる
