# Linux 0.0.1

 * __asm__ インラインアセンブラ
  * http://www.sci10.org/on_gcc_asm.html

## システムコール呼び出し

 * set_system_gate(0x80,&system_call); で割り込みベクタの初期化
 * int 0x80 でのシステムコール呼び出しのソフトウェア割り込み、
  * eax にシステムコール番号、ebx, ecx, edx に引数 をセットして割り込みする
  * 必要に応じて スケジューリングする
  * eax に返り値をセット
  * シグナルを受けていた場合はシグナルハンドラを呼び出し
 * iret で割り込みからの復帰

### 詳細

 * main -> sched_init() で int 0x80 を trap してシステムコール呼び出しに入る様に設定している

   set_system_gate(0x80,&system_call);

 * 呼び出しのアセンブラ部分
 
    bad_sys_call:
    	movl $-1,%eax  // -ENOSYS
    	iret
    .align 2
    reschedule:
    	pushl $ret_from_sys_call
    	jmp _schedule
    .align 2
    
    // kernel/system_call.s
    _system_call:
    	cmpl $nr_system_calls-1,%eax  // (eaxレジスタの番号 - システムコール番号の最大値) を比較
    	ja bad_sys_call               // 実装されないシステムコール呼び出しだぞー
    	push %ds       // データセグメントをスタックに退避
    	push %es       //
    	push %fs       //
    	pushl %edx                                           // 引数 3 
    	pushl %ecx		# push %ebx,%ecx,%edx as parameters  // 引数 2 
    	pushl %ebx		# to the system call                 // 引数 1 
    	movl $0x10,%edx		# set up ds,es to kernel space
    	mov %dx,%ds
    	mov %dx,%es
    	movl $0x17,%edx		# fs points to local data space
    	mov %dx,%fs
    	call _sys_call_table(,%eax,4) // システムコールテーブルで%eax番目の関数にディスパッチする

    	pushl %eax                    // 退避 ( rescheduleしたりするので、システムコール呼び出しの際のレジスタを一旦退避するのだろう)
    	movl _current,%eax            // current = task struct ?
    	cmpl $0,state(%eax)		      // task_struc->state をみてるのかな
    	jne reschedule                // 0 = runnable でなければ reschedule
    	cmpl $0,counter(%eax)		  // task_struct->counter == 0 なら
    	je reschedule                 // 再スケジューリング

 * システムコールから復帰の部分 
   * int 0x80 で割り込んでいるので、割り込みからの復帰 iret が必要

    ret_from_sys_call:
    	movl _current,%eax		# task[0] cannot have signals
    	cmpl _task,%eax         // task[0] -> init ? カーネルスレッド ? 
    	je 3f                   // シグナル処理をすっとばして 3 に行く

    	movl CS(%esp),%ebx		# was old code segment supervisor
    	testl $3,%ebx			# mode? If so - don't check signals
    	je 3f
    	cmpw $0x17,OLDSS(%esp)		# was stack segment = 0x17 ?
    	jne 3f
    // シグナルハンドラの呼び出し
    2:	movl signal(%eax),%ebx		# signals (bitmap, 32 signals)
    	bsfl %ebx,%ecx			# %ecx is signal nr, return if none
    	je 3f                   # シグナルを受信してなかったら 3 

    	btrl %ecx,%ebx			# clear it
    	movl %ebx,signal(%eax)
    	movl sig_fn(%eax,%ecx,4),%ebx	# %ebx is signal handler address
    	cmpl $1,%ebx
    	jb default_signal		# 0 is default signal handler - exit
    	je 2b				# 1 is ignore - find next signal
    	movl $0,sig_fn(%eax,%ecx,4)	# reset signal handler address
    	incl %ecx
    	xchgl %ebx,EIP(%esp)		# put new return address on stack
    	subl $28,OLDESP(%esp)
    	movl OLDESP(%esp),%edx		# push old return address on stack
    	pushl %eax			# but first check that it's ok.
    	pushl %ecx
    	pushl $28
    	pushl %edx
    	call _verify_area
    	popl %edx
    	addl $4,%esp
    	popl %ecx
    	popl %eax
    	movl restorer(%eax),%eax
    	movl %eax,%fs:(%edx)		# flag/reg restorer
    	movl %ecx,%fs:4(%edx)		# signal nr
    	movl EAX(%esp),%eax
    	movl %eax,%fs:8(%edx)		# old eax
    	movl ECX(%esp),%eax
    	movl %eax,%fs:12(%edx)		# old ecx
    	movl EDX(%esp),%eax
    	movl %eax,%fs:16(%edx)		# old edx
    	movl EFLAGS(%esp),%eax
    	movl %eax,%fs:20(%edx)		# old eflags
    	movl %ebx,%fs:24(%edx)		# old return addr

    3:	popl %eax                   // 退避してたレジスタを元に戻して、プロセス側のコンテキストに iret で戻る
    	popl %ebx
    	popl %ecx
    	popl %edx
    	pop %fs
    	pop %es
    	pop %ds
    	iret                       // 割り込みからの復帰


