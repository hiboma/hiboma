
## [struct address_space_operations](http://lxr.free-electrons.com/source/include/linux/fs.h?v=2.6.32#L570) の実装

 * struct file_operations と一緒に実装する必要あり
 * RAMベースのファイルシステムでは address_space = ページキャッシュ がストレージとして機能する

### ramfs

```c
const struct address_space_operations ramfs_aops = {
	.readpage	= simple_readpage,
	.write_begin	= simple_write_begin,
	.write_end	= simple_write_end,
	.set_page_dirty = __set_page_dirty_no_writeback,
};
```

#### .write_begin

 * ページに書き込むにはまずはページの確保が必要
   * 新しく割り当てるか? ページキャッシュから探索して見つかるか?
   * ページは .write_begin 〜 .write_end の間ロックされる
   * ページ確保は grab_cache_page_write_begin で実装される

```c
int simple_write_begin(struct file *file, struct address_space *mapping,
			loff_t pos, unsigned len, unsigned flags,
			struct page **pagep, void **fsdata)
{
	struct page *page;
	pgoff_t index;
	unsigned from;

	index = pos >> PAGE_CACHE_SHIFT;
	from = pos & (PAGE_CACHE_SIZE - 1);

	page = grab_cache_page_write_begin(mapping, index, flags);
	if (!page)
		return -ENOMEM;

	*pagep = page;

	return simple_prepare_write(file, page, from, from+len);
}
```

grab_cache_page_write_begin

 * find_lock_page
   * ページキャッシュからページを探索、ロックを取る
 * __page_cache_alloc
   * 新しくページを確保したら LRU に繋ぐ add_to_page_cache_lru

```c
/*
 * Find or create a page at the given pagecache position. Return the locked
 * page. This function is specifically for buffered writes.
 */
struct page *grab_cache_page_write_begin(struct address_space *mapping,
					pgoff_t index, unsigned flags)
{
	int status;
	struct page *page;
	gfp_t gfp_notmask = 0;
	if (flags & AOP_FLAG_NOFS)
		gfp_notmask = __GFP_FS;
repeat:
    // ページキャッシュで探索
    // 並行して同じページに書き込みが内容にロックを取る
    // ページのロックを取れない場合は TASK_UNINTERRUPTIBLE
	page = find_lock_page(mapping, index);
	if (likely(page))
		return page;

    // ページの割り当て
	page = __page_cache_alloc(mapping_gfp_mask(mapping) & ~gfp_notmask);
	if (!page)
		return NULL;

    // ページキャッシュLRU への追加
	status = add_to_page_cache_lru(page, mapping, index,
						GFP_KERNEL & ~gfp_notmask);
	if (unlikely(status)) {
		page_cache_release(page);
		if (status == -EEXIST)
			goto repeat;
		return NULL;
	}
	return page;
}
EXPORT_SYMBOL(grab_cache_page_write_begin);
```

simple_prepare_write

 * 書き込んだサイズ ( to - from ) が PAGE_CACHE_SIZE 以下なら余った部分を zero 化
   * 余計なデータがユーザ空間から参照できないようにするため?

```c
int simple_prepare_write(struct file *file, struct page *page,
			unsigned from, unsigned to)
{
	if (!PageUptodate(page)) {
		if (to - from != PAGE_CACHE_SIZE)
			zero_user_segments(page,
				0, from,
				to, PAGE_CACHE_SIZE);
	}
	return 0;
}
```

#### .write_end

 * ページに書き込んだサイズがページ以下なら memset zero化
   * commit_write でページを dirty に

```c
int simple_write_end(struct file *file, struct address_space *mapping,
			loff_t pos, unsigned len, unsigned copied,
			struct page *page, void *fsdata)
{
	unsigned from = pos & (PAGE_CACHE_SIZE - 1);

	/* zero the stale part of the page if we did a short copy */
	if (copied < len) {
        // ?
		void *kaddr = kmap_atomic(page, KM_USER0);

        // kaddr   from               copied  len
        // /------/-------------------/------/
        // |      |###################|      |
        // +--------------------------\------+
        //                           kaddr+from+len
		memset(kaddr + from + copied, 0, len - copied);
        // アーキテチャ依存 x86 は空になっている
		flush_dcache_page(page);
		kunmap_atomic(kaddr, KM_USER0);
	}

	simple_commit_write(file, page, from, from+copied);

	unlock_page(page);
	page_cache_release(page);

	return copied;
}
```

