# limits

 * http://www.unix.com/man-page/opensolaris/3head/limits.h/
 * http://libc.blog47.fc2.com/blog-entry-10.html

型の規格の話は難しいなー

```c
#if 0
#!/bin/bash
CFLAGS="-O2 -std=gnu99 -Werror -W -Wall -fPIE -D_FORTIFY_SOURCE=2"
o=`basename $0`
o=".${o%.*}"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#include <stdio.h>
#include <limits.h>

int main()
{
	printf("CHAR_MAX:\t%d\n", CHAR_MAX);
	printf("UCHAR_MAX:\t%d\n", UCHAR_MAX);
	printf("CHAR_MIN:\t%d\n", CHAR_MIN);
	printf("SHRT_MAX:\t%d\n", SHRT_MAX);
	printf("SHRT_MIN:\t%d\n", SHRT_MIN);
	printf("USHRT_MAX:\t%d\n", USHRT_MAX);
	printf("INT_MAX:\t%d\n", INT_MAX);
	printf("INT_MIN:\t%d\n", INT_MIN);
	printf("UINT_MAX:\t%u\n", UINT_MAX);
	printf("LONG_MAX:\t%ld\n", LONG_MAX);
	printf("LONG_MIN:\t%ld\n", LONG_MIN);
	printf("ULONG_MAX:\t%lu\n", ULONG_MAX);
	printf("UULONG_MAX:\t%lld\n", LLONG_MAX);
	return 0;
}
```

