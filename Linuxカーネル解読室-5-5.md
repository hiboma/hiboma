# プロセス空間へのアクセスと例外テーブル

## 5.5.1 アドレス範囲チェック

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

```c
#define __addr_ok(addr)					\
	((unsigned long __force)(addr) <		\
	 (current_thread_info()->addr_limit.seg))
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