simple_commit_write

 * set_page_dirty でページに dirty フラグを立てる
   * 内部で address_space の .set_page_dirty が呼ばれている
   * RAMベースだと __set_page_dirty_no_writeback 呼ぶだけ
   
```c
static int simple_commit_write(struct file *file, struct page *page,
			       unsigned from, unsigned to)
{
	struct inode *inode = page->mapping->host;
	loff_t pos = ((loff_t)page->index << PAGE_CACHE_SHIFT) + to;

	if (!PageUptodate(page))
		SetPageUptodate(page);
	/*
	 * No need to use i_size_read() here, the i_size
	 * cannot change under us because we hold the i_mutex.
	 */
	if (pos > inode->i_size)
		i_size_write(inode, pos);
	set_page_dirty(page);
	return 0;
}
```

__set_page_dirty_no_writeback

``` c
/*
 * For address_spaces which do not use buffers nor write back.
 */
int __set_page_dirty_no_writeback(struct page *page)
{
	if (!PageDirty(page))
		SetPageDirty(page);
	return 0;
}
```

### tmpfs

 * tmpfs はスワップも絡んでくるので大分ややこしい

```c
static const struct address_space_operations shmem_aops = {
	.writepage	= shmem_writepage,
	.set_page_dirty	= __set_page_dirty_no_writeback,
#ifdef CONFIG_TMPFS
	.write_begin	= shmem_write_begin,
	.write_end	= shmem_write_end,
#endif
	.migratepage	= migrate_page,
    // メモリが物故割れた際にページを取り除く?らしい
	.error_remove_page = generic_error_remove_page,
};
```

### .writepage

 * alloc_page群で shrink_page_list を呼び出し際に pageout の中で呼び出される
   * mapping->a_ops->writepage
 * Backing Store がディスクであれば Dirty なページの writeback
 * tmpfs は Backing Store が swap なので swap を利用しての writeback になる
   * ページキャッシュ => スワップキャッシュ => swap out ?
   * swap page という単位で page cache にマッピングされている
 * get_swap_page -> swap_writepage -> swapcache_free
   * swap を writeback する際に使うページを スワップキャッシュと呼ぶのだろうか?

```c
/*
 * Move the page from the page cache to the swap cache.
 */
static int shmem_writepage(struct page *page, struct writeback_control *wbc)
{
	struct shmem_inode_info *info;
	struct address_space *mapping;
	struct inode *inode;
	swp_entry_t swap;
	pgoff_t index;

	BUG_ON(!PageLocked(page));
	mapping = page->mapping;
    // mapping の中でのオフセット (論理的なインデックス?)
	index = page->index;
    // オーナー。block_device か swap か
	inode = mapping->host;
	info = SHMEM_I(inode);

    // redirty => SetPageDirty しなおして別のページを対象にする?
    // mlock(2) ?
	if (info->flags & VM_LOCKED)
		goto redirty;
    // swap page が無い ( total_swap_pages はグローバルな統計 )
	if (!total_swap_pages)
		goto redirty;

	/*
	 * shmem_backing_dev_info's capabilities prevent regular writeback or
	 * sync from ever calling shmem_writepage; but a stacking filesystem
	 * might use ->writepage of its underlying filesystem, in which case
	 * tmpfs should write out to swap only in response to memory pressure,
	 * and not for the writeback threads or sync.
	 */
    // スタッキングファイルシステムで下位のファイルシステムの writepage を呼び出すケース
	if (!wbc->for_reclaim) {
		WARN_ON_ONCE(1);	/* Still happens? Tell us about it! */
		goto redirty;
	}

    // swap 用ページ
	swap = get_swap_page();
	if (!swap.val)
		goto redirty;

	/*
	 * Add inode to shmem_unuse()'s list of swapped-out inodes,
	 * if it's not already there.  Do it now before the page is
	 * moved to swap cache, when its pagelock no longer protects
	 * the inode from eviction.  But don't unlock the mutex until
	 * we've incremented swapped, because shmem_unuse_inode() will
	 * prune a !swapped inode from the swaplist under this mutex.
	 */
	mutex_lock(&shmem_swaplist_mutex);

    // inode を swap のリストに入れとく
	if (list_empty(&info->swaplist))
    // page が swap cache に移ると pagelock で eviction を保護できないから
		list_add_tail(&info->swaplist, &shmem_swaplist);

	if (add_to_swap_cache(page, swap, GFP_ATOMIC) == 0) {
		swap_shmem_alloc(swap);
        // page キャシュから削除 (address_space の radix tree から削除)
		shmem_delete_from_page_cache(page, swp_to_radix_entry(swap));

		spin_lock(&info->lock);
		info->swapped++;
		shmem_recalc_inode(inode);
		spin_unlock(&info->lock);

		mutex_unlock(&shmem_swaplist_mutex);
		BUG_ON(page_mapped(page));

        // swap デバイスに書き出す
		swap_writepage(page, wbc);
		return 0;
	}

	mutex_unlock(&shmem_swaplist_mutex);
    // cgroup の swap チャージを減らしたり
	swapcache_free(swap, NULL);
redirty:
	set_page_dirty(page);
	if (wbc->for_reclaim)
		return AOP_WRITEPAGE_ACTIVATE;	/* Return with page locked */
	unlock_page(page);
	return 0;
}
```

