# open(2) の O_DIRECT

 * ページキャッシュを経由しない
 * O_DIRECT を指定して read/write した場合 cached の値が増えないはず

## 検証用コード

http://nopipi.hatenablog.com/entry/2012/11/12/004704 のを拝借して改造して試した

 * O_DIRECT をつけると read/write ともにページキャッシュをモリモリ使う
 * O_DIRECT を外すと ページキャッシュ増えない
 * /tmp のファイルシステムは ext4

```c
#if 0
#!/bin/bash
CFLAGS="-O2 -std=gnu99 -W -Wall -fPIE -D_FORTIFY_SOURCE=2"
o=`basename $0`
o=".${o%.*}"
gcc ${CFLAGS} -o $o $0 && ./$o $*; exit
#endif

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

// http://nopipi.hatenablog.com/entry/2012/11/12/004704
int main()
{
        int in, out, ret;
        size_t size = 512 * 4096;
        char *buffer;

        /* allocate buffer memory */
        if (posix_memalign((void **)&buffer, 512, size)) {
		perror("posix_memalign");
		exit(1);
	}

	unlink("/tmp/file_out");

	//O_DIRECT
        in  = open("/tmp/524MB.txt", O_RDONLY|O_DIRECT);
        out = open("/tmp/file_out",  O_WRONLY|O_CREAT|O_TRUNC|O_DIRECT, S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP );

	for (;;) {
		ret = read(in, buffer, size);
		if (ret == 0) {
			break;
		}
		else if (ret == -1)  {
			if (errno == EINTR) {
				continue;
			}

			perror("read");
			exit(1);
		}

		/* 書き込み retry めんどいのでスルー ... */
		ret = write(out, buffer, size);
		if (ret == -1) {
			perror("write");
			exit(1);
		}
	}

	exit(0);
}
```

## カーネルのコード

### open(2)

__dentry_open で O_DIRECT 出来るメソッドがあるかどうか見る

 * address_space_operations の .direct_IO
 * address_space_operations の .get_xip_mem

```c
//    do_filp_open
// -> nameidata_to_filp
// -> __dentry_open
//
static struct file *__dentry_open(struct dentry *dentry, struct vfsmount *mnt,
					struct file *f,
					int (*open)(struct inode *, struct file *),
					const struct cred *cred)
{
//...

	/* NB: we're sure to have correct a_ops only after f_op->open */
	if (f->f_flags & O_DIRECT) {
		if (!f->f_mapping->a_ops ||
		    ((!f->f_mapping->a_ops->direct_IO) &&
		    (!f->f_mapping->a_ops->get_xip_mem))) {
			fput(f);
			f = ERR_PTR(-EINVAL);
		}
	}
```