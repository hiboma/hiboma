# strace が open(2) の引数を出力する部分を読む

open(2) を呼ぶプロセスを strace を実行すると、下記のように人間に読みやすい表示で出力されます

```c
open("./hello.txt", O_RDWR|O_CREAT|O_TRUNC, 0666) = 3
```

どのように処理されているのか、一部追ってみます。 strace のバージョンは 4.10 です

( strace 自体の仕組みは説明しません。ptrace(2) を使って実現していると思われますが、複雑なのでここで解説は無理です )

## open(2)

インタフェースを確認しておきましょう

```c
int open(const char *pathname, int flags, mode_t mode);
```

## あたりをつけて読み始める

strace のソースを展開するとシステムコールと同名のファイルがいくつか並んでいます。

```
 $ \ls 
AUTHORS        README               chdir.c       depcomp      futex.c            ipc.c     mknod.c        process_vm.c  seccomp.c         strace.spec        tests       utime.c
COPYING        README-linux-ptrace  chmod.c       desc.c       get_robust_list.c  kexec.c   mount.c        ptp.c         signal.c          stream.c           tests-m32   utimes.c
CREDITS        access.c             clone.c       dirent.c     getcpu.c           keyctl.c  mtd.c          ptrace.h      signalent.sh      swapon.c           tests-mx32  v4l2.c
ChangeLog      aclocal.m4           compile       errnoent.sh  getcwd.c           ldt.c     net.c          quota.c       sigreturn.c       sync_file_range.c  time.c      vsprintf.c
ChangeLog-CVS  affinity.c           config.guess  evdev.c      getrandom.c        link.c    open.c         readahead.c   sock.c            syscall.c          truncate.c  wait.c
GPATH          aio.c                config.h.in   execve.c     hostname.c         linux     or1k_atomic.c  readlink.c    socketutils.c     syscallent.sh      uid.c       xattr.c
GRTAGS         bjm.c                config.sub    exit.c       inotify.c          loop.c    pathtrace.c    reboot.c      sram_alloc.c      sysctl.c           uid16.c     xlat
GTAGS          block.c              configure     fadvise.c    install-sh         lseek.c   personality.c  regs.h        statfs.c          sysinfo.c          umask.c     xlate.el
INSTALL        cacheflush.c         configure.ac  fallocate.c  io.c               m4        prctl.c        renameat.c    strace-graph      syslog.c           umount.c
Makefile.am    capability.c         count.c       fanotify.c   ioctl.c            maint     printmode.c    resource.c    strace-log-merge  sysmips.c          uname.c
Makefile.in    caps0.h              debian        fchownat.c   ioctlsort.c        mem.c     printstat.h    sched.c       strace.1          term.c             unwind.c
NEWS           caps1.h              defs.h        file.c       ioprio.c           missing   process.c      scsi.c        strace.c          test-driver        util.c
```

open.c というファイルがあるのでそこから追いかけてみました

## open.c

#### sys_open

いかにもそれっぽい `sys_open` があるのでここから読みます。`decode_open` に続きます

```c
int
sys_open(struct tcb *tcp)
{
	return decode_open(tcp, 0);
}
```

#### decode_open

`struct tcb` はシステムコールを呼び出した時の引数やコンテキストを保持した構造体のようです。

