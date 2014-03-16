# UNIX 4.3BSDの設計と実装

## VAX

 * 0 kernel, 1, 2, 3 user の特権レベル
 
## 3 カーネルサービス

 * top half
   * プロセスコンテキスト
 * bottom half
   * 割り込みコンテキスト
   * 非同期
   * スケジュールされない

### カーネルの入り口

OS,アーキテクチャによる違いはあるが 設計の骨組みとして共通するのは

 * ユーザモード/カーネルモードの切り替え
 * レジスタの退避/復帰
 * ハンドラの実行が要点
 
のあたり。

## システムプロセス

 * swapperプロセス
   * PID = 0
   * Bach本とだいたい同じ記述

## 3.2 システムコール

Bach本 6.4.2 に書かれている記述/擬似コードと合致する部分が多い

 * システムコールの一覧
  * /_/c/4.3BSD/srcsys/sys/syscalls.c
 * `return from iterruput` で変える
 * VAX 0番目の汎用レジスタに返り値がはいる。Linuxのx86系と同じ (eax)
 * Cライブラリが errno を操作してエラーを指し示す
   * PDP-11 由来の歴史的な作法らしい。
 * システムコールのシグナル割り込み EINTER について触れられてる
   * setjmp, プログラムカウンタを保存して使っているあたり?
 
### source (machine/trap.c)

割り込みベクタでのディスパッチ => syscall() => システムコール番号でのディスパッチ 
 
  * 割り込みベクタの初期化 (machine/scb.s)
  * 4byteごとにならんどる?
 ```c
/* 000 */       STRAY;          IS(machcheck);  IS(kspnotval);  STOP(powfail);
/* 010 */       KS(privinflt);  KS(xfcflt);     KS(resopflt);   KS(resadflt);
/* 020 */       KS(protflt);    KS(transflt);   KS(tracep);     KS(bptflt);
/* 030 */       KS(compatflt);  KS(arithtrap);  STRAY;          STRAY;
/* 040 */       KS(syscall);    KS(chme);       KS(chms);       KS(chmu);
/* 050 */       STRAY;          IS(cmrd);       STRAY;          STRAY;
/* 060 */       IS(wtime);      STRAY;          STRAY;          STRAY;
/* 070 */       STRAY;          STRAY;          STRAY;          STRAY;
/* 080 */       STRAY;          STRAY;          KS(astflt);     STRAY;
/* 090 */       STRAY;          STRAY;          STRAY;          STRAY;
/* 0a0 */       IS(softclock);  STRAY;          STRAY;          STRAY;
/* 0b0 */       IS(netintr);    STRAY;          STRAY;          STRAY;
/* 0c0 */       IS(hardclock);  STRAY;          KS(emulate);    KS(emulateFPD);
/* 0d0 */       STRAY;          STRAY;          STRAY;          STRAY;
/* 0e0 */       STRAY;          STRAY;          STRAY;          STRAY;
/* 0f0 */       IS(consdin);    IS(consdout);   IS(cnrint);     IS(cnxint);
/* 100 */       IS(nexzvec); STRAY15;           /* ipl 0x14, nexus 0-15 */
/* 140 */       IS(nexzvec); STRAY15;           /* ipl 0x15, nexus 0-15 */
/* 180 */       IS(nexzvec); STRAY15;           /* ipl 0x16, nexus 0-15 */
/* 1c0 */       IS(nexzvec); STRAY15;           /* ipl 0x17, nexus 0-15 */
```

 * 割り込みハンドラの実装 (machine/locore.s)
 * chmk (CHange Mode to Kernel )
