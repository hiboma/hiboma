
## USAGE

```c
#include <unistd.h>
#include <asm/page.h> /* to find PAGE_SIZE */
#include <sys/swap.h>
int swapon(const char *path, int swapflags);
int swapoff(const char *path);
```