## buffer

 * getblk
 * brelse
 * bread
 * ll_rw_block

## 4.3 例外および割り込み処理のネスト

 * カーネル実行パス

> Linuxの設計では、CPUが割り込みに関連した実行パスを実行中には、プロセスを切り替えることを許していません

割り込みコンテキストではスケジューリングできない

 * カーネル実行パスによって、`優先度レベルがない割り込みモデルを実現できます`
   * 6th, 4.3BSD では割り込みの優先度を利用していた。優先度が無いとシンプルで移植しやすいらしい

## 例外、割り込み

Intel のドキュメントによる区分

 * 同期割り込み
   * `例外`
     * プロセッサが検出する例外。プロセスが起こす。
     * ハンドリングの仕方が三つある
       * フォルト => 例外を起こした命令からやり直しする (ページフォルト、セグメンテーションフォルト)
         * やり直しできるかどうかは OS のハンドリングしだいだな。
         * 4.3BSD本では `traps can also occur because of a page fault` という書き方をしている
       * トラップ => 例外を起こした命令の次から再会する
       * アボート => 例外を起こした命令で止める
     * ソフトウェアが生成する例外
       * ソフトウェア割り込み => int, int3
       * トラップとして処理される (ユーザーモード->カーネルモードへの切り替え)
 * 非同期割り込み
   * `割り込み`
     * タイマー、I/Oデバイスが発行する。カーネル実行パス(非プロセス)
       * 割り込みはネストできるように書く
     * I/Oを発行したプロセスとは関係なく割り込み => 故に非同期
     * マスク可能割り込み
     * ノンマスカブル割り込み

## スケジューラ、コンテキストスイッチ

 * スケジューラ
   * priority, single-level queue, round-robin

    void schedule(void)
    {
    	int i,next,c;
    	struct task_struct ** p;
    
    /* check alarm, wake up any interruptible tasks that have got a signal */

        // 全プロセス線形サーチ。64プロセスが上限だったらしい
    	for(p = &LAST_TASK ; p > &FIRST_TASK ; --p)
    		if (*p) {
                // alarm(2) の時間超えたかどうかの判定
    			if ((*p)->alarm && (*p)->alarm < jiffies) {
    					(*p)->signal |= (1<<(SIGALRM-1));
    					(*p)->alarm = 0;
    				}
                // シグナル受けた場合。 TASK_RUNNING になるのね。
    			if ((*p)->signal && (*p)->state==TASK_INTERRUPTIBLE)
    				(*p)->state=TASK_RUNNING;
    		}

    /* this is the scheduler proper: */

    	while (1) {
    		c = -1;
    		next = 0;
    		i = NR_TASKS;
    		p = &task[NR_TASKS];
    		while (--i) {
    			if (!*--p)
    				continue;
                // c が MAXのを探す => 次のプロセス
    			if ((*p)->state == TASK_RUNNING && (*p)->counter > c)
    				c = (*p)->counter, next = i;
    		}
    		if (c) break;
            // ２回目サーチ
    		for(p = &LAST_TASK ; p > &FIRST_TASK ; --p)
    			if (*p)
                    // counter を bitシフトで1/2
                    // do_timer で減らされているのでタイムスライスなのかな
    				(*p)->counter = ((*p)->counter >> 1) +
    						(*p)->priority;
    	}
    	switch_to(next);
    }


    /*
     *  switch_to(n) should switch tasks to task nr n, first
     * checking that n isn't the current task, in which case it does nothing.
     * This also clears the TS-flag if the task we switched to has used
     * tha math co-processor latest.
     */
    #define switch_to(n) {
    struct {long a,b;} __tmp; 
    __asm__(
        cmpl %%ecx,_current   / switch_toに指定したプロセスと現在のプロセスが同じでないかを見る
        je 1f 
        xchgl %%ecx,_current  / タスクを切り替え ?
                              / current で参照されるプロセスが n に変わっている
        movw %%dx,%1 
        ljmp %0 
        cmpl %%ecx,%2 
        jne 1f 
        clts                  / http://www.ousob.com/ng/masm/ng7110.php
        1:"
        ::m" (*&__tmp.a),"m" (*&__tmp.b), 
        m" (last_task_used_math),"d" _TSS(n),"c" ((long) task[n])); 
    }

