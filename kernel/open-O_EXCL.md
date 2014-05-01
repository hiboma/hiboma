# open(2) の O_EXCL

```c
/*
 * Note that the low bits of the passed in "open_flag"
 * are not the same as in the local variable "flag". See
 * open_to_namei_flags() for more details.
 */
struct file *do_filp_open(int dfd, struct filename *filename,
		int open_flag, int mode, int acc_mode)
{
	struct file *filp;
	struct nameidata nd;
	int error;
	struct path path;
	struct dentry *dir;
	int count = 0;
	int will_truncate;
	int flag = open_to_namei_flags(open_flag);
	int got_write = false;
	const char *pathname = filename->name;

//...

	nd.flags &= ~LOOKUP_PARENT;
	nd.flags |= LOOKUP_CREATE | LOOKUP_OPEN;
	if (flag & O_EXCL)
		nd.flags |= LOOKUP_EXCL;
```