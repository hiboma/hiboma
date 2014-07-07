# プロセス空間へのアクセスと例外テーブル

## 5.5.1 アドレス範囲チェック

アドレスがユーザ空間を差しているかどうかを確認する術についての章

thread_info の addr_limit がプロセスのアクセス可能範囲に使われている

```c
struct thread_info {

//

	mm_segment_t		addr_limit;
```

addr_limit の取りうる値は次の通り
               
 * 32bit では 0x00000000   〜 0xC000000000
 * 62bit では 0x0000000000 〜 0x800000000000 (1 << 47)

addr_limit の設定方法
 
 * set_fs で設定、get_fs で値を取り出す

```c 
#define get_fs()	(current_thread_info()->addr_limit)
#define set_fs(x)	(current_thread_info()->addr_limit = (x))
```

#### addr_limit がどこで設定されるか?

load_elf_binary の中で start_thread が呼ばれ addr_limit が設定される

```c
static int load_elf_binary(struct linux_binprm *bprm, struct pt_regs *regs)
{

//...

	start_thread(regs, elf_entry, bprm->p);
	retval = 0;
```

start_thread の実装。 `set_fs(USER_DS)` として addr_limit をセットしている

```c
void
start_thread(struct pt_regs *regs, unsigned long new_ip, unsigned long new_sp)
{
	loadsegment(fs, 0);
	loadsegment(es, 0);
	loadsegment(ds, 0);
	load_gs_index(0);
	regs->ip		= new_ip;
	regs->sp		= new_sp;
	percpu_write(old_rsp, new_sp);
	regs->cs		= __USER_CS;
	regs->ss		= __USER_DS;
	regs->flags		= 0x200;

    /* ここ */
	set_fs(USER_DS);
	/*
	 * Free the old FP and other extended state
	 */
	free_thread_xstate(current);
}
EXPORT_SYMBOL_GPL(start_thread);
```

USER_DS は下記の通りの定義

```
#define USER_DS 	MAKE_MM_SEG(TASK_SIZE_MAX)


/* 32bit の TASK_SIZE_MAX */
/*
 * User space process size: 3GB (default).
 */
#define TASK_SIZE		PAGE_OFFSET
#define TASK_SIZE_MAX		TASK_SIZE

/* 64 bit の TASK_SIZE_MAX */

/*
 * User space process size. 47bits minus one guard page.
 */
#define TASK_SIZE_MAX	((1UL << 47) - PAGE_SIZE)
```

## __addr_ok マクロ

アドレスが addr_limit 以下になっているか(ユーザ空間のアドレス) どうかをみるマクロ

```c
#define __addr_ok(addr)					\
	((unsigned long __force)(addr) <		\
	 (current_thread_info()->addr_limit.seg))
```

access_ok マクロ

 * x86 では type は使われていない
 * __range_not_ok が 0 ならユーザ空間のアドレスとする

```c
/**
 * access_ok: - Checks if a user space pointer is valid
 * @type: Type of access: %VERIFY_READ or %VERIFY_WRITE.  Note that
 *        %VERIFY_WRITE is a superset of %VERIFY_READ - if it is safe
 *        to write to a block, it is always safe to read from it.
 * @addr: User space pointer to start of block to check
 * @size: Size of block to check
 *
 * Context: User context only.  This function may sleep.
 *
 * Checks if a pointer to a block of memory in user space is valid.
 *
 * Returns true (nonzero) if the memory block may be valid, false (zero)
 * if it is definitely invalid.
 *
 * Note that, depending on architecture, this function probably just
 * checks that the pointer is in the user space range - after calling
 * this function, memory access functions may still return -EFAULT.
 */
#define access_ok(type, addr, size) (likely(__range_not_ok(addr, size) == 0))
```

__range_not_ok は addr + size が addr_limit を超えていないかをみるマクロ

```c
/*
 * Test whether a block of memory is a valid user space address.
 * Returns 0 if the range is valid, nonzero otherwise.
 *
 * This is equivalent to the following test:
 * (u33)addr + (u33)size >= (u33)current->addr_limit.seg (u65 for x86_64)
 *
 * This needs 33-bit (65-bit for x86_64) arithmetic. We have a carry...
 */

#define __range_not_ok(addr, size)					\
({									\
	unsigned long flag, roksum;					\
	__chk_user_ptr(addr);						\
	asm("add %3,%1 ; sbb %0,%0 ; cmp %1,%4 ; sbb $0,%0"		\
	    : "=&r" (flag), "=r" (roksum)				\
	    : "1" (addr), "g" ((long)(size)),				\
	      "rm" (current_thread_info()->addr_limit.seg));		\
	flag;								\
})
```

## 5.5.2 例外テーブルの作成

struct exception_table_entry

```c
struct exception_table_entry {
	unsigned long insn, fixup;
};
```

 * insn 例外(fault) を許可するアドレス
 * fixup 例外発生後に継続して実行するアドレス

## 5.5.2.1 例外テーブルと fixup

```c
int fixup_exception(struct pt_regs *regs)
{
	const struct exception_table_entry *fixup;

//...

    /* ソート済み配列の2分探索 */
	fixup = search_exception_tables(regs->ip);
	if (fixup) {
		/* If fixup is less than 16, it means uaccess error */
		if (fixup->fixup < 16) {
			current_thread_info()->uaccess_err = -EFAULT;
			regs->ip += fixup->fixup;
			return 1;
		}
		regs->ip = fixup->fixup;
		return 1;
	}

	return 0;
}
```

fixup_exception は do_general_protection で呼び出される

 * ユーザモードであれば SIGSEGV を飛ばす
 * カーネルモードであれば fixup_exception で fixup? できないかどうかを試す
 * fixup でかなかったら oops ?

```c
dotraplinkage void __kprobes
do_general_protection(struct pt_regs *regs, long error_code)
{
	struct task_struct *tsk;

	conditional_sti(regs);

	tsk = current;
    /* ユーザモードかどうか */
	if (!user_mode(regs))
		goto gp_in_kernel;

	tsk->thread.error_code = error_code;
	tsk->thread.trap_no = 13;

    /* syslog に出すやつ */
	if (show_unhandled_signals && unhandled_signal(tsk, SIGSEGV) &&
			printk_ratelimit()) {
		printk(KERN_INFO
			"%s[%d] general protection ip:%lx sp:%lx error:%lx",
			tsk->comm, task_pid_nr(tsk),
			regs->ip, regs->sp, error_code);
		print_vma_addr(" in ", regs->ip);
		printk("\n");
	}

	force_sig(SIGSEGV, tsk);
	return;

    /* カーネルモードでの例外ハンドリング */
gp_in_kernel:
	if (fixup_exception(regs))
		return;

    /* fixup できなかった */
	tsk->thread.error_code = error_code;
	tsk->thread.trap_no = 13;
	if (notify_die(DIE_GPF, "general protection fault", regs,
				error_code, 13, SIGSEGV) == NOTIFY_STOP)
		return;
	die("general protection fault", regs, error_code);
```