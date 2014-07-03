# C の .rodata と .data

`char []` と `char *` の違いについて、#あるある のやつ

 * http://c-faq.com/aryptr/aryptr2.html
 * http://stackoverflow.com/questions/10186765/char-array-vs-char-pointer-in-c

### char *

```c
char string[] = "@@@@@@@@@@@@@";

int main()
{
	return 0;
}
```

string は rodata に配置されている

```
$ objdump -s -j .rodata ./a.out 

./a.out:     file format elf64-x86-64

Contents of section .rodata:
 400568 01000200 00000000 00000000 00000000  ................
 400578 40404040 40404040 40404040 4000      @@@@@@@@@@@@@.
```

data は特にない

```
$ objdump -s -j .data ./a.out 

./a.out:     file format elf64-x86-64

Contents of section .data:
 600810 00000000 00000000 78054000 00000000  ........x.@.....
```

### char []

```c
char string[] = "@@@@@@@@@@@@@";

int main()
{
	return 0;
}
```

rodata には何も無い

``` 
$ objdump -s -j .rodata ./a.out 

./a.out:     file format elf64-x86-64

Contents of section .rodata:
 400568 01000200 00000000 00000000 00000000  ................
```

string は .data に配置されている

```
$ objdump -s -j .data ./a.out 

./a.out:     file format elf64-x86-64

Contents of section .data:
 600800 00000000 40404040 40404040 40404040  ....@@@@@@@@@@@@
 600810 40000000                             @...
```

rodata のデータは書き込み権限の無いメモリリージョンに配置されるので、変更を加えようとすると SIGSEGV を出す

#### おまけ

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

と探していける 