```
SCBVEC(syscall):
        pushl   $T_SYSCALL 
        mfpr    $USP,-(sp);   
                calls $0,_syscall;
                mtpr (sp)+,$USP
        incl    _cnt+V_SYSCALL      // システムコールを呼び出した回数を ++ かな
        addl2   $8,sp                   # pop type, code
        mtpr    $HIGH,$IPL              ## dont go to a higher IPL (GROT)
        rei
```

 * C実装の syscall が呼び出される。( trap.c )
   * trap(sp, type, code, pc, psl) はページフォルトとかをハンドリングする用
     * 6th では trap で システムコールのディスパッチをしていたけど、4.3BSDでは syscall に移動している
 * syscall は システムコールテーブルの番号をみて関数ポインタでディスパッチする役割
   * ユーザ空間から引数をコピーする、レジスタでエラー通知 などが肝
 ```c
    syscall(sp, type, code, pc, psl)

    // システムコールへの引き数の確認
    if ((i = callp->sy_narg * sizeof (int)) &&
    // ユーザ空間のスタック? からカーネル空間に引数をコピーしている箇所
    (u.u_error = copyin(params, (caddr_t)u.u_arg, (u_int)i)) != 0) {
                                               // コピーがエラった場合
        locr0[R0] = u.u_error;                 // レジスタ0 にエラー番号を入れる
        locr0[PS] |= PSL_C;     /* carry bit */// PSの carry bit を立ててエラーの通知

        (*(callp->sy_call))();                 // 関数ポインタでシステムコール呼び出し
                                               // 引数は u で参照できる
      if (u.u_eosys == NORMALRETURN) {
          // システムコールがエラった場合の番号が u_error に入ってる
          if (u.u_error) {
              locr0[R0] = u.u_error;
              locr0[PS] |= PSL_C; /* carry bit */ // carry bit たてる
          } else {
              locr0[R0] = u.u_r.r_val1;           // レジスタ0 にはシステムコールの返り値をセットしておく
              locr0[R1] = u.u_r.r_val2;           // ? なんだべ
              locr0[PS] &= ~PSL_C;                // carry bit をクリア => システムコール成功の印
          }
      } else if (u.u_eosys == RESTARTSYS)
          pc = opc;                               // プログラムカウンタを戻す?
                                                  // SA_RESTARTでシグナル割り込みされた際の処理ぽいんだけど謎
```

 * runrun(reschedule)のフラグがたってたら swtch() して優先度高いプロセスに変える

### ユーザランド側の システムコール呼び出し

http://193.166.3.2/pub/unix/4.3bsd/net2/lib/ から拾った

 * VAX

``` 
#ifdef PROF
#define	ENTRY(x)	.globl _/**/x; .align 2; _/**/x: .word 0; \
			.data; 1:; .long 0; .text; moval 1b,r0; jsb mcount
#else
#define	ENTRY(x)	.globl _/**/x; .align 2; _/**/x: .word 0
#endif PROF
#define	SYSCALL(x)	err: jmp cerror; ENTRY(x); chmk $SYS_/**/x; jcs err
#define	RSYSCALL(x)	SYSCALL(x); ret
#define	PSEUDO(x,y)	ENTRY(x); chmk $SYS_/**/y; ret
#define	CALL(x,y)	calls $x, _/**/y

#define	ASMSTR		.asciz

ENTRY(syscall)
	movl	4(ap),r0	    # syscall number
	subl3	$1,(ap)+,(ap)	# one fewer arguments
	chmk	r0              # CHange Mode to Kernel (カーネルモードに移行する命令らしい
	jcs	1f
	ret
1:
	jmp	cerror
```

 * i386

```c
#include "SYS.h"

#ifdef PROF
#define	ENTRY(x)	.globl _/**/x; \
			.data; 1:; .long 0; .text; .align 2; _/**/x: \
			movl $1b,%eax; call mcount
#else
#define	ENTRY(x)	.globl _/**/x; .text; .align 2; _/**/x: 
#endif PROF
#define	SYSCALL(x)	2: jmp cerror; ENTRY(x); lea SYS_/**/x,%eax; LCALL(7,0); jb 2b
#define	RSYSCALL(x)	SYSCALL(x); ret
#define	PSEUDO(x,y)	ENTRY(x); lea SYS_/**/y, %eax; ; LCALL(7,0); ret
#define	CALL(x,y)	call _/**/y; addl $4*x,%esp
/* gas fucks up offset -- although we don't currently need it, do for BCS */
#define	LCALL(x,y)	.byte 0x9a ; .long y; .word x

#define	ASMSTR		.asciz
    
ENTRY(syscall)
	pop	%ecx	/* rta */
	pop	%eax	/* syscall number */
	push	%ecx
	LCALL(7,0)  // 特別な命令で呼び出さないで、サブルーチン呼び出し???
	jb	1f
	ret
1:
	jmp	cerror
```    
        
## 3.4 Clock Interrupts

srcsys/sys/kern_clock.c

 * タイマ割り込み
   * hardclock() で ハードウェアのタイマ割り込みを処理

