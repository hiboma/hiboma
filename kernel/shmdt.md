# shmdt(2)

## API

```c
#include <sys/types.h>
#include <sys/shm.h>

int shmdt(const void *shmaddr);
```

> shmdt() は呼び出したプロセスのアドレス空間から shmaddr で指定されたアドレスに配置された共有メモリーセグメントを分離 (detach) する。 分離する共有メモリーセグメントは、現在 shmaddr に付加されているものでなければならない。 shmaddr は、それを付加した時に shmat() が返した値に等しくなければならない。
成功した shmdt() コールはその共有メモリーセグメントに関連する shmid_ds 構造体のメンバーを以下のように更新する:
> 
> shm_dtime には現在の時刻が設定される。
> shm_lpid には呼び出したプロセスのプロセス ID が設定される。
> shm_nattch を 1 減少させる。 もし 0 になり、削除マークがあった場合は そのセグメントは削除される。
>
> https://linuxjm.osdn.jp/html/LDP_man-pages/man2/shmat.2.html

## Implementation

linux-3.10.0-327.el7.centos.x86_64

```c
/*
 * detach and kill segment if marked destroyed.
 * The work is done in shm_close.
 */
SYSCALL_DEFINE1(shmdt, char __user *, shmaddr)
{
	struct mm_struct *mm = current->mm;
	struct vm_area_struct *vma;
	unsigned long addr = (unsigned long)shmaddr;
	int retval = -EINVAL;
#ifdef CONFIG_MMU
	loff_t size = 0;
	struct vm_area_struct *next;
#endif

	if (addr & ~PAGE_MASK)
		return retval;

	down_write(&mm->mmap_sem);

	/*
	 * This function tries to be smart and unmap shm segments that
	 * were modified by partial mlock or munmap calls:
	 * - It first determines the size of the shm segment that should be
	 *   unmapped: It searches for a vma that is backed by shm and that
	 *   started at address shmaddr. It records it's size and then unmaps
	 *   it.
	 * - Then it unmaps all shm vmas that started at shmaddr and that
	 *   are within the initially determined size.
	 * Errors from do_munmap are ignored: the function only fails if
	 * it's called with invalid parameters or if it's called to unmap
	 * a part of a vma. Both calls in this function are for full vmas,
	 * the parameters are directly copied from the vma itself and always
	 * valid - therefore do_munmap cannot fail. (famous last words?)
	 */
	/*
	 * If it had been mremap()'d, the starting address would not
	 * match the usual checks anyway. So assume all vma's are
	 * above the starting address given.
	 */
	vma = find_vma(mm, addr);

#ifdef CONFIG_MMU

    // vm_area_struct をイテテートして共有メモリセグメントとして mmap しているリージョンを探す。
	while (vma) {
		next = vma->vm_next;

		/*
		 * Check if the starting address would match, i.e. it's
		 * a fragment created by mprotect() and/or munmap(), or it
		 * otherwise it starts at this address with no hassles.
		 */

        // vm_ops が shm_vm_ops であるかどうかで、SysV セグメントかどうかを判定している
        // うっかりアドレスを指定し間違えて別のリージョンを munmap しないようにしているためと思われる。面白い
		if ((vma->vm_ops == &shm_vm_ops) &&
			(vma->vm_start - addr)/PAGE_SIZE == vma->vm_pgoff) {

            // カーネル内部では mmap した anon リージョンと同等の扱いなのだろうか? inode を持つ
			size = file_inode(vma->vm_file)->i_size;
			do_munmap(mm, vma->vm_start, vma->vm_end - vma->vm_start);
			/*
			 * We discovered the size of the shm segment, so
			 * break out of here and fall through to the next
			 * loop that uses the size information to stop
			 * searching for matching vma's.
			 */

			retval = 0;
			vma = next;
			break;
		}
		vma = next;
	}

	/*
	 * We need look no further than the maximum address a fragment
	 * could possibly have landed at. Also cast things to loff_t to
	 * prevent overflows and make comparisons vs. equal-width types.
	 */
	size = PAGE_ALIGN(size);
	while (vma && (loff_t)(vma->vm_end - addr) <= size) {
		next = vma->vm_next;

		/* finding a matching vma now does not alter retval */
		if ((vma->vm_ops == &shm_vm_ops) &&
			(vma->vm_start - addr)/PAGE_SIZE == vma->vm_pgoff)

			do_munmap(mm, vma->vm_start, vma->vm_end - vma->vm_start);
		vma = next;
	}

#else /* CONFIG_MMU */
	/* under NOMMU conditions, the exact address to be destroyed must be
	 * given */
	if (vma && vma->vm_start == addr && vma->vm_ops == &shm_vm_ops) {
		do_munmap(mm, vma->vm_start, vma->vm_end - vma->vm_start);
		retval = 0;
	}

#endif

	up_write(&mm->mmap_sem);
	return retval;
}
```

 * 感想: 関数呼び出しでネストせずに実装していてシンプルだなー
 * shmdt(2) すると、セグメントが破棄される否かに関わらず、プロセスからは munmap(2) したのと同じ状態になるとみなしてよさそう