```c
/* Trace Control Block */
struct tcb {
	int flags;		/* See below for TCB_ values */
	int pid;		/* If 0, this tcb is free */
	int qual_flg;		/* qual_flags[scno] or DEFAULT_QUAL_FLAGS + RAW */
	int u_error;		/* Error code */
	long scno;		/* System call number */
	long u_arg[MAX_ARGS];	/* System call arguments */
#if defined(LINUX_MIPSN32) || defined(X32)
	long long ext_arg[MAX_ARGS];
	long long u_lrval;	/* long long return value */
#endif
	long u_rval;		/* Return value */
#if SUPPORTED_PERSONALITIES > 1
	unsigned int currpers;	/* Personality at the time of scno update */
#endif
	int curcol;		/* Output column for this process */
	FILE *outf;		/* Output file for this process */
	const char *auxstr;	/* Auxiliary info from syscall (see RVAL_STR) */
	const struct_sysent *s_ent; /* sysent[scno] or dummy struct for bad scno */
	struct timeval stime;	/* System time usage as of last process wait */
	struct timeval dtime;	/* Delta for system time usage */
	struct timeval etime;	/* Syscall entry time */
				/* Support for tracing forked processes: */
	long inst[2];		/* Saved clone args (badly named) */

#ifdef USE_LIBUNWIND
	struct UPT_info* libunwind_ui;
	struct mmap_cache_t* mmap_cache;
	unsigned int mmap_cache_size;
	unsigned int mmap_cache_generation;
	struct queue_t* queue;
#endif
};
```

`decode_open`に付いている元のソースコメントを参考にしながら追っていくと整合性が取れます。
 
```c
static int
decode_open(struct tcb *tcp, int offset)
{
	if (entering(tcp)) {

		printpath(tcp, tcp->u_arg[offset]); // tcp->u_arg[offset] は open の第1引数 = const chat *pathname 
		tprints(", ");
		/* flags */
		tprint_open_modes(tcp->u_arg[offset + 1]); // tcp->u_arg[offset+1] は open の第2引数 = flags */
		if (tcp->u_arg[offset + 1] & O_CREAT) {
			/* mode */
			tprintf(", %#lo", tcp->u_arg[offset + 2]); // tcp->u_arg[offset+1] は open の第3引数 = mode */
		}
	}
	return RVAL_FD;
}
```

ファイル名を出力する際には `printpath` を呼ぶようです

#### printpath

ソースがややこしくなってきます。私が説明しきれない部分はソースを読んで補ってください ＾＾;

 * `umovestr` で path に文字列をコピーします
   * umovestr は `NULL 終端している場合 1` を返すと 関数のコメント欄にかかれています
 * path にコピーした文字列を `print_quoted_string` で出力します
   * print_quoted_string に `QUOTE_0_TERMINATED` を指定すると `NULL終端の文字列または size-1 バイトの文字列として扱う` と関数のコメント欄に書かれています

open(2) の第一引数であるパスをどういう風に扱うかが見えてきました

```c
/*
 * Print path string specified by address `addr' and length `n'.
 * If path length exceeds `n', append `...' to the output.
 */
void
printpathn(struct tcb *tcp, long addr, unsigned int n)
{
	char path[PATH_MAX + 1];
	int nul_seen;

	if (!addr) {
		tprints("NULL");
		return;
	}

	/* Cap path length to the path buffer size */
	if (n > sizeof path - 1)
		n = sizeof path - 1;

	/* Fetch one byte more to find out whether path length > n. */
    // path にコピーする実装のようです
    // umovestr の実装が複雑ですが、コメントには `Like `umove' but make the additional effort of looking for a terminating zero byte.` とあります
    // \0x00 終端しているかどうかを見つけてくれるようです
	nul_seen = umovestr(tcp, addr, n + 1, path);
	if (nul_seen < 0)
        // path に \0x00 が含まれない場合。アドレスを出して終わり?
		tprintf("%#lx", addr);
	else {
        // path に \0x00 が含まれる場合は、print_quoted_string で print する
        // print_quoted_string のコメントに QUOTE_0_TERMINATED の説明が書いてある
        //
        // > * If QUOTE_0_TERMINATED `style' flag is set,
        // > * treat `str' as a NUL-terminated string and
        // > * quote at most (`size' - 1) bytes.
        //
        // QUOTE_0_TERMINATED を指定すると NUL-終端の文字列または size-1 バイトの文字列として扱うとのことです
		path[n++] = '\0';
		print_quoted_string(path, n, QUOTE_0_TERMINATED);
		if (!nul_seen)
			tprints("...");
	}
}
```

#### umovestr

umovestr` で文字列をコピーします

umovestr は ptrace(2) を使っていたりと複雑なので実装はおいかけませんが、下記のようなコードがあるので NULL が出るとコピーを終えるんだろうと推測できます