```
SCBVEC(hardclock):
        PUSHR
        mtpr $ICCS_RUN|ICCS_IE|ICCS_INT|ICCS_ERR,$ICCS // hardclock の優先度をあげてる?
        pushl 4+6*4(sp); pushl 4+6*4(sp);
        calls $2,_hardclock                     # hardclock(pc,psl)
        POPR;
        incl    _cnt+V_INTR
        incl    _intrcnt+I_CLOCK
        rei  
SCBVEC(softclock):
        PUSHR
        pushl   4+6*4(sp); pushl 4+6*4(sp);
        calls   $2,_softclock                   # softclock(pc,psl)
        POPR; 
        incl    _cnt+V_SOFT
        rei
```

 * 時間のかかる処理は ソフトウェア割り込み ( software interruputs) を起こして softclock() に委譲する
   * VAX の場合 100HZ なので、実時間 "0.01 秒内" にタイマ割り込みを処理しないと、次の割り込みを取りこぼす
   * CPU優先度の高い hardclock() で ソフトウェア割り込み => 優先度下げると softclock() を処理できる
   * 割り込みのコストが高い( VAX だと 100HZ ) ので hardclock() が softclock() を直接呼び出す場合もある
     * needsoft = 1 の時に softclock()
     * needsoft = 0 の時に setsoftclock() で割り込みする

  * http://www.cs.auckland.ac.nz/references/macvax/op-codes/Instructions/mtpr.html
    * mtpr命令でソフトウェア割りこみ? レジスタに何か書いてる

```    
              { 0, "_setsoftclock\n",
      "       mtpr    $0x8,$0x14\n" },
```

 * hardclock() の 優先度は非常に高いので、他のほとんどの処理はブロックされる
   * ネットワークパケットのロス、ディスクヘッドのセクタ転送? を取りこぼしたりする可能性。"重要"
 * 4.3BSD では setrlimit, SIGXCPU が実装済み
 * softclock()
   * calltodo のリストを線形にさらって、関数ポインタで `struct callout` を実行
   * プロファイリング TODO:
   * 優先度の再計算 TODO:
   
## 3.6 Process Management

ondeman paging, magic number の処理方法と、セグメントサイズの指定方法あたり、

 * `shebang` が実装されている ( kern_exec.c )
  * 6th にはない
  * 4.0BSDから => http://www.in-ulm.de/~mascheck/various/shebang/
 * a.out フォーマットは 6th とだいたい同じ
 * execve に指定されたファイルの最初の sizeof(exec) 分を読んで、フォーマットを解析する

``` 
struct exec {
	long	        a_magic;	/* magic number */
    unsigned long	a_text;		/* size of text segment */
    unsigned long	a_data;		/* size of initialized data */
    unsigned long	a_bss;		/* size of uninitialized data */
    unsigned long	a_syms;		/* size of symbol table */
    unsigned long	a_entry;	/* entry point */
    unsigned long	a_trsize;	/* size of text relocation */
    unsigned long	a_drsize;	/* size of data relocation */
};
```

  * ex_shell[SHSIZE] にインタプリタの名前を格納する。
    * データが # と ! で始まるかどうかを見て判断
    * #!に続く名前が実行可能ファイルだったら goto again で途中の処理を巻き返してやり直しする
      * ( 改めてインタプリタを execve() する感じ )
  * plain executable ( インタプリタで読むファイル ) の場合は text セグメントのサイズを data セグメントに加算して、テキストセグメントのサイズを 0 とする

```  
    	case 0407:
    		exdata.ex_exec.a_data += exdata.ex_exec.a_text;
    		exdata.ex_exec.a_text = 0;
    		break;
```            

  * インタプリタの名前は SHSIZE = 32文字 まで

# 4 プロセス管理

 * スレッドの考え方はまだない
   * スケジューリングがスレッド単位、プロセス(タスク)単位
   * スレッドごとにスケジューリングされないと、ページフォルトやシステムコールのブロックで全スレッドがブロックする

## 4.2 Process Management

 * プロセスの state と flags は別
  * state SIDL ----> SRUN <==> SSLEEP <==> SSTOP ---> SZOMB の遷移だけ
  * flags は context switch の中間状態を記述するためのフラグ
 * プロセス管理のリストは 3つある
   * allproc
   * freeproc
   * zombproc
 * スケジューリング用のキュー
   * run queue
     * setrq() で 繋ぐ
     * VAX では insque, remque 命令でキューを管理することができる
   * sleep queue (ハッシュ管理)
     * どちらも p_link と p_rlink で管理される
 * `struct proc` の p_pgrp, p_pptr, p_ctpr, p_osptr, p_ysptr でプロセスグループの管理
   * 親子関係、兄弟関係を指す。killpg(2) の実装
   * killpg(2) は 4.0 BSD から登場
 * プロセスの優先度は二つ
  * p_userpri　ユーザーモードの優先度
  * p_pri      カーネルモードの優先度
    * 優先度が PZERO以下のプロセスはシグナルハンドリングをしない (TASK_UNINTERRUPTIBLE)
    * 低レイヤの処理ではリソースを早く解放するために優先度を上げる Bach本

