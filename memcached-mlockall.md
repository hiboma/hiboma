# memcached の -k オプションと mlockall(2)

memcached は `-k` オプションをつけて起動すると、ページをロックする

> -k     Lock down all paged memory. This is a somewhat dangerous option with large caches, so consult the README and memcached homepage for configuration suggestions.

すなわち、memcached がスワップしない君

## 実装

#### memcached.c

-k オプションを有効にすると、 lock_memory が true になる

```c
        case 'k':
            lock_memory = true;
            break;
```

ロックの実装は、 mlockall(2) を使っています

```c
    /* lock paged memory if needed */
    if (lock_memory) {
#ifdef HAVE_MLOCKALL
        int res = mlockall(MCL_CURRENT | MCL_FUTURE);
        if (res != 0) {
            fprintf(stderr, "warning: -k invalid, mlockall() failed: %s\n",
                    strerror(errno));
        }
#else
        fprintf(stderr, "warning: -k invalid, mlockall() not supported on this platform.  proceeding without.\n");
#endif
    }
```

これだけ。なかなか簡易の実装ですね

## mlockall とは?

http://linuxjm.sourceforge.jp/html/LDP_man-pages/man2/mlock.2.html

```
mlock() と mlockall() はそれぞれ、呼び出し元プロセスの仮想アドレス空間の一部または全部を RAM 上にロックし、
メモリがスワップエリアにページングされるのを防ぐ
````

```
MCL_CURRENT
現在、プロセスのアドレス空間にマップされている全てのページをロックする。
MCL_FUTURE
将来、プロセスのアドレス空間にマップされる全てのページをロックする。 例えば、ヒープ (heap) やスタックの成長により新しく必要になったページだけで なく、新しくメモリマップされたファイルや共有メモリ領域もロックされる。
```

mlock/mlockall しておくと、カーネルがスワップアウトするページを探す際に mlock されたページを対象外とする ( VM_LOCKED ) 、てな挙動

#### do_mlockall

 * vm_area_struct をイテレートして、 VM_LOCKED を立てている
 * mlock_fixup がとちょっと複雑

```c
static int do_mlockall(int flags)
{
	struct vm_area_struct * vma, * prev = NULL;
	unsigned int def_flags = 0;

	if (flags & MCL_FUTURE)
		def_flags = VM_LOCKED;
	current->mm->def_flags = def_flags;
	if (flags == MCL_FUTURE)
		goto out;

	for (vma = current->mm->mmap; vma ; vma = prev->vm_next) {
		unsigned int newflags;

		newflags = vma->vm_flags | VM_LOCKED;
		if (!(flags & MCL_CURRENT))
			newflags &= ~VM_LOCKED;

		/* Ignore errors */
		mlock_fixup(vma, &prev, vma->vm_start, vma->vm_end, newflags);
	}
out:
	return 0;
}
```

## somewhat dangerous option

 * OS の RAM 搭載量と、キャッシュの使用量のバランスを考えて使えということだろう
 * mlockall(2) の挙動を理解できる人に可否を問うべき

## SEE ALSO

 * http://threebrothers.org/brendan/blog/using-memcached-k-prevent-paging/
   * ulimit の値に注意
 * http://mkosaki.blog46.fc2.com/blog-entry-352.html