```c
				if (memchr(local[0].iov_base, '\0', r))
					return 1;

//...                    

		while (n & (sizeof(long) - 1))
			if (u.x[n++] == '\0')
				return 1;
```

コメント欄にも仕様が書かれているのでここを頼りにします

```c
/*
 * Like `umove' but make the additional effort of looking
 * for a terminating zero byte.
 *
 * Returns < 0 on error, > 0 if NUL was seen,
 * (TODO if useful: return count of bytes including NUL),
 * else 0 if len bytes were read but no NUL byte seen.
 *
 * Note: there is no guarantee we won't overwrite some bytes
 * in laddr[] _after_ terminating NUL (but, of course,
 * we never write past laddr[len-1]).
 */
int
umovestr(struct tcb *tcp, long addr, unsigned int len, char *laddr)
{
#if SIZEOF_LONG == 4
	const unsigned long x01010101 = 0x01010101ul;
	const unsigned long x80808080 = 0x80808080ul;
#elif SIZEOF_LONG == 8
	const unsigned long x01010101 = 0x0101010101010101ul;
	const unsigned long x80808080 = 0x8080808080808080ul;
#else
# error SIZEOF_LONG > 8
#endif

	int pid = tcp->pid;
	unsigned int n, m, nread;
	union {
		unsigned long val;
		char x[sizeof(long)];
	} u;

#if SUPPORTED_PERSONALITIES > 1 && SIZEOF_LONG > 4
	if (current_wordsize < sizeof(addr))
		addr &= (1ul << 8 * current_wordsize) - 1;
#endif

	nread = 0;
	if (!process_vm_readv_not_supported) {
		struct iovec local[1], remote[1];

		local[0].iov_base = laddr;
		remote[0].iov_base = (void*)addr;

		while (len > 0) {
			unsigned int chunk_len;
			unsigned int end_in_page;
			int r;

			/* Don't read kilobytes: most strings are short */
			chunk_len = len;
			if (chunk_len > 256)
				chunk_len = 256;
			/* Don't cross pages. I guess otherwise we can get EFAULT
			 * and fail to notice that terminating NUL lies
			 * in the existing (first) page.
			 * (I hope there aren't arches with pages < 4K)
			 */
			end_in_page = ((addr + chunk_len) & 4095);
			if (chunk_len > end_in_page) /* crosses to the next page */
				chunk_len -= end_in_page;

			local[0].iov_len = remote[0].iov_len = chunk_len;
			r = process_vm_readv(pid, local, 1, remote, 1, 0);
			if (r > 0) {
				if (memchr(local[0].iov_base, '\0', r))
					return 1;
				local[0].iov_base += r;
				remote[0].iov_base += r;
				len -= r;
				nread += r;
				continue;
			}
			switch (errno) {
				case ENOSYS:
					process_vm_readv_not_supported = 1;
					goto vm_readv_didnt_work;
				case ESRCH:
					/* the process is gone */
					return -1;
				case EFAULT: case EIO: case EPERM:
					/* address space is inaccessible */
					if (nread) {
						perror_msg("umovestr: short read (%d < %d) @0x%lx",
							   nread, nread + len, addr);
					}
					return -1;
				default:
					/* all the rest is strange and should be reported */
					perror_msg("process_vm_readv");
					return -1;
			}
		}
		return 0;
	}
 vm_readv_didnt_work:

	if (addr & (sizeof(long) - 1)) {
		/* addr not a multiple of sizeof(long) */
		n = addr & (sizeof(long) - 1);	/* residue */
		addr &= -sizeof(long);		/* aligned address */
		errno = 0;
		u.val = ptrace(PTRACE_PEEKDATA, pid, (char *)addr, 0);
		switch (errno) {
			case 0:
				break;
			case ESRCH: case EINVAL:
				/* these could be seen if the process is gone */
				return -1;
			case EFAULT: case EIO: case EPERM:
				/* address space is inaccessible */
				return -1;
			default:
				/* all the rest is strange and should be reported */
				perror_msg("umovestr: PTRACE_PEEKDATA pid:%d @0x%lx",
					    pid, addr);
				return -1;
		}
		m = MIN(sizeof(long) - n, len);
		memcpy(laddr, &u.x[n], m);
		while (n & (sizeof(long) - 1))
			if (u.x[n++] == '\0')
				return 1;
		addr += sizeof(long);
		laddr += m;
		nread += m;
		len -= m;
	}

	while (len) {
		errno = 0;
		u.val = ptrace(PTRACE_PEEKDATA, pid, (char *)addr, 0);
		switch (errno) {
			case 0:
				break;
			case ESRCH: case EINVAL:
				/* these could be seen if the process is gone */
				return -1;
			case EFAULT: case EIO: case EPERM:
				/* address space is inaccessible */
				if (nread) {
					perror_msg("umovestr: short read (%d < %d) @0x%lx",
						   nread, nread + len, addr - nread);
				}
				return -1;
			default:
				/* all the rest is strange and should be reported */
				perror_msg("umovestr: PTRACE_PEEKDATA pid:%d @0x%lx",
					   pid, addr);
				return -1;
		}
		m = MIN(sizeof(long), len);
		memcpy(laddr, u.x, m);
		/* "If a NUL char exists in this word" */
		if ((u.val - x01010101) & ~u.val & x80808080)
			return 1;
		addr += sizeof(long);
		laddr += m;
		nread += m;
		len -= m;
	}
	return 0;
}
```

#### print_quoted_string

 * QUOTE_0_TERMINATED が指定されていると `str を NULL終端の文字列または size-1 バイトの文字列として扱う` と関数のコメント欄に書かれています
 * 文字列出力関数は `tprints` を使います

open(2) に渡されたパスの扱い方がはっきりしてきました

```c
/*
 * Quote string `str' of length `size' and print the result.
 *
 * If QUOTE_0_TERMINATED `style' flag is set,
 * treat `str' as a NUL-terminated string and
 * quote at most (`size' - 1) bytes.
 *
 * If QUOTE_OMIT_LEADING_TRAILING_QUOTES `style' flag is set,
 * do not add leading and trailing quoting symbols.
 *
 * Returns 0 if QUOTE_0_TERMINATED is set and NUL was seen, 1 otherwise.
 * Note that if QUOTE_0_TERMINATED is not set, always returns 1.
 */