## shm_vm_ops

```c
static const struct vm_operations_struct shm_vm_ops = {
	.open	= shm_open,	/* callback for a new vm-area open */
	.close	= shm_close,	/* callback for when the vm-area is released */
	.fault	= shm_fault,
#if defined(CONFIG_NUMA)
	.set_policy = shm_set_policy,
	.get_policy = shm_get_policy,
#endif
};
```

shmdt -> munmap の中で呼び出されるのは `.close = shm_close`

## shm_close

```c
/*
 * remove the attach descriptor vma.
 * free memory for segment if it is marked destroyed.
 * The descriptor has already been removed from the current->mm->mmap list
 * and will later be kfree()d.
 */
static void shm_close(struct vm_area_struct *vma)
{
	struct file * file = vma->vm_file;
	struct shm_file_data *sfd = shm_file_data(file);
	struct shmid_kernel *shp;
	struct ipc_namespace *ns = sfd->ns;

	down_write(&shm_ids(ns).rwsem);
	/* remove from the list of attaches of the shm segment */
	shp = shm_lock(ns, sfd->id);
	BUG_ON(IS_ERR(shp));
	shp->shm_lprid = task_tgid_vnr(current); ♠
	shp->shm_dtim = get_seconds(); ♣
	shp->shm_nattch--; ♦
	if (shm_may_destroy(ns, shp)) ♦
		shm_destroy(ns, shp); ♦
	else
		shm_unlock(shp);
	up_write(&shm_ids(ns).rwsem);
}
```

この関数のなかで以下が実装されている

 * ♣ ... shm_dtime には現在の時刻が設定される。
 * ♠ ... shm_lpid には呼び出したプロセスのプロセス ID が設定される。
 * ♦ ... shm_nattch を 1 減少させる。 もし 0 になり、削除マークがあった場合は そのセグメントは削除される。

`ipcs -m` で見れるデータはこの中で扱っている `struct shmid_kernel *shp` に相当するのかなー？

```
$ LANG=C ipcs -m

------ Shared Memory Segments --------
key        shmid      owner      perms      bytes      nattch     status      
0x00000000 3866624    root       600        40         0                       
0x00000000 6029313    vagrant    600        40         10         dest         
0x00000000 5767170    vagrant    600        40         0                       
0x00000000 5865475    vagrant    600        40         0                       
0x00000000 5963780    vagrant    600        40         0                       
0x00000000 5996549    vagrant    600        40         0                       
0x00000000 6062086    vagrant    600        40         1                       
```

`shm_may_destroy` については [ここ](https://github.com/hiboma/hiboma/blob/master/kernel/proc/shm_rmid_forced.md) で取り上げたので省略する。
