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

### syscall で getpid(2)

```c
#if 0
#!/bin/bash
CFLAGS="-O2 -std=gnu99 -W -Wall -fPIE -D_FORTIFY_SOURCE=2"
o=`basename $0`
o=".${o%.*}"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#define _GNU_SOURCE         /* See feature_test_macros(7) */
#include <unistd.h>
#include <sys/syscall.h>   /* For SYS_xxx definitions */
#include <stdio.h>

int main()
{
	long retval = syscall(39);
	printf("getpid: %ld\n", retval);
	return 0;
}
```

syscall の glibc の実装は次の通り (sysdeps/unix/sysv/linux/x86_64/syscall.S)

```c
/* Copyright (C) 2001, 2003 Free Software Foundation, Inc.
   This file is part of the GNU C Library.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
   02111-1307 USA.  */

#include <sysdep.h>

/* Please consult the file sysdeps/unix/sysv/linux/x86-64/sysdep.h for
   more information about the value -4095 used below.  */

/* Usage: long syscall (syscall_number, arg1, arg2, arg3, arg4, arg5, arg6)
   We need to do some arg shifting, the syscall_number will be in
   rax.  */


        .text
ENTRY (syscall)
        movq %rdi, %rax         /* Syscall number -> rax.  */
        movq %rsi, %rdi         /* shift arg1 - arg5.  */
        movq %rdx, %rsi
        movq %rcx, %rdx
        movq %r8, %r10
        movq %r9, %r8 
        movq 8(%rsp),%r9        /* arg6 is on the stack.  */
        syscall                 /* Do the system call.  */
        cmpq $-4095, %rax       /* Check %rax for error.  */
        jae SYSCALL_ERROR_LABEL /* Jump to error handler if error.  */
L(pseudo_end):
        ret                     /* Return to caller.  */

PSEUDO_END (syscall)
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

2.6.32 ではコードが変わりまくりなので 2.6.15 を読む

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
    # 9. cli で IF = 0 ハードウェア割り込みを無視
	cli				# make sure we don't miss an interrupt
					# setting need_resched or sigpending
					# between sampling and the iret
	movl TI_flags(%ebp), %ecx
	testw $_TIF_ALLWORK_MASK, %cx	# current->work
	jne syscall_exit_work

restore_all:
    # 10. レジスタの復帰
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
    # 13 ユーザモードに復帰
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

#### syscall_table.S

 * システムコールのテーブル
 * 物理メモリ上に連続して並ぶ関数ポインタ群

```asm
.data
ENTRY(sys_call_table)
	.long sys_restart_syscall	/* 0 - old "setup()" system call, used for restarting */
	.long sys_exit
	.long sys_fork
	.long sys_read
	.long sys_write
	.long sys_open		/* 5 */
	.long sys_close
	.long sys_waitpid
	.long sys_creat
	.long sys_link
	.long sys_unlink	/* 10 */
	.long sys_execve
	.long sys_chdir
	.long sys_time
	.long sys_mknod
// ...    
```

#### syscall_exit_work

```asm
syscall_exit_work:
	testb $(_TIF_SYSCALL_TRACE|_TIF_SYSCALL_AUDIT|_TIF_SINGLESTEP), %cl
	jz work_pending
    # IF = 0 ハードウェア割り込み許可
	sti				# could let do_syscall_trace() call
					# schedule() instead
	movl %esp, %eax
	movl $1, %edx
    # ptrace とかあれこれ
	call do_syscall_trace
	jmp resume_userspace
```

#### syscall_badsys

 * eax に ENOSYS 入れる
 * resume_userspace で復帰

```asm
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

do_syscall_trace の ptrace_notify がおもしろそう

