# int0x80 と sysenter を切り替える vsyscall

vsyscall = virtual system call の略称

 * カーネル空間の実行コードをユーザ空間から参照できる
 * カーネルが指定したアドレスをエントリポイントにしてシステムコールの実行
 * 特権レベルの切り替えが必要ないものは ただの関数呼び出しになる
   * x86_64 の gettimeofday(2), time(2)

## 5.3.2 vsyscall の初期化

VSYSCALL_BASE (OxFFFFE000) に実行用コードが割り当て

```c
// arch/um/sys-i386/asm/elf.h
#define VSYSCALL_BASE vsyscall_ehdr
#define VSYSCALL_END vsyscall_end
```

vsyscall は 上位のアドレスに mmap されている

```c
[hiroya@hiroya002]~% cat /proc/self/maps
00400000-0040b000 r-xp 00000000 fd:00 19163                              /bin/cat
0060a000-0060b000 rw-p 0000a000 fd:00 19163                              /bin/cat
0060b000-0060c000 rw-p 00000000 00:00 0 
0080a000-0080b000 rw-p 0000a000 fd:00 19163                              /bin/cat
00b9d000-00bbe000 rw-p 00000000 00:00 0                                  [heap]
30f4c00000-30f4c20000 r-xp 00000000 fd:00 11579                          /lib64/ld-2.12.so
30f4e1f000-30f4e20000 r--p 0001f000 fd:00 11579                          /lib64/ld-2.12.so
30f4e20000-30f4e21000 rw-p 00020000 fd:00 11579                          /lib64/ld-2.12.so
30f4e21000-30f4e22000 rw-p 00000000 00:00 0 
30f5000000-30f518b000 r-xp 00000000 fd:00 11582                          /lib64/libc-2.12.so
30f518b000-30f538a000 ---p 0018b000 fd:00 11582                          /lib64/libc-2.12.so
30f538a000-30f538e000 r--p 0018a000 fd:00 11582                          /lib64/libc-2.12.so
30f538e000-30f538f000 rw-p 0018e000 fd:00 11582                          /lib64/libc-2.12.so
30f538f000-30f5394000 rw-p 00000000 00:00 0 
7f7d812dc000-7f7d8716c000 r--p 00000000 fd:00 21848                      /usr/lib/locale/locale-archive
7f7d8716c000-7f7d8716f000 rw-p 00000000 00:00 0 
7f7d8717a000-7f7d8717b000 rw-p 00000000 00:00 0 
7fff228a9000-7fff228be000 rw-p 00000000 00:00 0                          [stack]
7fff229ff000-7fff22a00000 r-xp 00000000 00:00 0                          [vdso]
ffffffffff600000-ffffffffff601000 r-xp 00000000 00:00 0                  [vsyscall]
```

vsyscall 呼び出しをあれこれするのは glibc の役割?

----   

## x86_64 の vsyscall_init

 * gettimeofday(2), time(2), vgetcpu(2) のアドレスをごそごそしている

```c
static int __init vsyscall_init(void)
{
	BUG_ON(((unsigned long) &vgettimeofday !=
			VSYSCALL_ADDR(__NR_vgettimeofday)));
	BUG_ON((unsigned long) &vtime != VSYSCALL_ADDR(__NR_vtime));
	BUG_ON((VSYSCALL_ADDR(0) != __fix_to_virt(VSYSCALL_FIRST_PAGE)));
	BUG_ON((unsigned long) &vgetcpu != VSYSCALL_ADDR(__NR_vgetcpu));
#ifdef CONFIG_SYSCTL
	register_sysctl_table(kernel_root_table2);
#endif
	on_each_cpu(cpu_vsyscall_init, NULL, 1);
	hotcpu_notifier(cpu_vsyscall_notifier, 0);
	return 0;
}
```

vsyscall_init で取ったアドレスは下記の関数呼び出しに使われている

 * vtime, vgettimeofday, vgetcpu

