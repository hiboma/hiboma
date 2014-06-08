# 5-2 プロセスからのカーネル呼び出し

## 5.2.1 システムコール呼び出し規約

 * inet     => iret
 * sysenter => sysexit

```asm
;; http://www.tutorialspoint.com/assembly_programming/assembly_system_calls.htm
;; exit(1) と同じ
mov	eax,1		; system call number (sys_exit)
int	0x80		; call kernel
```

```asm
;; http://www.tutorialspoint.com/assembly_programming/assembly_system_calls.htm
;; write(1, msg, 4) と同じ
mov	edx,4		; message length
mov	ecx,msg		; message to write
mov	ebx,1		; file descriptor (stdout)
mov	eax,4		; system call number (sys_write)
int	0x80		; call kernel
```

### int 0x80 で getpid(2)


```c
#if 0
#!/bin/bash
CFLAGS="-O0 -std=gnu99 -W -Wall"
o=`basename $0`
o=".${o%.*}"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#include <stdio.h>

int main()
{
	long rax;

	/* /usr/include/asm/unistd_32.h */
	__asm__(
		"mov $20, %%rax;"
		"int $0x80;"
		"mov %%rax, %0;"
		:"=r"(rax)
		);

	printf("getpid: %ld\n", rax);
	return 0;
}
```