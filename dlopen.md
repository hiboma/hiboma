# dlopen(3)

https://linuxjm.osdn.jp/html/LDP_man-pages/man3/dlsym.3.html

## sample code (1)

```c
#include <stdio.h>
#define _GNU_SOURCE         /* feature_test_macros(7) 参照 */
#include <dlfcn.h>

int main() {

   puts("dlopen");
   void *handle = dlopen("/usr/lib64/libz.so", RTLD_NOW);
   if (!handle) { 
     perror("dlopen");
     return 1;
   }

   puts("dlclose");
   if (dlclose(handle)) { 
     perror("dlopen");
     return 1;
   };

   puts("owari");
}
```

let't strace the sample code

```
write(1, "dlopen\n", 7dlopen
)                 = 7
brk(0)                                  = 0x2202000
brk(0x2223000)                          = 0x2223000
open("/usr/lib64/libz.so", O_RDONLY)    = 3
read(3, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0 !\300\3172\0\0\0@\0\0\0\0\0\0\0\30\\\1\0\0\0\0\0\0\0\0\0@\0008\0\7\0@\0\37\0\36\0\1\0\0\0\5\0\0\0\0\0\0\0\0\0\0\0\0\0\300\3172\0\0\0\0\0\300\3172\0\0\0tD\1\0"..., 832) = 832
fstat(3, {st_dev=makedev(253, 0), st_ino=65130, st_mode=S_IFREG|0755, st_nlink=1, st_uid=0, st_gid=0, st_blksize=4096, st_blocks=184, st_size=91096, st_atime=2016/06/23-15:38:01, st_mtime=2013/02/22-02:00:52, st_ctime=2016/02/19-03:22:35}) = 0
mmap(0x32cfc00000, 2183696, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x32cfc00000
mprotect(0x32cfc15000, 2093056, PROT_NONE) = 0
mmap(0x32cfe14000, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0x14000) = 0x32cfe14000
close(3)                                = 0
mprotect(0x32cfe14000, 4096, PROT_READ) = 0
write(1, "dlclose\n", 8dlclose
)                = 8
munmap(0x32cfc00000, 2183696)           = 0
write(1, "owari\n", 6owari
)                  = 6
exit_group(6)                           = ?
```

 * dlopen(3) calls open(2), read(2) and mmap(2) internally
 * dlclose(3) calls close(2) internally
 * I don't know how symbols are detected/resolved :(

## sample code (2)

```c
#define _GNU_SOURCE         /* feature_test_macros(7) 参照 */
#include <stdio.h>
#include <dlfcn.h>

int main() {
   Dl_info dlip;

   void *handle = dlopen("/usr/lib64/libpng.so", RTLD_LAZY|RTLD_GLOBAL);
   if (!handle) { 
     perror(dlerror());
     return 1;
   }

   void *php = dlsym(handle, "png_write_png"); 
   if (!dladdr(php, &dlip)) { 
     perror(dlerror());
     return 1;
   } 

// 89 typedef struct
// 90 {
// 91   __const char *dli_fname;      /* File name of defining object.  */
// 92   void *dli_fbase;              /* Load address of that object.  */
// 93   __const char *dli_sname;      /* Name of nearest symbol.  */
// 94   void *dli_saddr;              /* Exact value of nearest symbol.  */
// 95 } Dl_info;
   
   printf("handle address: %p\n", handle);
   printf("dli_fname: %s\ndli_fbase: %x\ndli_sname: %s\ndli_saddr: %p\n", dlip.dli_fname, dlip.dli_fbase, dlip.dli_sname, dlip.dli_saddr);
   if (dlclose(handle)) { 
     perror("dlopen");
     return 1;
   };
}
```

```
$ ./a.out
handle address: 0x1f31030
dli_fname: /usr/lib64/libpng.so
dli_fbase: d7000000
dli_sname: png_write_png
dli_saddr: 0x32d7015150
```

## sample code (3)

```c
#define _GNU_SOURCE         /* feature_test_macros(7) 参照 */
#include <stdio.h>
#include <dlfcn.h>

int main() {
   Dl_info dlip;

   void *handle;
   handle = dlopen("/usr/lib64/libpng.so", RTLD_LAZY|RTLD_GLOBAL);
   if (!handle) { 
     perror(dlerror());
     return 1;
   }
   printf("handle address: %p\n", handle);

   handle = dlopen("/usr/lib64/libpng.so", RTLD_LAZY|RTLD_GLOBAL);
   printf("handle address: %p\n", handle);
   if (!handle) { 
     perror(dlerror());
     return 1;
   }   
}
```

```c
$ ./a.out
handle address: 0xbff030
handle address: 0xbff030
```