int
print_quoted_string(const char *str, unsigned int size,
		    const unsigned int style)
{
	char *buf;
	char *outstr;
	unsigned int alloc_size;
	int rc;

	if (size && style & QUOTE_0_TERMINATED)
		--size;

    /* alloc で文字列出力用の outstr を割り当てる */
	alloc_size = 4 * size;
	if (alloc_size / 4 != size) {
		error_msg("Out of memory");
		tprints("???");
		return -1;
	}
	alloc_size += 1 + (style & QUOTE_OMIT_LEADING_TRAILING_QUOTES ? 0 : 2);

	if (use_alloca(alloc_size)) {
		outstr = alloca(alloc_size);
		buf = NULL;
	} else {
		outstr = buf = malloc(alloc_size);
		if (!buf) {
			error_msg("Out of memory");
			tprints("???");
			return -1;
		}
	}

    /* outstr をダブルクォートする??? */
	rc = string_quote(str, outstr, size, style);
	tprints(outstr);

	free(buf);
	return rc;
}
```

#### tprints

tprints の実態は [fputs_unlocked](http://linux.die.net/man/3/fgets_unlocked) のようです

```
void
tprints(const char *str)
{
	if (current_tcp) {
		int n = fputs_unlocked(str, current_tcp->outf);
		if (n >= 0) {
			current_tcp->curcol += strlen(str);
			return;
		}
		if (current_tcp->outf != stderr)
			perror_msg("%s", outfname);
	}
}
```

ノンブロッキングになる以外は、文字列の扱いは fputs と同じ挙動でよいのかな?