## The User Structure

 * `struct user`
  * 512 * 10ページ
  * カーネルスタックも同居する。struct user のサイズが固定なので、カーネルスタックが深くならないように注意する ( kernel-access fault を起こす )
  * 割り込み用のスタックは `interruput stack` というグローバルな領域がある
 * VAXアーキテクチャのPCB(Process Control Block)
   * ユーザーモードで、固定した仮想アドレスにおかれる。ハードウェアの仕様が濃い

```c   
struct pcb
{
	int	pcb_ksp; 	/* kernel stack pointer */
	int	pcb_esp; 	/* exec stack pointer */
	int	pcb_ssp; 	/* supervisor stack pointer */
	int	pcb_usp; 	/* user stack pointer */
    // 汎用レジスタ
	int	pcb_r0; 
	int	pcb_r1; 
	int	pcb_r2; 
	int	pcb_r3; 
	int	pcb_r4; 
	int	pcb_r5; 
	int	pcb_r6; 
	int	pcb_r7; 
	int	pcb_r8; 
	int	pcb_r9; 
	int	pcb_r10; 
	int	pcb_r11; 
	int	pcb_r12; 
#define	pcb_ap pcb_r12
	int	pcb_r13; 
#define	pcb_fp pcb_r13
	int	pcb_pc; 	/* program counter */
	int	pcb_psl; 	/* program status longword */

    // p0空間
	struct  pte *pcb_p0br; 	/* seg 0 base register */
	int	pcb_p0lr; 	/* seg 0 length register and astlevel */
    
    // p1空間
	struct  pte *pcb_p1br; 	/* seg 1 base register */
	int	pcb_p1lr; 	/* seg 1 length register and pme */
/*
 * Software pcb (extension)
 */
	int	pcb_szpt; 	/* number of pages of user page table */
	int	pcb_cmap2;
	int	*pcb_sswap;
	int	pcb_sigc[5];
};
```

## 4.2 Context Swtiching

 * synchronously
  * => トラップ
 * asynchronously
  * => 割り込みハンドラ
 * voluntary
  * => リソース待ちでブロック
  * sleep()
 * involuntary
  * => タイムスライス使い切り で発生する

 * run queue のキュー操作は VAXの命令で実装されている
   * Cのレイヤでは ↓ な感じで定義されている。32個のキューがある
   * p_pri を 4で割ってキュー割り当てする

```c   
#define	NQS	32		/* 32 run queues */
struct	prochd {
	struct	proc *ph_link;	/* linked list of running processes */
	struct	proc *ph_rlink;
} qs[NQS];
int	whichqs;		/* bit mask summarizing non-empty qs's */
#endif
```

### コンテキストスイッチ (swtch, resume, idle)
 
 * swtch()  ... run queue から高優先度のプロセスを探す
 * resume() ... PCBB を切り替えてコンテキストスイッチする

```c 
Idle: idle:
    mtpr    $0,$IPL         # must allow interrupts here
    tstl    _whichqs        # look for non-empty queue
    bneq    sw1
    brb idle

/*
 * Swtch(), using fancy VAX instructions
 */
    .align  1
JSBENTRY(Swtch, 0)
    movl    $1,_noproc
    incl    _cnt+V_SWTCH        # コンテキストスイッチの回数インクリメント 統計データ
sw1:ffs $0,$32,_whichqs,r0  # look for non-empty queue 
                                # find first bit 命令。最初にビットが立っている位置を探す
                                # _whichqs の 0 からはじめて ~ 32 bit まで確認する
                                # 0 に近いと優先度高いプロセス?
    mtpr    $0x18,$IPL          # lock out all so _whichqs==_qs // 優先度上げる
    bbcc    r0,_whichqs,sw1     # proc moved via lbolt interrupt
    movaq   _qs[r0],r1          # r1 にキューのアドレス? 
    remque  *(r1),r2            # r2 = p = highest pri process // キューから外す
    bvs badsw           # make sure something was there
sw2:beql    sw3
    insv    $1,r0,$1,_whichqs   # still more procs in this queue
sw3:
    clrl    _noproc
    clrl    _runrun
    tstl    P_WCHAN(r2)         ## firewalls // r2->p_wchan のポインタを test
    bneq    badsw               ## => パニック
    cmpb    P_STAT(r2),$SRUN    ##       // r2->p_stat == SRUN の test
    bneq    badsw               ## => パニック
    clrl    P_RLINK(r2)         ## // r2->r_link
    movl    *P_ADDR(r2),r0         // r2->r_addr を r0 にセット
    movl    r0,_masterpaddr        
    ashl    $PGSHIFT,r0,r0      # r0 = pcbb(p) ? // PCBのアドレスを r0 にセット
    　　　　　　　　　　　　　　　　　　　　　　 // resume で使う ?
/* fall into... */

/*
 * Resume(pf)
 */
JSBENTRY(Resume, R0)
        mtpr    $HIGH,$IPL              # no interrupts, please 割り込み不可
        movl    _CMAP2,_u+PCB_CMAP2     # yech 
        svpctx                          # ハードウェアコンテキストの保存 (PCBに保存)
                                        # svpctx を呼び出すと割り込みスタックに切り替わるらしい
        mtpr    r0,$PCBB                # Process Control Block Base レジスタに、別のPCBのアドレスをセット
                                        # mtpr は "内部特権レジスタ" のロードをする命令。カーネルモードでのみ実行可能な特権命令
                                        # movl とかでいじれんということなのか
        ldpctx                          # ハードウェアコンテキストの読み込み
                                        # ldpctx を呼び出すとカーネルスタックに切り替わる
        movl    _u+PCB_CMAP2,_CMAP2     # yech 
        mtpr    $_CADDR2,$TBIS
res0:
        tstl    _u+PCB_SSWAP
        bneq    res1 
        rei  
res1:
        movl    _u+PCB_SSWAP,r0                 # longjmp to saved context
        clrl    _u+PCB_SSWAP
        movq    (r0)+,r6
        movq    (r0)+,r8
        movq    (r0)+,r10
        movq    (r0)+,r12
        movl    (r0)+,r1
        cmpl    r1,sp                           # must be a pop
        bgequ   1f   
        pushab  2f
        calls   $1,_panic
        /* NOTREACHED */
1:
        movl    r1,sp
        movl    (r0),(sp)                       # address to return to
        movl    $PSL_PRVMOD,4(sp)               # ``cheating'' (jfr)
        rei
```

