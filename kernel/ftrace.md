# sysctl kernel.ftrace_enabled

## CONFIG

 * CONFIG_FUNCTION_TRACER
 * CONFIG_FUNCTION_GRAPH_TRACER
 * CONFIG_STACK_TRACER
 * CONFIG_DYNAMIC_FTRACE

## API

 * ftrace_trace_function ( ftrace_stub ) 
 * ftrace_graph_entry ( ftrace_graph_entry_stub )

## mcmount

 * http://lwn.net/Articles/365835/
 * gcc -pg
 * アセンブリ。C ABI では駄目
 * ブート時は NOP

```ams
#ifdef CONFIG_FUNCTION_GRAPH_TRACER
GLOBAL(ftrace_graph_call)
	jmp ftrace_stub
#endif

GLOBAL(ftrace_stub)
	retq
END(ftrace_caller)

#else /* ! CONFIG_DYNAMIC_FTRACE */
ENTRY(mcount)
	cmpl $0, function_trace_stop
	jne  ftrace_stub

	cmpq $ftrace_stub, ftrace_trace_function
	jnz trace

#ifdef CONFIG_FUNCTION_GRAPH_TRACER
	cmpq $ftrace_stub, ftrace_graph_return
	jnz ftrace_graph_caller

	cmpq $ftrace_graph_entry_stub, ftrace_graph_entry
	jnz ftrace_graph_caller
#endif
```

## sysctl インタフェース

### tracing_on

リングバッファの状態を取れる

```c
static __init int rb_init_debugfs(void)
{
	struct dentry *d_tracer;

	d_tracer = tracing_init_dentry();

	trace_create_file("tracing_on", 0644, d_tracer,
			    &ring_buffer_flags, &rb_simple_fops);

	return 0;
}
```

ring_buffer_flags に状態を保持している。

 * ftrace が実行されていても、リングバッファが書き込み可能でないと、何も記録されない
 * かな?

```c
#ifdef CONFIG_TRACING
static ssize_t
rb_simple_read(struct file *filp, char __user *ubuf,
	       size_t cnt, loff_t *ppos)
{
	unsigned long *p = filp->private_data;
	char buf[64];
	int r;

	if (test_bit(RB_BUFFERS_DISABLED_BIT, p))
		r = sprintf(buf, "permanently disabled\n");
	else
		r = sprintf(buf, "%d\n", test_bit(RB_BUFFERS_ON_BIT, p));

	return simple_read_from_buffer(ubuf, cnt, ppos, buf, r);
}

static ssize_t
rb_simple_write(struct file *filp, const char __user *ubuf,
		size_t cnt, loff_t *ppos)
{
	unsigned long *p = filp->private_data;
	char buf[64];
	unsigned long val;
	int ret;

	if (cnt >= sizeof(buf))
		return -EINVAL;

	if (copy_from_user(&buf, ubuf, cnt))
		return -EFAULT;

	buf[cnt] = 0;

	ret = strict_strtoul(buf, 10, &val);
	if (ret < 0)
		return ret;

	if (val)
		set_bit(RB_BUFFERS_ON_BIT, p);
	else
		clear_bit(RB_BUFFERS_ON_BIT, p);

	(*ppos)++;

	return cnt;
}

static const struct file_operations rb_simple_fops = {
	.open		= tracing_open_generic,
	.read		= rb_simple_read,
	.write		= rb_simple_write,
};
```

### ftrace_enabled

```c
#ifdef CONFIG_FUNCTION_TRACER
	{
		.ctl_name	= CTL_UNNUMBERED,
		.procname	= "ftrace_enabled",
		.data		= &ftrace_enabled,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= &ftrace_enable_sysctl,
	},
#endif
```

ftrace_enable_sysctl がエントリポイントのハンドラ

```c
int
ftrace_enable_sysctl(struct ctl_table *table, int write,
		     void __user *buffer, size_t *lenp,
		     loff_t *ppos)
{
	int ret = -ENODEV;

	mutex_lock(&ftrace_lock);

	if (unlikely(ftrace_disabled))
		goto out;

	ret = proc_dointvec(table, write, buffer, lenp, ppos);

	if (ret || !write || (last_ftrace_enabled == !!ftrace_enabled))
		goto out;

	last_ftrace_enabled = !!ftrace_enabled;

	if (ftrace_enabled) {

        /* ftrace はじめるよー */
		ftrace_startup_sysctl();

		/* we are starting ftrace again */
		if (ftrace_ops_list != &ftrace_list_end) {
			if (ftrace_ops_list->next == &ftrace_list_end)
				ftrace_trace_function = ftrace_ops_list->func;
			else
				ftrace_trace_function = ftrace_ops_list_func;
		}

	} else {
		/* stopping ftrace calls (just send to ftrace_stub) */
        /* スタブをいれることで無効化するらしい */
        /* mcount - arch/x86/kernel/entry_64.S で呼び出されている */
		ftrace_trace_function = ftrace_stub;

		ftrace_shutdown_sysctl();
	}

 out:
	mutex_unlock(&ftrace_lock);
	return ret;
}

#ifdef CONFIG_FUNCTION_GRAPH_TRACER
```