## システムコール呼び出し

 * set_system_gate(0x80,&system_call); で割り込みベクタの初期化
 * int 0x80 でのシステムコール呼び出しのソフトウェア割り込み(例外)、
   * eax にシステムコール番号、ebx, ecx, edx に引数 をセットして割り込みする
     * 必要に応じて スケジューリングする
   * eax に返り値をセット
   * シグナルを受けていた場合はシグナルハンドラを呼び出し
 * iret で割り込みからの復帰
 
### 詳細

 * main -> sched_init() で int 0x80 を trap してシステムコール呼び出しに入る様に設定している

   set_system_gate(0x80,&system_call);

 * 呼び出しのアセンブラ部分
 
    bad_sys_call:
    	movl $-1,%eax  // -ENOSYS
    	iret
    .align 2
    reschedule:
    	pushl $ret_from_sys_call
    	jmp _schedule
    .align 2
    
    // kernel/system_call.s
    _system_call:
    	cmpl $nr_system_calls-1,%eax  // (eaxレジスタの番号 - システムコール番号の最大値) を比較
    	ja bad_sys_call               // 実装されないシステムコール呼び出しだぞー
    	push %ds       // データセグメントをスタックに退避
    	push %es       //
    	push %fs       //
    	pushl %edx                                           // 引数 3 
    	pushl %ecx		# push %ebx,%ecx,%edx as parameters  // 引数 2 
    	pushl %ebx		# to the system call                 // 引数 1 
    	movl $0x10,%edx		# set up ds,es to kernel space
    	mov %dx,%ds
    	mov %dx,%es
    	movl $0x17,%edx		# fs points to local data space
    	mov %dx,%fs
    	call _sys_call_table(,%eax,4) // システムコールテーブルで%eax番目の関数にディスパッチする

    	pushl %eax                    // 退避 ( rescheduleしたりするので、システムコール呼び出しの際のレジスタを一旦退避するのだろう)
    	movl _current,%eax            // current = task struct ?
    	cmpl $0,state(%eax)		      // task_struc->state をみてるのかな
    	jne reschedule                // 0 = runnable でなければ reschedule
    	cmpl $0,counter(%eax)		  // task_struct->counter == 0 なら
    	je reschedule                 // 再スケジューリング

 * システムコールから復帰の部分 
   * int 0x80 で割り込んでいるので、割り込みからの復帰 iret が必要

    ret_from_sys_call:
    	movl _current,%eax		# task[0] cannot have signals
    	cmpl _task,%eax         // task[0] -> init ? カーネルスレッド ? 
    	je 3f                   // シグナル処理をすっとばして 3 に行く

    	movl CS(%esp),%ebx		# was old code segment supervisor
    	testl $3,%ebx			# mode? If so - don't check signals
    	je 3f
    	cmpw $0x17,OLDSS(%esp)		# was stack segment = 0x17 ?
    	jne 3f
    // シグナルハンドラの呼び出し
    2:	movl signal(%eax),%ebx		# signals (bitmap, 32 signals)
    	bsfl %ebx,%ecx			# %ecx is signal nr, return if none
    	je 3f                   # シグナルを受信してなかったら 3 

    	btrl %ecx,%ebx			# clear it
    	movl %ebx,signal(%eax)
    	movl sig_fn(%eax,%ecx,4),%ebx	# %ebx is signal handler address
    	cmpl $1,%ebx
    	jb default_signal		# 0 is default signal handler - exit
    	je 2b				# 1 is ignore - find next signal
    	movl $0,sig_fn(%eax,%ecx,4)	# reset signal handler address
    	incl %ecx
    	xchgl %ebx,EIP(%esp)		# put new return address on stack
    	subl $28,OLDESP(%esp)
    	movl OLDESP(%esp),%edx		# push old return address on stack
    	pushl %eax			# but first check that it's ok.
    	pushl %ecx
    	pushl $28
    	pushl %edx
    	call _verify_area
    	popl %edx
    	addl $4,%esp
    	popl %ecx
    	popl %eax
    	movl restorer(%eax),%eax
    	movl %eax,%fs:(%edx)		# flag/reg restorer
    	movl %ecx,%fs:4(%edx)		# signal nr
    	movl EAX(%esp),%eax
    	movl %eax,%fs:8(%edx)		# old eax
    	movl ECX(%esp),%eax
    	movl %eax,%fs:12(%edx)		# old ecx
    	movl EDX(%esp),%eax
    	movl %eax,%fs:16(%edx)		# old edx
    	movl EFLAGS(%esp),%eax
    	movl %eax,%fs:20(%edx)		# old eflags
    	movl %ebx,%fs:24(%edx)		# old return addr

    3:	popl %eax                   // 退避してたレジスタを元に戻して、プロセス側のコンテキストに iret で戻る
    	popl %ebx
    	popl %ecx
    	popl %edx
    	pop %fs
    	pop %es
    	pop %ds
    	iret                       // 割り込みからの復帰