### run queue の操作 (setrq , remrq)

 * run queue の操作は Setrq()
 * VAXの命令でキュー操作される

```c 
/*
 * Setrq(p), using fancy VAX instructions.
 *
 * Call should be made at splclock(), and p->p_stat should be SRUN
 */
    .align  1
 JSBENTRY(Setrq, R0)
    tstl    P_RLINK(r0)     ## firewall: p->p_rlink must be 0
    beql    set1            ##
    pushab  set3            ##
    calls   $1,_panic       ## パニック
set1:
    movzbl  P_PRI(r0),r1     # put on queue which is p->p_pri / 4
                             # p->p_pri / 4 で繋げるキューを決める様子
                             # 結果 32 個のキューになる
    ashl    $-2,r1,r1
    movaq   _qs[r1],r2
    insque  (r0),*4(r2)      # at end of queue      // キューの末尾に insert
    bbss    r1,_whichqs,set2 # mark queue non-empty // bit をセット。 Swtch の ffs 命令で確認される
set2:
    rsb

set3:   .asciz  "setrq"
```

 * Remrq で run queue から外す

```c 
/*
 * Remrq(p), using fancy VAX instructions
 *
 * Call should be made at splclock().
 */
    .align  1
 JSBENTRY(Remrq, R0)
    movzbl  P_PRI(r0),r1
    ashl    $-2,r1,r1
    bbsc    r1,_whichqs,rem1
    pushab  rem3            # it wasn't recorded to be on its q
    calls   $1,_panic
rem1:
    remque  (r0),r2
    beql    rem2
    bbss    r1,_whichqs,rem2
rem2:
    clrl    P_RLINK(r0)     ## for firewall checking
    rsb

rem3:   .asciz  "remrq"
```

## Caculations of Process Priority

 * `decay filter` => 減衰フィルタ
 * ロードアベレージが計算されている。
   * tenex とかいうのが起源らしい http://ja.wikipedia.org/wiki/TOPS-20
 * /procやシステムコールインタフェースで参照する仕組みは無い様子
   * 計算式が分からん

```c   
double  avenrun[3];             /* load average, of runnable procs */

/*
 * Constants for averages over 1, 5, and 15 minutes
 * when sampling at 5 second intervals.
 */
double	cexp[3] = {
	0.9200444146293232,	/* exp(-1/12) */
	0.9834714538216174,	/* exp(-1/60) */
	0.9944598480048967,	/* exp(-1/180) */
};

/*
 * Compute a tenex style load average of a quantity on
 * 1, 5 and 15 minute intervals.
 */
loadav(avg, n)
	register double *avg;
	int n;
{
	register int i;

	for (i = 0; i < 3; i++)
		avg[i] = cexp[i] * avg[i] + n * (1.0 - cexp[i]);
}

/* fraction for digital decay to forget 90% of usage in 5*loadav sec */
#define	filter(loadav) ((2 * (loadav)) / (2 * (loadav) + 1))
```

 * setpri でプライオリティを再計算 (フィードバック) する