time(2)/vtime の実装を追ってみる

```c
/* This will break when the xtime seconds get inaccurate, but that is
 * unlikely */
time_t __vsyscall(1) vtime(time_t *t)
{
	struct timeval tv;
	time_t result;
	if (unlikely(!__vsyscall_gtod_data.sysctl_enabled))
		return time_syscall(t);

    // ->
	vgettimeofday(&tv, NULL);
	result = tv.tv_sec;
	if (t)
		*t = result;
	return result;
}
```

gettimeofday(2) の実装

 * read_seqbegin で複雑だけど gettimeofday を呼び出しているのが肝
 * gettimeofday は インラインアセンブラで呼び出しされてる
 * 前述の通り特権レベルを切り替えないで gettimeofday を呼び出せるということなのだろう

```c
static __always_inline void do_vgettimeofday(struct timeval * tv)
{
	cycle_t now, base, mask, cycle_delta;
	unsigned seq;
	unsigned long mult, shift, nsec;
	cycle_t (*vread)(void);
	do {
		seq = read_seqbegin(&__vsyscall_gtod_data.lock);

		vread = __vsyscall_gtod_data.clock.vread;
		if (unlikely(!__vsyscall_gtod_data.sysctl_enabled || !vread)) {
            // ここで呼び出し
			gettimeofday(tv,NULL);
			return;
		}

		now = vread();
		base = __vsyscall_gtod_data.clock.cycle_last;
		mask = __vsyscall_gtod_data.clock.mask;
		mult = __vsyscall_gtod_data.clock.mult;
		shift = __vsyscall_gtod_data.clock.shift;

		tv->tv_sec = __vsyscall_gtod_data.wall_time_sec;
		nsec = __vsyscall_gtod_data.wall_time_nsec;
	} while (read_seqretry(&__vsyscall_gtod_data.lock, seq));

	/* calculate interval: */
	cycle_delta = (now - base) & mask;
	/* convert to nsecs: */
	nsec += (cycle_delta * mult) >> shift;

	while (nsec >= NSEC_PER_SEC) {
		tv->tv_sec += 1;
		nsec -= NSEC_PER_SEC;
	}
	tv->tv_usec = nsec / NSEC_PER_USEC;
}
```

gettimeofday のインラインアセンブラ

```c
static __always_inline int gettimeofday(struct timeval *tv, struct timezone *tz)
{
	int ret;
	asm volatile("syscall"
		: "=a" (ret)
		: "0" (__NR_gettimeofday),"D" (tv),"S" (tz)
		: __syscall_clobber );
	return ret;
}
```

## vsyscall-sysenter.S

```c
#include <linux/init.h>

__INITDATA

	.globl vsyscall_int80_start, vsyscall_int80_end
vsyscall_int80_start:
	.incbin "arch/i386/kernel/vsyscall-int80.so"
vsyscall_int80_end:

	.globl vsyscall_sysenter_start, vsyscall_sysenter_end
vsyscall_sysenter_start:
	.incbin "arch/i386/kernel/vsyscall-sysenter.so"
vsyscall_sysenter_end:

__FINIT
```

## sysenter_setup

#### 2.6.15

vsyscall 用の struct page を PTE にマップして実行コードを貼付ける

```c
/*
 * These symbols are defined by vsyscall.o to mark the bounds
 * of the ELF DSO images included therein.
 */
extern const char vsyscall_int80_start, vsyscall_int80_end;
extern const char vsyscall_sysenter_start, vsyscall_sysenter_end;

int __init sysenter_setup(void)
{
    /* vsyscall 用のページをあてる */
	void *page = (void *)get_zeroed_page(GFP_ATOMIC);

    /*
     * __pa         => page から物理アドレスを出す
     * __set_fixmap => 固定の PTE?
     */
	__set_fixmap(FIX_VSYSCALL, __pa(page), PAGE_READONLY_EXEC);

    /* sysenter のサポートの有無 */
	if (!boot_cpu_has(X86_FEATURE_SEP)) {
        /* page に int80 を呼び出すコードをコピー  /
		memcpy(page,
		       &vsyscall_int80_start,
		       &vsyscall_int80_end - &vsyscall_int80_start);
		return 0;
	}

    /* sysenter をサポートしている */
	memcpy(page,
	       &vsyscall_sysenter_start,
	       &vsyscall_sysenter_end - &vsyscall_sysenter_start);

	return 0;
}
```

