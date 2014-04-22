# libgcc

```
libgcc_s.so.1 must be installed for pthread_cancel to work
```

```
[pid 25224] open("/lib64/libgcc_s.so.1", O_RDONLY) = 3
[pid 25224] read(3, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0\20)\0\0\0\0\0\0"..., 832) = 832
[pid 25224] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] close(3)                    = 0
[pid 25224] open("/lib64/tls/x86_64/libgcc_s.so.1", O_RDONLY) = -1 ENOENT (No such file or directory)
[pid 25224] stat("/lib64/tls/x86_64", 0x7f0f94d9a480) = -1 ENOENT (No such file or directory)
[pid 25224] open("/lib64/tls/libgcc_s.so.1", O_RDONLY) = -1 ENOENT (No such file or directory)
[pid 25224] stat("/lib64/tls", {st_mode=S_IFDIR|0555, st_size=4096, ...}) = 0
[pid 25224] open("/lib64/x86_64/libgcc_s.so.1", O_RDONLY) = -1 ENOENT (No such file or directory)
[pid 25224] stat("/lib64/x86_64", 0x7f0f94d9a480) = -1 ENOENT (No such file or directory)
[pid 25224] open("/lib64/libgcc_s.so.1", O_RDONLY) = 3
[pid 25224] read(3, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0\20)\0\0\0\0\0\0"..., 832) = 832
[pid 25224] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] close(3)                    = 0
[pid 25224] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] munmap(0x7f0f9bf0f000, 40834) = 0
[pid 25224] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] mmap(NULL, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid 25224] open("/dev/tty", O_RDWR|O_NOCTTY|O_NONBLOCK) = 3
[pid 25224] writev(3, [{"libgcc_s.so.1 must be installed "..., 59}], 1libgcc_s.so.1 must be installed for pthread_cancel to work
) = 59
```

```
[vagrant@vagrant-centos65 ~]$ rpm -qi libgcc
Name        : libgcc                       Relocations: (not relocatable)
Version     : 4.4.7                             Vendor: CentOS
Release     : 4.el6                         Build Date: Thu 21 Nov 2013 07:47:41 PM UTC
Install Date: Thu 05 Dec 2013 02:15:53 PM UTC      Build Host: c6b9.bsys.dev.centos.org
Group       : System Environment/Libraries   Source RPM: gcc-4.4.7-4.el6.src.rpm
Size        : 117320                           License: GPLv3+ and GPLv3+ with exceptions and GPLv2+ with exceptions
Signature   : RSA/SHA1, Sun 24 Nov 2013 07:31:56 PM UTC, Key ID 0946fca2c105b9de
Packager    : CentOS BuildSystem <http://bugs.centos.org>
URL         : http://gcc.gnu.org
Summary     : GCC version 4.4 shared support library
Description :
This package contains GCC shared support library which is needed
e.g. for exception handling support.
```

## php --enable-libgcc

```
  --enable-libgcc         Enable explicitly linking against libgcc
```

configure.in の定義

```sh
PHP_ARG_ENABLE(libgcc, whether to explicitly link against libgcc,
[  --enable-libgcc         Enable explicitly linking against libgcc], no, no)

if test "$PHP_LIBGCC" = "yes"; then
  PHP_LIBGCC_LIBPATH(gcc)
  if test -z "$libgcc_libpath"; then
    AC_MSG_ERROR([Cannot locate libgcc. Make sure that gcc is in your path])
  fi
  PHP_ADD_LIBPATH($libgcc_libpath)
  PHP_ADD_LIBRARY(gcc, yes)
fi
```