```c
/*
 * Set user priority.
 * The rescheduling flag (runrun)
 * is set if the priority is better
 * than the currently running process.
 */
// ユーザーモードのプライオリティを決定する
setpri(pp)
	register struct proc *pp;
{
	register int p;
    // 0377 = 255
    // PUSER + CPU使用時間の1/4 + 2 * p_nice
	p = (pp->p_cpu & 0377)/4;
	p += PUSER + 2 * pp->p_nice;
    //メモリ食ってると優先度下がる?
	if (pp->p_rssize > pp->p_maxrss && freemem < desfree)
		p += 2*4;	/* effectively, nice(4) */
    //127がmax
	if (p > 127)
		p = 127;
	if (p < curpri) {
		runrun++;
		aston();
	}
	pp->p_usrpri = p;
	return (p);
}
```

## 5.4 Management of Main Memory

### Memory Allocation Routines

 * CLSIZE とは?
   * ハードウェアのページサイズが小さい場合に複数ページをクラスタリングして、1ページとして扱う
   * その際のサイズが CLSIZE
 * ここで言う `memory allocation` の定義は?
   * vm_mem.c 当たりにルーチンまとまってる
 * core map とは?
   * ページクラスタ管理用の配列, 構造体
   * PTEはハードウェアレイヤのページ管理用のオブジェクト
     * ハードウェアレイヤの仕様がOSレイヤの仕様に出過ぎてる感
   * OS(ソフトウェア)レイヤでのメタデータ,フラグを管理するオブジェクトとして core map
   * => PTEを一体一で結びついている
 * core map 役割は?
    * 物理アドレスから仮想アドレスへの逆マッピング (PTEの動作と逆)
    * ページクラスタの管理??? ( ページフレーム?)
    * フリーリストの管理 (LRU)
    * 同期機構
      * c_lock, c_want
    * テキストページのキャッシュ
  * core map が管理対象は User memory の区間の物理メモリのページ

```  
    +--------+--------------------------------------------------------+-------+
    | kernel |                        User memory                     | msgs  |
    +--------+--------------------------------------------------------+-------+
             |                                                        |
             |                                                        |
          firstfree <~~~~~~~~~~~~~~~~~ freemem ~~~~~~~~~~~~~~~~~~> maxfree
                         [freemem / CLSIZE] = page clustersの数
```

  * core map の初期化
    * vax/machdep.c で呼び出されている

```c    
/*
 * Initialize core map
 */
meminit(first, last)
	int first, last;
{
	register int i;
	register struct cmap *c;

	firstfree = clrnd(first);
	maxfree = clrnd(last - (CLSIZE - 1));
	freemem = maxfree - firstfree;
	ecmx = ecmap - cmap;
	if (ecmx < freemem / CLSIZE)
		freemem = ecmx * CLSIZE;

    // freemem / CLSIZE => ページクラスタの数
    // リンクリストの初期化
	for (i = 1; i <= freemem / CLSIZE; i++) {
		cmap[i-1].c_next = i;
		c = &cmap[i];
		c->c_prev = i-1;
		c->c_free = 1;
		c->c_gone = 1;
		c->c_type = CSYS;
		c->c_mdev = 0;
		c->c_blkno = 0;
	}
    
	cmap[freemem / CLSIZE].c_next = CMHEAD;
	for (i = 0; i < CMHSIZ; i++)
		cmhash[i] = ecmx;
	cmap[CMHEAD].c_prev = freemem / CLSIZE;
	cmap[CMHEAD].c_type = CSYS;
	avefree = freemem;
}
```

 * ページングの閾値が定義されている
   * freemem 空きメモリ

```c   
*
* Paging thresholds (see vm_sched.c).
* Strategy of 1/19/85:
*      lotsfree is 512k bytes, but at most 1/4 of memory
*      desfree is 200k bytes, but at most 1/8 of memory
*      minfree is 64k bytes, but at most 1/2 of desfree
*/
```

 * memall(),memfree()
   * メモリが足らない場合 失敗する
   * 割り込みコンテキストで使う => Linux kmalloc GFP_ATOMIC の使用方法と類似
     * kmalloc に相当するのは rmalloc ?
   * memall() は cmap ( core map ) に繋がってるリストを走査して、空きを探す。最初に見つけた core map を利用する

