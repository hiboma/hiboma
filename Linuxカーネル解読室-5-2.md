# 5-2 プロセスからのカーネル呼び出し

## 5.2.1 システムコール呼び出し規約

 * inet     => iret
 * sysenter => sysexit

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