### vfs_write から address_space_operations に下るところを追う

[generic_perform_write](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L2212) is 複雑 !!!

 * .write_begin 
   * [simple_write_begin](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L353)
     * [grab_cache_page_write_begin](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L2184)
       * find_lock_page で アドレス空間から指定したインデックスを持つ struct *page を返す。page は PG_locked
         * ロックを取れない場合は TASK_UNINTERRUPTIBLE でブロック
           * 並行して同一のページに書き込みを防ぐため
         * struct *page は ページフレーム に対応 => 同じページフレームに複数のタスク(割り込みコンテキストは?)から同時書き込みできない
       * [__page_cache_alloc](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L483)
         * struct *page を割り当て
           * NUMAに対応するためにどのメモリノードからページを取るか allow_pages_excat_node で指定
         * alloc_pages 以下は複雑なので別件で追う
       * [add_to_page_cache_lru](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L457)
         * mapping_cap_swap_backed(struct address_space) で address_space が swap 可能かどうかを見ている
           * backing_dev_info の capabilities に BDI_CAP_SWAP_BACKED が立っているか否か
           * tmpfs の場合 true
             * SetPageSwapBacked(page) ???
         * [add_to_page_cache](http://lxr.free-electrons.com/source/include/linux/pagemap.h?v=2.6.32#L443) ???
         * lru_cache_add_file => LRU_INACTIVE_FILE リストに繋ぐ
         * lru_cache_add_anon => LRU_INACTIVE_ANON リストに繋ぐ
   * [simple_prepare_write](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L341)
     * [zero_user_segments](http://lxr.free-electrons.com/source/include/linux/highmem.h?v=2.6.32#L140) 
       * memsetで struct pageを '\0'初期化 [refs](http://lwn.net/Articles/234564/)
 * [iov_iter_fault_in_readable](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L1976)
   * ユーザ空間のアドレスを前もってページフォールト起こしておく `prefault`
   * ページフォルト失敗したら不正なアドレスてことで、止める
     * [fault_in_pages_readable](http://lxr.free-electrons.com/source/include/linux/pagemap.h?v=2.6.32#L413)
 * pagefault_disable() ???
 * [iov_iter_copy_from_user_atomic](http://lxr.free-electrons.com/source/mm/filemap.c?v=2.6.32#L1892)
   * ユーザ空間のバッファをカーネル空間にコピるイテレータ
     * __copy_from_user ( Architecure Depends ) を繰り返す
 * pagefault_enable() ???
 * flush_dcache_page
   * x86 だと何も定義されてないぞ?
 * mark_page_accessed ???
 * .write_end
   * [simple_write_end](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L391)
     * [simple_commit_write](http://lxr.free-electrons.com/source/fs/libfs.c?v=2.6.32#L373)
     * [set_page_dirty](http://lxr.free-electrons.com/source/mm/page-writeback.c?v=2.6.32#L1168)
       * .set_page_dirty or [__set_page_dirty_buffers](http://lxr.free-electrons.com/source/fs/buffer.c?v=2.6.32#L710)
       * ページの内容が変わったので dirty になる
     * unlock_page で PG_locked を落とす
     * page_cache_release で参照カウントをデクリメント

struct *page の 割り当て、LRUへの追加、ユーザ空間のデータをコピー、page に書き込み、page is dirty

### __copy_from_user ( Architecure Depends )

```c
int __copy_from_user(void *dst, const void __user *src, unsigned size)
{
        int ret = 0;

        might_fault();
        if (!__builtin_constant_p(size))
                return copy_user_generic(dst, (__force void *)src, size);
        switch (size) {
        case 1:__get_user_asm(*(u8 *)dst, (u8 __user *)src,
                              ret, "b", "b", "=q", 1); 
                return ret;
        case 2:__get_user_asm(*(u16 *)dst, (u16 __user *)src,
                              ret, "w", "w", "=r", 2); 
                return ret;
        case 4:__get_user_asm(*(u32 *)dst, (u32 __user *)src,
                              ret, "l", "k", "=r", 4); 
                return ret;
        case 8:__get_user_asm(*(u64 *)dst, (u64 __user *)src,
                              ret, "q", "", "=r", 8); 
                return ret;
        case 10: 
                __get_user_asm(*(u64 *)dst, (u64 __user *)src,
                               ret, "q", "", "=r", 10);
                if (unlikely(ret))
                        return ret;
                __get_user_asm(*(u16 *)(8 + (char *)dst),
                               (u16 __user *)(8 + (char __user *)src),
                               ret, "w", "w", "=r", 2); 
                return ret;
        case 16: 
                __get_user_asm(*(u64 *)dst, (u64 __user *)src,
                               ret, "q", "", "=r", 16);
                if (unlikely(ret))
                        return ret;
                __get_user_asm(*(u64 *)(8 + (char *)dst),
                               (u64 __user *)(8 + (char __user *)src),
                               ret, "q", "", "=r", 8); 
                return ret;
        default:
                return copy_user_generic(dst, (__force void *)src, size);
        }   
}
```

### copy_user_generic

```
/* Some CPUs run faster using the string copy instructions.
 * This is also a lot simpler. Use them when possible.
 *
 * Only 4GB of copy is supported. This shouldn't be a problem
 * because the kernel normally only writes from/to page sized chunks
 * even if user space passed a longer buffer.
 * And more would be dangerous because both Intel and AMD have
 * errata with rep movsq > 4GB. If someone feels the need to fix
 * this please consider this.
 *
 * Input:
 * rdi destination
 * rsi source
 * rdx count
 *
 * Output:
 * eax uncopied bytes or 0 if successful.
 */
ENTRY(copy_user_generic_string)
	CFI_STARTPROC
	andl %edx,%edx
	jz 4f
	cmpl $8,%edx
	jb 2f		/* less than 8 bytes, go to byte copy loop */
	ALIGN_DESTINATION
	movl %edx,%ecx
	shrl $3,%ecx
	andl $7,%edx
1:	rep
	movsq
2:	movl %edx,%ecx
3:	rep
	movsb
4:	xorl %eax,%eax
	ret

	.section .fixup,"ax"
11:	lea (%rdx,%rcx,8),%rcx
12:	movl %ecx,%edx		/* ecx is zerorest also */
	jmp copy_user_handle_tail
	.previous

	.section __ex_table,"a"
	.align 8
	.quad 1b,11b
	.quad 3b,12b
	.previous
	CFI_ENDPROC
ENDPROC(copy_user_generic_string)
```

#### vboxfs
 
```c
struct address_space_operations sf_reg_aops =
{
    .readpage      = sf_readpage,
    .writepage     = sf_writepage,
# if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 24)
    .write_begin   = sf_write_begin,
    .write_end     = sf_write_end,
# else
    .prepare_write = simple_prepare_write,
    .commit_write  = simple_commit_write,
# endif
};
#endif
```

 * sf_write_begin は simple_write_begin のラッパーで特になんもしてない (`TRACE()`を埋め込んでるだけ)

 ```c
# if LINUX_VERSION_CODE >= KERNEL_VERSION(2, 6, 24)
int sf_write_begin(struct file *file, struct address_space *mapping, loff_t pos,
                   unsigned len, unsigned flags, struct page **pagep, void **fsdata)
{
    TRACE();
    // zero_user_segments で page の中身を ゼロ化
    return simple_write_begin(file, mapping, pos, len, flags, pagep, fsdata);
}
```

```c
static inline void zero_user_segments(struct page *page,
	unsigned start1, unsigned end1,
	unsigned start2, unsigned end2)
{
    // kmap
	void *kaddr = kmap_atomic(page, KM_USER0);

	BUG_ON(end1 > PAGE_SIZE || end2 > PAGE_SIZE);

    // kmap しといたら memset とかでいじれるということでおk?
	if (end1 > start1)
		memset(kaddr + start1, 0, end1 - start1);

	if (end2 > start2)
		memset(kaddr + start2, 0, end2 - start2);

	kunmap_atomic(kaddr, KM_USER0);
	flush_dcache_page(page);
}
```

 * sf_write_end は ページを kmap でごにょったり sf_reg_write_aux でホストOSと通信
 * `kmap、システムの任意のページのカーネル仮想アドレスをかえします`

```c
int sf_write_end(struct file *file, struct address_space *mapping, loff_t pos,
                 unsigned len, unsigned copied, struct page *page, void *fsdata)
{
    struct inode *inode = mapping->host;
    struct sf_glob_info *sf_g = GET_GLOB_INFO(inode->i_sb);
    struct sf_reg_info *sf_r = file->private_data;
    void *buf;
    // ファイルポジションからオフセットの算出
    unsigned from = pos & (PAGE_SIZE - 1);
    uint32_t nwritten = len;
    int err;

    TRACE();

    // buf = kmap(page)`
    // http://wiki.bit-hive.com/linuxkernelmemo/pg/HighMemory
    // 永続的カーネルマッピング Highメモリのページフレームをリニアドレスにマッピングする
    buf = kmap(page);
    err = sf_reg_write_aux(__func__, sf_g, sf_r, buf+from, &nwritten, pos);

    // マッピングの解除。必ず呼ばんといかんらしい
    kunmap(page);

    // PG_uptodate ... ページの読み込みが完了したときに設定する
    if (!PageUptodate(page) && err == PAGE_SIZE)
        SetPageUptodate(page);

    if (err >= 0) {
        pos += nwritten;
        if (pos > inode->i_size)
            inode->i_size = pos;
    }

    // simple_write_begin の grab_cache_page_write_begin が返す page は PG_locked なので
    // ここで PG_locked を外す (page を待ってブロックしている他タスクも起床される)
    unlock_page(page);

    // page の参照カウントをデクリメント
    // 参照カウントは simple_write_begin の中で page_cache_get されてインクリメントされている
    page_cache_release(page);

    return nwritten;
}

# endif /* KERNEL_VERSION 
```

 * sf_reg_write_aux は vboxCallWrite を呼んで buf の中身をホストOSのファイルシステムに書き込んでるはず
   * void *buf は kmap でリニアアドレス(物理アドレス) にマッピングされてる => 速いらしい
   * vboxCallWrite がホストOSとどうやり取りしてるかは TODO

```c
static int sf_reg_write_aux(const char *caller, struct sf_glob_info *sf_g,
                            struct sf_reg_info *sf_r, void *buf,
                            uint32_t *nwritten, uint64_t pos)
{
    /** @todo bird: yes, kmap() and kmalloc() input only. Since the buffer is
     *        contiguous in physical memory (kmalloc or single page), we should
     *        use a physical address here to speed things up. */

    // src/VBox/Additions/common/VBoxGuestLib/VBoxGuestR0LibSharedFolders.c
    int rc = vboxCallWrite(&client_handle, &sf_g->map, sf_r->handle,
                           pos, nwritten, buf, false /* already locked? */);
    if (RT_FAILURE(rc))
    {
        LogFunc(("vboxCallWrite failed. caller=%s, rc=%Rrc\n",
                    caller, rc));
        return -EPROTO;
    }
    return 0;
}
```
