# /proc/sys/crypto/fips_enabled

```
-r--r--r-- 1 root root 0 Apr  2 16:49 /proc/sys/crypto/fips_enabled
```

## 定義

```c
static struct ctl_table crypto_sysctl_table[] = {
    {
        .ctl_name       = CTL_UNNUMBERED,
        .procname       = "fips_enabled",
        .data           = &fips_enabled,
        .maxlen         = sizeof(int),
        .mode           = 0444,
        .proc_handler   = &proc_dointvec
    },
    {
        .ctl_name = 0,
    },
};
```

root 権限を持っていても、書き込みできないよ

proc エントリのパーミッション検査

static int parse_table(int __user *name, int nlen,
		       void __user *oldval, size_t __user *oldlenp,
		       void __user *newval, size_t newlen,
		       struct ctl_table_root *root,
		       struct ctl_table *table)
{
	int n;
repeat:
	if (!nlen)
		return -ENOTDIR;
	if (get_user(n, name))
		return -EFAULT;
	for ( ; table->ctl_name || table->procname; table++) {
		if (!table->ctl_name)
			continue;
		if (n == table->ctl_name) {
			int error;
			if (table->child) {
				if (sysctl_perm(root, table, MAY_EXEC))
					return -EPERM;

int sysctl_perm(struct ctl_table_root *root, struct ctl_table *table, int op)
{
	int error;
	int mode;

	error = security_sysctl(table, op & (MAY_READ | MAY_WRITE | MAY_EXEC));
	if (error)
		return error;

	if (root->permissions)
		mode = root->permissions(root, current->nsproxy, table);
	else
		mode = table->mode;

	return test_perm(mode, op);
}


/*
 * sysctl_perm does NOT grant the superuser all rights automatically, because
 * some sysctl variables are readonly even to root.
 */

static int test_perm(int mode, int op)
{
	if (!current_euid())
		mode >>= 6;
	else if (in_egroup_p(0))
		mode >>= 3;
	if ((op & ~mode & (MAY_READ|MAY_WRITE|MAY_EXEC)) == 0)
		return 0;
	return -EACCES;
}

## fips_enabled は、いつ、どこで設定されるか?

下記を読むと、boot 時のパラメータで指定して、boot 時に決定される様子

```c
/* Process kernel command-line parameter at boot time. fips=0 or fips=1 */
static int fips_enable(char *str)
{
	fips_enabled = !!simple_strtol(str, NULL, 0);
	printk(KERN_INFO "fips mode: %s\n",
		fips_enabled ? "enabled" : "disabled");
	return 1;
}

__setup("fips=", fips_enable);
```

## __setup is 何?

```c
#define __setup(str, fn)					\
	__setup_param(str, fn, fn, 0)
```

マクロ地獄で分からん

```c
/*
 * Only for really core code.  See moduleparam.h for the normal way.
 *
 * Force the alignment so the compiler doesn't space elements of the
 * obs_kernel_param "array" too far apart in .init.setup.
 */
#define __setup_param(str, unique_id, fn, early)			\
	static const char __setup_str_##unique_id[] __initconst	\
		__aligned(1) = str; \
	static struct obs_kernel_param __setup_##unique_id	\
		__used __section(.init.setup)			\
		__attribute__((aligned((sizeof(long)))))	\
		= { __setup_str_##unique_id, fn, early }
```