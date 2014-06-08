# 5-2 プロセスからのカーネル呼び出し

## 5.2.1 システムコール呼び出し規約

 * inet     => iret
 * sysenter => sysexit

```asm
;; http://www.tutorialspoint.com/assembly_programming/assembly_system_calls.htm
;; exit(1) と同じ
mov	eax,1		; system call number (sys_exit)
int	0x80		; call kernel
```

```asm
;; http://www.tutorialspoint.com/assembly_programming/assembly_system_calls.htm
;; write(1, msg, 4) と同じ
mov	edx,4		; message length
mov	ecx,msg		; message to write
mov	ebx,1		; file descriptor (stdout)
mov	eax,4		; system call number (sys_write)
int	0x80		; call kernel
```

### int 0x80 で getpid(2)

```c
#if 0
#!/bin/bash
CFLAGS="-O0 -std=gnu99 -W -Wall"
o=`basename $0`
o=".${o%.*}"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#include <stdio.h>

int main()
{
	long rax;

	/* /usr/include/asm/unistd_32.h */
	__asm__(
		"mov $20, %%rax;"
		"int $0x80;"
		"mov %%rax, %0;"
		:"=r"(rax)
		);

	printf("getpid: %ld\n", rax);
	return 0;
}
```

## 5.2.2 int 0x80/iret によるシステムコール

```asm
# int の時点で
# - SS
# - ESP
# - EFLAGS
# - CS
# - EIP
# が既にレジスタに積まれている
ENTRY(system_call)
    # 2. eax を退避
	pushl %eax			# save orig_eax

    # 3. その他汎用レジスタを pushl で退避
	SAVE_ALL

    # 4. 現在実行中のタスクのスタックを %ebp にセット   
	GET_THREAD_INFO(%ebp)
					# system call tracing in operation / emulation
	/* Note, _TIF_SECCOMP is bit number 8, and so it needs testw and not testb */
	testw $(_TIF_SYSCALL_EMU|_TIF_SYSCALL_TRACE|_TIF_SECCOMP|_TIF_SYSCALL_AUDIT),TI_flags(%ebp)
    # 5. ↑の testw の結果が 0 でないなら ptrace されているのでジャンプ
	jnz syscall_trace_entry

    # 6. eax がシステムコールの最大の番号を超えてたら ENOSYS かえす
	cmpl $(nr_syscalls), %eax
	jae syscall_badsys

    # 7 システムコールテーブルの %eax 番目を call する
syscall_call:
	call *sys_call_table(,%eax,4)

    # 8. システムコールの戻り値を %eax に入れとく
	movl %eax,EAX(%esp)		# store the return value
syscall_exit:
	cli				# make sure we don't miss an interrupt
					# setting need_resched or sigpending
					# between sampling and the iret
	movl TI_flags(%ebp), %ecx
	testw $_TIF_ALLWORK_MASK, %cx	# current->work
	jne syscall_exit_work

restore_all:
	movl EFLAGS(%esp), %eax		# mix EFLAGS, SS and CS
	# Warning: OLDSS(%esp) contains the wrong/random values if we
	# are returning to the kernel.
	# See comments in process.c:copy_thread() for details.
	movb OLDSS(%esp), %ah
	movb CS(%esp), %al
	andl $(VM_MASK | (4 << 8) | 3), %eax
	cmpl $((4 << 8) | 3), %eax
	je ldt_ss			# returning to user-space with LDT SS
restore_nocheck:
	RESTORE_REGS
	addl $4, %esp
1:	iret
.section .fixup,"ax"
iret_exc:
	sti
	pushl $0			# no error code
	pushl $do_iret_error
	jmp error_code
.previous
.section __ex_table,"a"
	.align 4
	.long 1b,iret_exc
.previous
```

#### syscall_badsys

 * eax に ENOSYS 入れる
 * resume_userspace で復帰

```
syscall_badsys:
	movl $-ENOSYS,EAX(%esp)
	jmp resume_userspace
```

#### syscall_trace_entry

do_syscall_trace に移ってデバッギにあれこて通知だすぽい

```asm
syscall_trace_entry:
	movl $-ENOSYS,EAX(%esp)
	movl %esp, %eax
	xorl %edx,%edx
	call do_syscall_trace
	cmpl $0, %eax
	jne resume_userspace		# ret != 0 -> running under PTRACE_SYSEMU,
					# so must skip actual syscall
	movl ORIG_EAX(%esp), %eax
	cmpl $(nr_syscalls), %eax
	jnae syscall_call
	jmp syscall_exit

	# perform syscall exit tracing
	ALIGN
```