```c
//テキストセグメント
#define	tptopte(p, i)		((p)->p_p0br + (i))
//データセグメント( テキストセグメントをオフセットにした数値
#define	dptopte(p, i)		((p)->p_p0br + ((p)->p_tsize + (i)))
//スタックセグメント system セグメントから減算した場所
#define	sptopte(p, i)		((p)->p_addr - (1 + (i)))

//仮想ページ番号を 各セグメントのページ番号に変換する, もしくはその逆
/* Virtual page numbers to text|data|stack segment page numbers and back */
#define	vtotp(p, v)	((int)(v))
#define	vtodp(p, v)	((int)((v) - stoc(ctos((p)->p_tsize))))
#define	vtosp(p, v)	((int)(BTOPUSRSTACK - 1 - (v)))
#define	tptov(p, i)	((unsigned)(i))
#define	dptov(p, i)	((unsigned)(stoc(ctos((p)->p_tsize)) + (i)))
#define	sptov(p, i)	((unsigned)(BTOPUSRSTACK - 1 - (i)))
```

   * memfree(pte, size, detach)
     * PTE ~ PTE + size 分のページフレームをフリーリストに繋ぐ
     * PG_PROT 以外を落とす
     * c_gone = 1 にして、ページ解放の印をつける => pageout デーモンにまかせる
     * c->c_free = 1;
     * freemem += CLSIZE; freemem を加算

 * vmemall(), vmemfree()
   * 必ずメモリを確保するが、メモリが確保されるまで sleep する可能性がある
     * 内部では memall() を呼び出す
       * freemem -= CLSIZE; を減算
     * sleepするためプロセスコンテキストでしか使えない => Linux の kmalloc GFP_KERNEL との類似
     * freemem < desfree の場合、 outofmem() で pageoutデーモンをwakeupしてページ回収を要求する
   * vmemall() は procdup() の中でプロセスを複製する際に呼び出されている   
   * vmemfree() は指定したページテーブルエントリから、count分のページを解放する
     * valid + reclaimable + locked な場合 => pageout デーモンに処理を任せる
     * 連続した valid ページなページ群を memfree() に渡して一度で解放する

   * memall(pte, size, p, type)
    * プロセスの PTE ~ PTE+size 分のページフレームを確保。typeを指定

## 5.11 Demand Paging

 * ページフォルトハンドラ pagein()
  * ページフォルトを起こした仮想アドレスから、セグメント(text,data,stack) を求める
  * ページフォルトを起こした仮想アドレスから、PTEを求める ( vtopte() )
    * PTEB Page Table Entry Base レジスタ (p_p0br) などを利用して求められる
  * core map によってページの操作を操る
    * c_free = 1 ページがフリーリストに載ってる
    * c_lock = 1 ならプロセスをsleep
    * c_want = 1 ならプロセスを起床させる
  * PTEを更新 => TLBのクリア の操作
  * fill on demand

ページフォルトハンドラでは、利用したいページがロックされていたり転送中だと sleep しうる
 * ユーザプロセスコンテキストなので ok

## ファイルシステム
 