#### CentOS6.5

 * vdso になった
   * http://man7.org/linux/man-pages/man7/vdso.7.html の説明が詳しい
   * getau
 * リロケータブルになっている
   * http://www.atmarkit.co.jp/flinux/rensai/watch2006/watch06b.html

```c
int __init sysenter_setup(void)
{
	void *syscall_page = (void *)get_zeroed_page(GFP_ATOMIC);
	const void *vsyscall;
	size_t vsyscall_len;

	vdso32_pages[0] = virt_to_page(syscall_page);

#ifdef CONFIG_X86_32
	gate_vma_init();
#endif

    /* vdso なるものが追加された */
    // #define	vdso32_syscall()	(boot_cpu_has(X86_FEATURE_SYSCALL32))
    // #define X86_FEATURE_SYSCALL32	(3*32+14) /* "" syscall in ia32 userspace */
	if (vdso32_syscall()) {
		vsyscall = &vdso32_syscall_start;
		vsyscall_len = &vdso32_syscall_end - &vdso32_syscall_start;

    // #define	vdso32_sysenter()	(boot_cpu_has(X86_FEATURE_SYSENTER32))
	} else if (vdso32_sysenter()){
		vsyscall = &vdso32_sysenter_start;
		vsyscall_len = &vdso32_sysenter_end - &vdso32_sysenter_start;
	} else {
		vsyscall = &vdso32_int80_start;
		vsyscall_len = &vdso32_int80_end - &vdso32_int80_start;
	}

	memcpy(syscall_page, vsyscall, vsyscall_len);

    // ELFバイナリとして展開する
	relocate_vdso(syscall_page);

	return 0;
}
```

vdso32_pages は arch_setup_additional_pages でマップされう?

```c
/* Setup a VMA at program startup for the vsyscall page */
int arch_setup_additional_pages(struct linux_binprm *bprm, int uses_interp)
{
	struct mm_struct *mm = current->mm;
	unsigned long addr;
	int ret = 0;
	bool compat;

    /* on/off 切り替えられる。ブートオプションに vdso=0/1/2 */
	if (vdso_enabled == VDSO_DISABLED)
		return 0;

	down_write(&mm->mmap_sem);

	/* Test compat mode once here, in case someone
	   changes it via sysctl */
	compat = (vdso_enabled == VDSO_COMPAT);

	map_compat_vdso(compat);

	if (compat)
		addr = VDSO_HIGH_BASE;
	else {
		addr = get_unmapped_area_prot(NULL, 0, PAGE_SIZE, 0, 0, 1);
		if (IS_ERR_VALUE(addr)) {
			ret = addr;
			goto up_fail;
		}
	}

	current->mm->context.vdso = (void *)addr;

	if (compat_uses_vma || !compat) {
		/*
		 * MAYWRITE to allow gdb to COW and set breakpoints
		 */
		ret = install_special_mapping(mm, addr, PAGE_SIZE,
					      VM_READ|VM_EXEC|
					      VM_MAYREAD|VM_MAYWRITE|VM_MAYEXEC,
					      vdso32_pages);

		if (ret)
			goto up_fail;
	}

	current_thread_info()->sysenter_return =
		VDSO32_SYMBOL(addr, SYSENTER_RETURN);

  up_fail:
	if (ret)
		current->mm->context.vdso = NULL;

	up_write(&mm->mmap_sem);

	return ret;
}
```