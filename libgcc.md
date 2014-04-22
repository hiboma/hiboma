# libgcc

```
libgcc_s.so.1 must be installed for pthread_cancel to work
```

エラーの場所

```
$ grep -R 'pthread_cancel to work' * 
nptl/sysdeps/pthread/unwind-forcedunwind.c:    __libc_fatal (LIBGCC_S_SO " must be installed for pthread_cancel to work\n");
sysdeps/gnu/unwind-resume.c:    __libc_fatal (LIBGCC_S_SO " must be installed for pthread_cancel to work\n");
sysdeps/unix/sysv/linux/arm/nptl/unwind-forcedunwind.c:    __libc_fatal ("libgcc_s.so.1 must be installed for pthread_cancel to work\n");
sysdeps/unix/sysv/linux/arm/nptl/unwind-resume.c:    __libc_fatal ("libgcc_s.so.1 must be installed for pthread_cancel to work\n");
```

```c
void
__attribute_noinline__
pthread_cancel_init (void)
{
  void *resume;
  void *personality;
  void *forcedunwind;
  void *getcfa;
  void *handle;

  if (__glibc_likely (libgcc_s_handle != NULL))
    {
      /* Force gcc to reload all values.  */
      asm volatile ("" ::: "memory");
      return;
    }

  handle = __libc_dlopen (LIBGCC_S_SO);

  if (handle == NULL
      || (resume = __libc_dlsym (handle, "_Unwind_Resume")) == NULL
      || (personality = __libc_dlsym (handle, "__gcc_personality_v0")) == NULL
      || (forcedunwind = __libc_dlsym (handle, "_Unwind_ForcedUnwind"))
	 == NULL
      || (getcfa = __libc_dlsym (handle, "_Unwind_GetCFA")) == NULL
#ifdef ARCH_CANCEL_INIT
      || ARCH_CANCEL_INIT (handle)
#endif
      )
    __libc_fatal (LIBGCC_S_SO " must be installed for pthread_cancel to work\n");

  PTR_MANGLE (resume);
  libgcc_s_resume = resume;
  PTR_MANGLE (personality);
  libgcc_s_personality = personality;
  PTR_MANGLE (forcedunwind);
  libgcc_s_forcedunwind = forcedunwind;
  PTR_MANGLE (getcfa);
  libgcc_s_getcfa = getcfa;
  /* Make sure libgcc_s_handle is written last.  Otherwise,
     pthread_cancel_init might return early even when the pointer the
     caller is interested in is not initialized yet.  */
  atomic_write_barrier ();
  libgcc_s_handle = handle;
}
```

__libc_message で何かエラーメッセージ出す

```c
void
__libc_fatal (message)
     const char *message;
{
  /* The loop is added only to keep gcc happy.  */
  while (1)
    __libc_message (1, "%s", message);
}
libc_hidden_def (__libc_fatal)
```

 * __libc_secure_getenv, LIBC_FATAL_STDERR_
   * STDERR にログ書く指定かな
 * /dev/tty を open

```c
/* Abort with an error message.  */
void
__libc_message (int do_abort, const char *fmt, ...)
{
  va_list ap;
  int fd = -1;

  va_start (ap, fmt);

#ifdef FATAL_PREPARE
  FATAL_PREPARE;
#endif

  /* Open a descriptor for /dev/tty unless the user explicitly
     requests errors on standard error.  */
  const char *on_2 = __libc_secure_getenv ("LIBC_FATAL_STDERR_");
  if (on_2 == NULL || *on_2 == '\0')
    fd = open_not_cancel_2 (_PATH_TTY, O_RDWR | O_NOCTTY | O_NDELAY);

  if (fd == -1)
    fd = STDERR_FILENO;

  struct str_list *list = NULL;
  int nlist = 0;

  const char *cp = fmt;
  while (*cp != '\0')
    {
      /* Find the next "%s" or the end of the string.  */
      const char *next = cp;
      while (next[0] != '%' || next[1] != 's')
	{
	  next = __strchrnul (next + 1, '%');

	  if (next[0] == '\0')
	    break;
	}

      /* Determine what to print.  */
      const char *str;
      size_t len;
      if (cp[0] == '%' && cp[1] == 's')
	{
	  str = va_arg (ap, const char *);
	  len = strlen (str);
	  cp += 2;
	}
      else
	{
	  str = cp;
	  len = next - cp;
	  cp = next;
	}

      struct str_list *newp = alloca (sizeof (struct str_list));
      newp->str = str;
      newp->len = len;
      newp->next = list;
      list = newp;
      ++nlist;
    }

  bool written = false;
  if (nlist > 0)
    {
      struct iovec *iov = alloca (nlist * sizeof (struct iovec));
      ssize_t total = 0;

      for (int cnt = nlist - 1; cnt >= 0; --cnt)
	{
	  iov[cnt].iov_base = (char *) list->str;
	  iov[cnt].iov_len = list->len;
	  total += list->len;
	  list = list->next;
	}

      written = WRITEV_FOR_FATAL (fd, iov, nlist, total);

      if (do_abort)
	{
	  total = ((total + 1 + GLRO(dl_pagesize) - 1)
		   & ~(GLRO(dl_pagesize) - 1));
	  struct abort_msg_s *buf = __mmap (NULL, total,
					    PROT_READ | PROT_WRITE,
					    MAP_ANON | MAP_PRIVATE, -1, 0);
	  if (__glibc_likely (buf != MAP_FAILED))
	    {
	      buf->size = total;
	      char *wp = buf->msg;
	      for (int cnt = 0; cnt < nlist; ++cnt)
		wp = mempcpy (wp, iov[cnt].iov_base, iov[cnt].iov_len);
	      *wp = '\0';

	      /* We have to free the old buffer since the application might
		 catch the SIGABRT signal.  */
	      struct abort_msg_s *old = atomic_exchange_acq (&__abort_msg,
							     buf);
	      if (old != NULL)
		__munmap (old, old->size);
	    }
	}
    }

  va_end (ap);

  if (do_abort)
    {
      BEFORE_ABORT (do_abort, written, fd);

      /* Kill the application.  */
      abort ();
    }
}
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