### 7.5 バッファ管理 (bio.c)

 * getblk
   * ブロックに割り当てられるバッファを獲得する
     * 獲得したいバッファが他のプロセスが使用中 (B_BUSY) であれば 待つ
     * バッファが無い場合も待つ
 * bfreelist
   * 複数アルゴリズムで bfreelist を持つ
   * unix 6th だと一個だけ (LRU?
 * bread(dev, blkno, size)
   * 現行の linux だと `struct buffer_head * __bread(struct block_device *bdev, sector_t block, unsigned size)`
   * デバイスドライバを呼び出してバッファを埋める、という意味合いでこの名前を使う
   * bread で獲得しようとしたバッファがロックされている場合は 休止(sleep?) して待つ
     * linux __bread だと TASK_UNINTERRUPTIBLE で待つぽい

バッファの再利用、I/Oの割り込みを待つ場合、自分で sleep に入るってあたりが肝

#### バッファを解放するメソッド 4つ

 * brelse
   * バッファが変更されている状態に対して `dirty` と呼ぶ記述がある
   * bfreelist に B_WANTED を立てておくと wakeup を読んでバッファ解放待ちのプロセスを解放してくれるイベントを立てる

```c   
	if (bp->b_flags&B_WANTED)
		wakeup((caddr_t)bp);
	if (bfreelist[0].b_flags&B_WANTED) {
		bfreelist[0].b_flags &= ~B_WANTED;
		wakeup((caddr_t)bfreelist);
	}
```
     * 6th では 単純に bfreelist の末尾にバッファを戻す
     * 4.3BSDだと b_flags に応じた bfreelist を選択して末尾に戻す
   * linux だと __brelse 参照カウントをatomicに下げるだけ
     * 参照カウントで locked / unlocked を決めている
 * bdwrite ... diry の印をつけるけど、呼び出し時点ではI/Oを発行しない。(`delayed write` の略
   * 遅延書き込み
   * バッファが近い時間のうちに再変更される可能性がある場合、すぐにI/Oを発行しておかないで「溜めて」置いたが効率が良い
   * 実装は B_DELWRI (delay write, B_DONE) フラグたてて brelse 呼んでいるだけ
 * bawrite ... 非同期書き込み
 　* 実装は B_ASYNC をたてて bwrite 呼んでいるだけ
 * bwrite  ... 同期書き込み
   * fdatasync, fsync, O_SYNC ?
   * ブロックデバイスに対して I/O を発行している

```
    bdevsw[major(bp->b_dev)].d_strategy)(bp);`
```

   * biowait で sleep する
     * ドライバからの割り込みで wakeup が呼び出されるはず
 * bflush  遅延書き込みバッファをディスクに書き出し
   * 6th だと /etc/update デーモンが 30秒ごとに bflush を呼び出す
   * 遅延書き込みバッファをほったらかしておくと、電源断などで不整合が生じる (要ジャーナリング?)

 * breada
    * design 本に書かれてる擬似コードと大体同じアルゴリズムで実装されている
     * 6th edtion の実装も大体同じ
    * 一個目の I/Oを発行、二個目のI/Oは B_ASYNC、一個目の I/O を sleep して待つ
    * ブロックデバイスから割り込みコンテキストで wakeup が実行されたらバッファを呼び出し元に返す

```c
/*
 * Wait for I/O completion on the buffer; return errors
 * to the user.
 */
iowait(bp)
struct buf *bp;
{
	register struct buf *rbp;

	rbp = bp;
	spl6();
	while ((rbp->b_flags&B_DONE)==0)
		sleep(rbp, PRIBIO);
	spl0();
	geterror(rbp);
}
```

これらを区分すると ↓ の感じ。遅延(delayed) と 非同期(async) 意味分けに注意

```
    brelse  I/O 発行無し
    bdwrite I/O 発行無し、遅延
    bawrite I/O 発行、非同期
    bwrite  I/O 発行、同期
```

## ページフォルト (vm_page.c)

```c
*
* Handle a page fault.
*
* Basic outline
*	If page is allocated, but just not valid:
*		Wait if intransit, else just revalidate
*		Done
*	Compute <dev,bn> from which page operation would take place
*	If page is text page, and filling from file system or swap space:
*		If in free list cache, reattach it and then done
*	Allocate memory for page in
*		If block here, restart because we could have swapped, etc.
*	Lock process from swapping for duration
*	Update pte's to reflect that page is intransit.
*	If page is zero fill on demand:
*		Clear pages and flush free list cache of stale cacheing
*		for this swap page (e.g. before initializing again due
*		to 407/410 exec).
*	If page is fill from file and in buffer cache:
*		Copy the page from the buffer cache.
*	If not a fill on demand:
*		Determine swap address and cluster to page in
*	Do the swap to bring the page in
*	Instrument the pagein
*	After swap validate the required new page
*	Leave prepaged pages reclaimable (not valid)
*	Update shared copies of text page tables
*	Complete bookkeeping on pages brought in:
*		No longer intransit
*		Hash text pages into core hash structure
*		Unlock pages (modulo raw i/o requirements)
*		Flush translation buffer
*	Process pagein is done
*/
```

## vfork

 * vfork は 3.0BSD由来ぽい
  * system V では copy on write が実装されている
  * 4.4BSD では copy on write が実装された
 * sys/init_sysent.c 

``` 
    int     vfork();                /* awaiting fork w/ copy on write */
```    

 * vfork と CoW について 哲学の違いと、 Bach 本では説明している
   * システムの特性をユーザーに対してふせておくか、優れた開発者が効率よく実装できるか
   * vfork はアプリケーション開発者が注意深く扱う必要がある

 * VAXアーキテクチャの制約が copy on write の実装を遠ざけ vfork の仕組みにいたったとか何とか。
 * VAXアーキテクチャハンドブック

## 7章メモリ管理

 * 最上位2ビットでリージョンを決める
  * システム管理領域
  * P1
  * P0
 * システム管理領域の仮想アドレスは、ユーザープロセスからもアクセスできる
  * CALL命令でカーネルの手続きを呼び出せる
  * システムコールを呼ぶ際に割り込みを使ったりしない??

## 8章プロセス構造

 * プロセス
   * 仮想アドレス空間
   * ハードウェアコンテキスト = 4.3BSDはVAXアーキテクチャと密接
     * Process Control Block (PCB)
       * プロセスごとに保存
       * PCBB (Process Contorl Block Base register) が PCBのベースアドレスを指す
     * 14 general resiters
     * PSL
     * PC
     * 4 stack pointer
     * P0BR, P0LR, P1BR, P1LR
   * ソフトウェアコンテキスト
