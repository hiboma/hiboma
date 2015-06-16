
## どゆこと?

```
[vagrant@vagrant-centos6 ~]$ ./a.out 
UID        PID  PPID  C STIME TTY          TIME CMD
vagrant   9660  9149  0 14:57 pts/0    00:00:00 [exe]
```

ps は `/proc/$pid/cmdline` から値をとれない状態の際に、 cmd, command の値を `[ ]` でくくった値を返す

#### man に記載されている

```
args       COMMAND  command with all its arguments as a string. Modifications to the arguments may be shown. The output in this column may contain spaces.
                    A process marked <defunct> is partly dead, waiting to be fully destroyed by its parent. Sometimes the process args will be unavailable; when
                    this happens, ps will instead print the executable name in brackets. (alias cmd, command). See also the comm format keyword, the -f option,
                    and the c option.
```

#### 再現コード

unix.stackexchange.com にも [同種の質問](http://unix.stackexchange.com/questions/110595/)がなげられている。 また[再現コード](http://unix.stackexchange.com/questions/110595/why-do-forked-processes-sometimes-appear-with-brackets-around-their-name-in-p?answertab=active#tab-top) が投稿されているので実行してみよう

```c
int main(int argc, char *argv[]) {
  if (argc) execve("/proc/self/exe",0,0);
  else system("ps -fp $PPID");
}
```

#### 実行結果

```
[vagrant@vagrant-centos6 ~]$ ./a.out 
UID        PID  PPID  C STIME TTY          TIME CMD
vagrant   9660  9149  0 14:57 pts/0    00:00:00 [exe]
```

このようなことである。一見するとカーネルスレッドと似ているのでややこしい。

## ps が `/proc/$pid/cmdline` から値をとれない状態とは何か?

 * fork か exec の途中か
   * cmdline はプロセスのスタックを参照することで取っているが、ここのスタックにアドレス空間が割り当てられていない場合に参照できなくなりそう

他何かあるんだっけ?   
 
## [ ] をつける箇所はどこか? ps の実装を追う

適当に grep して `ESC_BRACKETS` フラグを見つけた

```c
#define ESC_BRACKETS 0x2  // if using cmd, put '[' and ']' around it
```

`ESC_BRACKETS` を追いかけていくと `escape_command` にたどり着く。ここで `[ ]` が付く


```c
int escape_command(char *restrict const outbuf, const proc_t *restrict const pp, int bytes, int *cells, unsigned flags){
  int overhead = 0;
  int end = 0;

  /* cmdline から値をとれたらそれを返す */
  if(flags & ESC_ARGS){
    const char **lc = (const char**)pp->cmdline;
    if(lc && *lc) return escape_strlist(outbuf, lc, bytes, cells);
  }

  /* cmdline から値をとれない場合 */

  /* ESC_BRACKETS フラグがたっていれば [ ] でエスケープする */
  if(flags & ESC_BRACKETS){
    overhead += 2;
  }
  if(flags & ESC_DEFUNCT){
    if(pp->state=='Z') overhead += 10;    // chars in " <defunct>"
    else flags &= ~ESC_DEFUNCT;
  }
  if(overhead + 1 >= *cells){  // if no room for even one byte of the command name
    // you'd damn well better have _some_ space
//    outbuf[0] = '-';  // Oct23
    outbuf[1] = '\0';
    return 1;
  }
  if(flags & ESC_BRACKETS){
    outbuf[end++] = '[';
  }
  *cells -= overhead;
  end += escape_str(outbuf+end, pp->cmd, bytes-overhead, cells);

  // Hmmm, do we want "[foo] <defunct>" or "[foo <defunct>]"?
  if(flags & ESC_BRACKETS){
    outbuf[end++] = ']';
  }
  if(flags & ESC_DEFUNCT){
    memcpy(outbuf+end, " <defunct>", 10);
    end += 10;
  }
  outbuf[end] = '\0';
  return end;  // bytes, not including the NUL
}
```