## ページフォルトハンドラ

 * get_free_page() でページが足りない場合に SIGSEGV を返す。ENOMEM じゃないのかな?
 * 32bitのメモリなので
  * ページサイズが 12bit (4096K) の場合, ページエントリの数は 20bit
   * (address>>20) &0xffc
     * (0xfffff000 & *((unsigned long *) ((address>>20) &0xffc)))
     * => ページエントリのベースアドレスを出す?

 * trapの初期化は trap_init (traps.c )

    void trap_init(void) { 
        /* 略 */
	    set_trap_gate(14,&page_fault);
	    set_trap_gate(15,&reserved);
	    set_trap_gate(16,&coprocessor_error);

 * トラップゲート?の14番目のエントリとしてセット。
 * ページフォルトした場合のハンドラ (mm/page.s)

    /*
     * page.s contains the low-level page-exception code.
     * the real work is done in mm.c
     */
    
    .globl _page_fault
    
    _page_fault:
    	xchgl %eax,(%esp) // eax と (%esp) を入れ替える? TODO:
                          // (%esp) にはフォールトを発生させたアドレス?
    	pushl %ecx        // ユーザプロセスのレジスタを退避 
    	pushl %edx        // 
    	push %ds          // データセグメントの退避
    	push %es          // エクストラセグメントの退避
    	push %fs          // ??セグメント?? の退避
    	movl $0x10,%edx   // 80 ?
    	mov %dx,%ds       //
    	mov %dx,%es
    	mov %dx,%fs
    	movl %cr2,%edx
    	pushl %edx       // 退避
    	pushl %eax       // 退避
        -------------------------------------------------------------------

    	testl $1,%eax    // ページが割り当てられているかどうかのテスト?
      	  jne 1f           // ページが割り当てられていたら do_wp_page に飛ぶ
    	call _do_no_page // ページが割当られていないので確保する
    	jmp 2f

    1:	call _do_wp_page // ページ書き込みの処理 
    2:	addl $8,%esp

       -------------------------------------------------------------------
     	pop %fs          // スタックを復帰させる
    	pop %es
    	pop %ds
    	popl %edx
    	popl %ecx
    	popl %eax
    	iret             // ユーザープロセスコンテキストに戻る

### 割当ページが存在しない場合

    void do_no_page(unsigned long error_code,unsigned long address)
    {
    	unsigned long tmp;

    	if (tmp=get_free_page())
    		if (put_page(tmp,address))
    			return;
    	do_exit(SIGSEGV);
    }

 * get_free_page は x86 の命令直呼び出ししてページを確保する。
 * 物理メモリを操作して used bit ? の立っていないページを探す命令ぽい
   * TODO: x86の命令が分からない http://asm.inightmare.org/opcodelst/

    /*
     * Get physical address of first (actually last :-) free page, and mark it
     * used. If no free pages left, return 0.
     */
    unsigned long get_free_page(void)
    {
    register unsigned long __res asm("ax");
    
    __asm__(
        std ;                  / DF(ディレクションフラグを1にする
        repne ; scasw          / ecxの値と等しくない間はリピート
                               / scasw ... Compare AX with word at ES:(E)DI and set status flags
    	jne 1f                 / 1に飛ぶ (ページが見つからない?

    	movw $1,2(%%edi)       / 
    	sall $12,%%ecx         / 12bit 左シフト (4096)
    	movl %%ecx,%%edx       /
    	addl %2,%%edx          / 
    	movl $1024,%%ecx
    	leal 4092(%%edx),%%edi / %edxの値に4092 足して %edi に格納
    	rep ; stosl            / リピート => 0 でクリアするぽい
    	movl %%edx,%%eax\n     / %eax がページの物理アドレス?
    	1:
    	:=a" (__res)
    	:"0" (0),"i" (LOW_MEM),"c" (PAGING_PAGES),
    	"D" (mem_map+PAGING_PAGES-1)
    	:"di","cx","dx");
    return __res;
    }

### 割当ページが存在する場合

 * shared なページに書き込もうとした場合
   * ページを新しいアドレスにコピーする
   * 元のページの参照カウントをデクリメントする
     * 新しいページを使うようにする

    /*
     * This routine handles present pages, when users try to write
     * to a shared page. It is done by copying the page to a new address
     * and decrementing the shared-page counter for the old page.
     */
    void do_wp_page(unsigned long error_code,unsigned long address)
    {
        /* ページを管理しているテーブルを探すためのロジックなんだろうけど、分からない */
    	un_wp_page((unsigned long *)
    		(((address>>10) & 0xffc) + (0xfffff000 &
    		*((unsigned long *) ((address>>20) &0xffc)))));
    
    }

 * 新しいページを探して、ページの内容をコピーする
   * ページが足らんかったら SIGSEGV で exit
 * 新しいページが プロセス private なページとして管理されることになる

    void un_wp_page(unsigned long * table_entry)
    {
    	unsigned long old_page,new_page;

    	old_page = 0xfffff000 & *table_entry;
    	if (old_page >= LOW_MEM && mem_map[MAP_NR(old_page)]==1) {
    		*table_entry |= 2;
    		return;
    	}
        /* 新しいページを見つけられない (ENOMEMじゃないのか) */
    	if (!(new_page=get_free_page()))
    		do_exit(SIGSEGV);
    	if (old_page >= LOW_MEM)
    		mem_map[MAP_NR(old_page)]--;
         // ? 
    	*table_entry = new_page | 7;
    	copy_page(old_page,new_page);
    }	


    // 1024 x 1ワード (4バイト) ずつメモリコピーする命令かな?
    #define copy_page(from,to) \
    __asm__("cld ; rep ; movsl"::"S" (from),"D" (to),"c" (1024):"cx","di","si")

### タイマ割り込みハンドラ

 * カレントプロセスのタイムスライスの操作、スケジューリングする
  * ロードアベレージなどの統計的なデータを扱うコードはまだ実装されていない

 * set_intr_gate で割り込みゲートの登録。32番目

    set_intr_gate(0x20,&timer_interrupt);
    
    #define set_intr_gate(n,addr) \
	_set_gate(&idt[n],14,0,addr) // gate_addr, type = 14, dpl = 0 (Ring0 特権), addr

    #define _set_gate(gate_addr,type,dpl,addr) 
    __asm__ (
        movw %%dx,%%ax
    	movw %0,%%dx 
    	movl %%eax,%1 
    	movl %%edx,%2
    	: 
    	: "i" ((short) (0x8000+(dpl<<13)+(type<<8))), 
    	"o" (*((char *) (gate_addr))), 
    	"o" (*(4+(char *) (gate_addr))), 
    	"d" ((char *) (addr)),"a" (0x00080000))

  * タイマ割り込みのハンドラ。割り込みコンテキストなので、sleepせずなるたけ速く返らないといけない
        
    _timer_interrupt:
            push %ds                # save ds,es and put kernel data space
            push %es                # into them. %fs is used by _system_call
            push %fs 
            pushl %edx              # we save %eax,%ecx,%edx as gcc doesn't
            pushl %ecx              # save those across function calls. %ebx
            pushl %ebx              # is saved as we use that in ret_sys_call
            pushl %eax              # コンテキストを退避
            -----------------------------------------------------------------
            movl $0x10,%eax
            mov %ax,%ds
            mov %ax,%es
            movl $0x17,%eax
            mov %ax,%fs
            incl _jiffies           # jiffie の繰り上げ => 現在時刻が更新される、はず ( sys_times で参照している )
            movb $0x20,%al          # EOI to interrupt controller #1
            outb %al,$0x20
            movl CS(%esp),%eax
            andl $3,%eax            # %eax is CPL (0 or 3, 0=supervisor)
            pushl %eax              # eaxの値次第で do_timer の中で schedule() するかどうか決まるのかな
            call _do_timer          # 'do_timer(long CPL)' does everything from
            addl $4,%esp            # task switching to accounting ...
            -----------------------------------------------------------------
            jmp ret_from_sys_call   # システムコールから戻るサブルーチンで戻る。豪快

            
 * currentプロセスの ユーザー時間とシステム時間を加算
 * current->counter の値は time slice / time quantum

    void do_timer(long cpl)
    {
    	if (cpl)
    		current->utime++;
    	else
    		current->stime++;
    	if ((--current->counter)>0) return;
    	current->counter=0;
    	if (!cpl) return;
    	schedule();
    }
 
 * ロードアベレージの計算がない!!!
   * 2.6.35 は do_timer の中で calc_global_load(); を読んで ロードアベレージを計算している

## do_execve

 * struct exec は a.out 形式で、4.3BSDと同じ。ELFではない

    truct exec {
     unsigned long a_magic;	/* Use macros N_MAGIC, etc for access */
     unsigned a_text;		/* length of text, in bytes */
     unsigned a_data;		/* length of data, in bytes */
     unsigned a_bss;		/* length of uninitialized data area for file, in bytes */
     unsigned a_syms;		/* length of symbol table data in file, in bytes */
     unsigned a_entry;		/* start address */
     unsigned a_trsize;		/* length of relocation info for text, in bytes */
     unsigned a_drsize;		/* length of relocation info for data, in bytes */
    ;

    /* Code indicating object file or impure executable.  */
    #define OMAGIC 0407

    /* Code indicating pure executable.  */
    #define NMAGIC 0410

    /* Code indicating demand-paged executable.  */
    #define ZMAGIC 0413

  * shebang は使えなかったのかな?
  * namei, iput, bread, brelse のAPIも一緒
  * シグナルハンドラのNULL化
  * close_on_exec ならファイルテーブルを閉じる
  * ユーザランドから 引数コピる

    p = copy_strings(envc,envp,page,PAGE_SIZE*MAX_ARG_PAGES-4);
    p = copy_strings(argc,argv,page,p);

  * linux は BSDみたいに `u.u_error = ENOEXEC;` のようなエラーコードの持ち方をしないで、return で直返しする
    * why ? 