```c
static void ftrace_run_update_code(int command)
{
	int ret;

    /* set_kernel_text_rw(); を呼ぶ
     * カーネルのテキストセグメントのページを書き込み可能にする!
    */
	ret = ftrace_arch_code_modify_prepare();
	FTRACE_WARN_ON(ret);
	if (ret)
		return;

    /* ftrace できるように、コードを書き換えている、はず */
    /* 全てのCPUが「停止状態」? */
	stop_machine(__ftrace_modify_code, &command, NULL);

    /* set_kernel_text_ro(); を呼ぶ */
	ret = ftrace_arch_code_modify_post_process();
	FTRACE_WARN_ON(ret);
}
```

ここ以降、コード書き換えのコード。

```c
static int __ftrace_modify_code(void *data)
{
	int *command = data;

	/*
	 * Do not call function tracer while we update the code.
	 * We are in stop machine, no worrying about races.
	 */
	function_trace_stop++;

	if (*command & FTRACE_ENABLE_CALLS)
		ftrace_replace_code(1);
	else if (*command & FTRACE_DISABLE_CALLS)
		ftrace_replace_code(0);

	if (*command & FTRACE_UPDATE_TRACE_FUNC)
		ftrace_update_ftrace_func(ftrace_trace_function);

	if (*command & FTRACE_START_FUNC_RET)
		ftrace_enable_ftrace_graph_caller();
	else if (*command & FTRACE_STOP_FUNC_RET)
		ftrace_disable_ftrace_graph_caller();

#ifndef CONFIG_HAVE_FUNCTION_TRACE_MCOUNT_TEST
	/*
	 * For archs that call ftrace_test_stop_func(), we must
	 * wait till after we update all the function callers
	 * before we update the callback. This keeps different
	 * ops that record different functions from corrupting
	 * each other.
	 */
	__ftrace_trace_function = __ftrace_trace_function_delay;
#endif
	function_trace_stop--;

	return 0;
}
```

```c
static void ftrace_replace_code(int enable)
{
	struct dyn_ftrace *rec;
	struct ftrace_page *pg;
	int failed;

	if (unlikely(ftrace_disabled))
		return;

	do_for_each_ftrace_rec(pg, rec) {
		/* Skip over free records */
		if (rec->flags & FTRACE_FL_FREE)
			continue;

		/* ignore updates to this record's mcount site */
		if (get_kprobe((void *)rec->ip)) {
			freeze_record(rec);
			continue;
		} else {
			unfreeze_record(rec);
		}

		failed = __ftrace_replace_code(rec, enable);
		if (failed) {
			ftrace_bug(failed, rec->ip);
			/* Stop processing */
			return;
		}
	} while_for_each_ftrace_rec();
}
```

__ftrace_replace_code で

```c
static int
__ftrace_replace_code(struct dyn_ftrace *rec, int enable)
{
	unsigned long ftrace_addr;
	unsigned long flag = 0UL;

	ftrace_addr = (unsigned long)FTRACE_ADDR;

	/*
	 * If we are enabling tracing:
	 *
	 *   If the record has a ref count, then we need to enable it
	 *   because someone is using it.
	 *
	 *   Otherwise we make sure its disabled.
	 *
	 * If we are disabling tracing, then disable all records that
	 * are enabled.
	 */
	if (enable && (rec->flags & ~FTRACE_FL_MASK))
		flag = FTRACE_FL_ENABLED;

	/* If the state of this record hasn't changed, then do nothing */
	if ((rec->flags & FTRACE_FL_ENABLED) == flag)
		return 0;

	if (flag) {
		rec->flags |= FTRACE_FL_ENABLED;
		return ftrace_make_call(rec, ftrace_addr);
	}

	rec->flags &= ~FTRACE_FL_ENABLED;
	return ftrace_make_nop(NULL, rec, ftrace_addr);
}
```

```c
int ftrace_make_call(struct dyn_ftrace *rec, unsigned long addr)
{
	unsigned char *new, *old;
	unsigned long ip = rec->ip;

	old = ftrace_nop_replace();
	new = ftrace_call_replace(ip, addr);

	return ftrace_modify_code(rec->ip, old, new);
}
```

```c
static int
ftrace_modify_code(unsigned long ip, unsigned char *old_code,
		   unsigned char *new_code)
{
	unsigned char replaced[MCOUNT_INSN_SIZE];

	/*
	 * Note: Due to modules and __init, code can
	 *  disappear and change, we need to protect against faulting
	 *  as well as code changing. We do this by using the
	 *  probe_kernel_* functions.
	 *
	 * No real locking needed, this code is run through
	 * kstop_machine, or before SMP starts.
	 */

	/* read the text we want to modify */
	if (probe_kernel_read(replaced, (void *)ip, MCOUNT_INSN_SIZE))
		return -EFAULT;

	/* Make sure it is what we expect it to be */
	if (memcmp(replaced, old_code, MCOUNT_INSN_SIZE) != 0)
		return -EINVAL;

	/* replace the text with the new text */
	if (do_ftrace_mod_code(ip, new_code))
		return -EPERM;

	sync_core();

	return 0;
}
```