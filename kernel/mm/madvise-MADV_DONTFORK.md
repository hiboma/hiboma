# madvise(2) + MADV_DONTFORK

## proof code

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/types.h> 
#include <sys/wait.h>
#include <signal.h>
#include <err.h>

void handle_sigsegv(int signo) { 
    if (signo == SIGSEGV) 
        fprintf(stderr, "received SIGSEGV\n");

    exit(1);
}

int main()
{
        ssize_t page_size = sysconf(_SC_PAGESIZE);
        ssize_t mmap_size = page_size * 1000;;

        char *p = mmap(NULL, mmap_size, PROT_READ|PROT_WRITE, 
		MAP_PRIVATE|MAP_ANONYMOUS, 0,0);

        if (p == MAP_FAILED)
                err(1, "mmap");
        
        /* try to cause pagefaults */
        for (int i = 0; i < mmap_size; i += page_size) 
            	p[i] = 'a';

        if (madvise(p, mmap_size, MADV_DONTFORK) < 0)
               err(1, "madvise");

        pid_t pid = fork();
        if(pid < 0) 
        	err(1, "fork"); 

        if(pid < 0) { 
          	/* child */
          	int status;
          	wait(&status);
          	exit(0);
        } else { 
          	if (signal(SIGSEGV, handle_sigsegv))
                	err(1, "signal");

          	// mmap-ed region is not copied to child process.
          	// reading/writing this region must cause SIGSEGV
          	p[0] = 'a';
        }   
}
```

```
$ ./a.out 
received SIGSEGV
```

```
[vagrant@localhost ~]$ pmap -x $( pgrep a.out )
9690:   ./a.out
Address           Kbytes     RSS   Dirty Mode  Mapping
0000000000400000       4       4       4 r-x-- a.out
0000000000600000       4       4       4 r---- a.out
0000000000601000       4       4       4 rw--- a.out
00007f8128a06000    4000    4000    4000 rw---   [ anon ] ★★★
00007f8128dee000    1756     228       0 r-x-- libc-2.17.so
00007f8128fa5000    2048       0       0 ----- libc-2.17.so
00007f81291a5000      16      16      16 r---- libc-2.17.so
00007f81291a9000       8       8       8 rw--- libc-2.17.so
00007f81291ab000      20      12      12 rw---   [ anon ]
00007f81291b0000     132     112       0 r-x-- ld-2.17.so
00007f81293c2000      12      12      12 rw---   [ anon ]
00007f81293d0000       4       4       4 rw---   [ anon ]
00007f81293d1000       4       4       4 r---- ld-2.17.so
00007f81293d2000       4       4       4 rw--- ld-2.17.so
00007f81293d3000       4       4       4 rw---   [ anon ]
00007fff7773b000     132       8       8 rw---   [ stack ]
00007fff77766000       8       4       0 r-x--   [ anon ]
ffffffffff600000       4       0       0 r-x--   [ anon ]
---------------- ------- ------- ------- 
total kB            8164    4428    4084
9691:   ./a.out
Address           Kbytes     RSS   Dirty Mode  Mapping
0000000000400000       4       4       4 r-x-- a.out
0000000000600000       4       4       4 r---- a.out
0000000000601000       4       4       4 rw--- a.out
00007f8128dee000    1756      44       0 r-x-- libc-2.17.so
00007f8128fa5000    2048       0       0 ----- libc-2.17.so
00007f81291a5000      16      16      16 r---- libc-2.17.so
00007f81291a9000       8       8       8 rw--- libc-2.17.so
00007f81291ab000      20      12      12 rw---   [ anon ]
00007f81291b0000     132      24       0 r-x-- ld-2.17.so
00007f81293c2000      12      12      12 rw---   [ anon ]
00007f81293d0000       4       4       4 rw---   [ anon ]
00007f81293d1000       4       4       4 r---- ld-2.17.so
00007f81293d2000       4       4       4 rw--- ld-2.17.so
00007f81293d3000       4       4       4 rw---   [ anon ]
00007fff7773b000     132       8       8 rw---   [ stack ]
00007fff77766000       8       0       0 r-x--   [ anon ]
ffffffffff600000       4       0       0 r-x--   [ anon ]
---------------- ------- ------- ------- 
total kB            4164     152      84
```

## MADV_DONTFORK

madvose(2) + MADV_DONTFORK set VM_DONTCOPY flag on vm_area_struct

```C
/*
 * We can potentially split a vm area into separate
 * areas, each area with its own behavior.
 */
static long madvise_behavior(struct vm_area_struct * vma,
		     struct vm_area_struct **prev,
		     unsigned long start, unsigned long end, int behavior)
{
	struct mm_struct * mm = vma->vm_mm;
	int error = 0;
	pgoff_t pgoff;
	unsigned long new_flags = vma->vm_flags;

...

	case MADV_DOFORK:
		if (vma->vm_flags & VM_IO) {
			error = -EINVAL;
			goto out;
		}
		new_flags &= ~VM_DONTCOPY;
		break;
```

## VM_DONTCOPY ?

If VM_DONTCOPY flag is set to vm_area_struct of a parent process, the vm_area_struct will not copied to the child process when fork(2) / clone(2).

```c
static int dup_mmap(struct mm_struct *mm, struct mm_struct *oldmm)
{
	struct vm_area_struct *mpnt, *tmp, *prev, **pprev;
	struct rb_node **rb_link, *rb_parent;
	int retval;
	unsigned long charge;
	struct mempolicy *pol;

...

	prev = NULL;
	for (mpnt = oldmm->mmap; mpnt; mpnt = mpnt->vm_next) {
		struct file *file;

		if (mpnt->vm_flags & VM_DONTCOPY) {
			vm_stat_account(mm, mpnt->vm_flags, mpnt->vm_file,
							-vma_pages(mpnt));
			continue;
		}

...


	prev = NULL;
	for (mpnt = oldmm->mmap; mpnt; mpnt = mpnt->vm_next) {
		struct file *file;

		if (mpnt->vm_flags & VM_DONTCOPY) {
			vm_stat_account(mm, mpnt->vm_flags, mpnt->vm_file,
							-vma_pages(mpnt));
            /* skip copy_page_range */
			continue;
		}


...

        /* copy parent mm to child process */
		retval = copy_page_range(mm, oldmm, mpnt);
```

So if the child process try to read/write the region, MMU cause a memory fault. 
