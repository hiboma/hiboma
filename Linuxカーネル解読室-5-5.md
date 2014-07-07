# プロセス空間へのアクセスと例外テーブル

## 5.5.1 アドレス範囲チェック

thread_info の addr_limit がプロセスのアクセス可能範囲

```c
struct thread_info {

//

	mm_segment_t		addr_limit;
```
               
 * 32bit では 0x00000000 〜 0xC000000000
 * set_fs で設定、get_fs で値を取り出す

```c 
#define get_fs()	(current_thread_info()->addr_limit)
#define set_fs(x)	(current_thread_info()->addr_limit = (x))
```

load_elf_binary の中で addr_limit が設定される

```c
static int load_elf_binary(struct linux_binprm *bprm, struct pt_regs *regs)
{

//...

	start_thread(regs, elf_entry, bprm->p);
	retval = 0;
```

start_thread の実装。 `set_fs(USER_DS)` で addr_limit のセット

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