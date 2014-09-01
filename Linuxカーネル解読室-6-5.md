# 排他機構の利用例 - ディィレクトリエントリキャッシュ

## 6.5.1 ディレクトリエントリキャッシュ

#### struct dentry

```c
struct dentry {
	atomic_t d_count;
	unsigned int d_flags;		/* protected by d_lock */
	spinlock_t d_lock;		/* per dentry lock */
	int d_mounted;
	struct inode *d_inode;		/* Where the name belongs to - NULL is
					 * negative */
	/*
	 * The next three fields are touched by __d_lookup.  Place them here
	 * so they all fit in a cache line.
	 */
	struct hlist_node d_hash;	/* lookup hash list */
	struct dentry *d_parent;	/* parent directory */
	struct qstr d_name;

	struct list_head d_lru;		/* LRU list */
	/*
	 * d_child and d_rcu can share memory
	 */
	union {
		struct list_head d_child;	/* child of parent list */
	 	struct rcu_head d_rcu;
	} d_u;
	struct list_head d_subdirs;	/* our children */
	struct list_head d_alias;	/* inode alias list */
	unsigned long d_time;		/* used by d_revalidate */
	const struct dentry_operations *d_op;
	struct super_block *d_sb;	/* The root of the dentry tree */
	void *d_fsdata;			/* fs-specific data */

	unsigned char d_iname[DNAME_INLINE_LEN_MIN];	/* small names */
};
```

 * d_lookup
 * d_free
 * d_move

が取り上げられている。 https://github.com/hiboma/hiboma/blob/master/kernel/dentry_cache.md を読んで思い出す

#### dentry キャッシュの保護

dentry を操作するスコープによって複数のロックが使い分けされている

```
/*
locking rules:
                big lock        dcache_lock     d_lock   may block
d_revalidate:   no              no              no       yes
d_hash          no              no              no       yes
d_compare:      no              yes             yes      no
d_delete:       no              yes             no       no
d_release:      no              no              no       yes
d_iput:         no              no              no       yes
 */
```

 * パス名検索による dentry 参照を保護
   * RCU
 * dentry ツリー操作同士の保護 is ?
   * スピンロック
   * dentry ツリー全体を保護する dcache_lock で保護
   * include/dcache.h で `extern spinlock_t dcache_lock;` として宣言されたグローバル変数
 * dentry エントリ単体の保護
   * スピンロック
   * `spinlock_t d_lock`
 * ファイルの rename を保護
   * シーケンスカウンタロック
   * `extern seqlock_t rename_lock;`


## 6.5.1.1 シーケンスカウンタロックによる保護

ロックの仕組みが複数併用されていてとても複雑 ...

```c
/**
 * d_lookup - search for a dentry
 * @parent: parent dentry
 * @name: qstr of name we wish to find
 *
 * Searches the children of the parent dentry for the name in question. If
 * the dentry is found its reference count is incremented and the dentry
 * is returned. The caller must use dput to free the entry when it has
 * finished using it. %NULL is returned on failure.
 *
 * __d_lookup is dcache_lock free. The hash list is protected using RCU.
 * Memory barriers are used while updating and doing lockless traversal. 
 * To avoid races with d_move while rename is happening, d_lock is used.
 *
 * Overflows in memcmp(), while d_move, are avoided by keeping the length
 * and name pointer in one structure pointed by d_qstr.
 *
 * rcu_read_lock() and rcu_read_unlock() are used to disable preemption while
 * lookup is going on.
 *
 * The dentry unused LRU is not updated even if lookup finds the required dentry
 * in there. It is updated in places such as prune_dcache, shrink_dcache_sb,
 * select_parent and __dget_locked. This laziness saves lookup from dcache_lock
 * acquisition.
 *
 * d_lookup() is protected against the concurrent renames in some unrelated
 * directory using the seqlockt_t rename_lock.
 */

struct dentry * d_lookup(struct dentry * parent, struct qstr * name)
{
	struct dentry * dentry = NULL;
	unsigned long seq;

        do {
                /* lookup 中に rename されていたら  __d_lookup をやり直す */
                seq = read_seqbegin(&rename_lock);
                dentry = __d_lookup(parent, name);
                if (dentry)
			break;
	} while (read_seqretry(&rename_lock, seq));
	return dentry;
}

struct dentry * __d_lookup(struct dentry * parent, struct qstr * name)
{
	unsigned int len = name->len;
	unsigned int hash = name->hash;
	const unsigned char *str = name->name;
	struct hlist_head *head = d_hash(parent,hash);
	struct dentry *found = NULL;
	struct hlist_node *node;
	struct dentry *dentry;

	rcu_read_lock();
	
	hlist_for_each_entry_rcu(dentry, node, head, d_hash) {
		struct qstr *qstr;

		if (dentry->d_name.hash != hash)
			continue;
		if (dentry->d_parent != parent)
			continue;

		spin_lock(&dentry->d_lock);

		/*
		 * Recheck the dentry after taking the lock - d_move may have
		 * changed things.  Don't bother checking the hash because we're
		 * about to compare the whole name anyway.
		 */
		if (dentry->d_parent != parent)
			goto next;

		/* non-existing due to RCU? */
		if (d_unhashed(dentry))
			goto next;

		/*
		 * It is safe to compare names since d_move() cannot
		 * change the qstr (protected by d_lock).
		 */
		qstr = &dentry->d_name;
		if (parent->d_op && parent->d_op->d_compare) {
			if (parent->d_op->d_compare(parent, qstr, name))
				goto next;
		} else {
			if (qstr->len != len)
				goto next;
			if (memcmp(qstr->name, str, len))
				goto next;
		}

        // アトミックにインクリメント
		atomic_inc(&dentry->d_count);
		found = dentry;
		spin_unlock(&dentry->d_lock);
		break;
next:
		spin_unlock(&dentry->d_lock);
 	}
 	rcu_read_unlock();

 	return found;
}

/**
 * d_move - move a dentry
 * @dentry: entry to move
 * @target: new dentry
 *
 * Update the dcache to reflect the move of a file name. Negative
 * dcache entries should not be moved in this way.
 */

void d_move(struct dentry * dentry, struct dentry * target)
{
    // dentryツリー全体を保護するスピンロック
    // d_move は同時に 1CPU からのみ呼び出すことできる
	spin_lock(&dcache_lock);
	d_move_locked(dentry, target);
	spin_unlock(&dcache_lock);
}

/*
 * d_move_locked - move a dentry
 * @dentry: entry to move
 * @target: new dentry
 *
 * Update the dcache to reflect the move of a file name. Negative
 * dcache entries should not be moved in this way.
 */
static void d_move_locked(struct dentry * dentry, struct dentry * target)
{
	struct hlist_head *list;

	if (!dentry->d_inode)
		printk(KERN_WARNING "VFS: moving negative dcache entry\n");

    /*
     * dentry の移動 = rename の操作のロックを取る
     * d_lookup が read_seqbegin を取っている 
     */
	write_seqlock(&rename_lock);

    // デッドロック防止のために低位アドレスのものから先にスピンロックをかける
    // ここのスピンロックは、 __d_lookup との排他に使われる
    // __d_lookup が dentry を参照中に名前やハッシュ値が書き変わってしまうのを防ぐ
	/*
	 * XXXX: do we really need to take target->d_lock?
	 */
	if (target < dentry) {
		spin_lock(&target->d_lock);
		spin_lock_nested(&dentry->d_lock, DENTRY_D_LOCK_NESTED);
	} else {
		spin_lock(&dentry->d_lock);
		spin_lock_nested(&target->d_lock, DENTRY_D_LOCK_NESTED);
	}

	/* Move the dentry to the target hash queue, if on different bucket */
	if (d_unhashed(dentry))
		goto already_unhashed;

	hlist_del_rcu(&dentry->d_hash);

already_unhashed:
	list = d_hash(target->d_parent, target->d_name.hash);
	__d_rehash(dentry, list);

	/* Unhash the target: dput() will then get rid of it */
	__d_drop(target);

	list_del(&dentry->d_u.d_child);
	list_del(&target->d_u.d_child);

	/* Switch the names.. */
    // dentry .d_name と .d_inaem の交換
	switch_names(dentry, target);

    // ハッシュ値を交換
	swap(dentry->d_name.hash, target->d_name.hash);

	/* ... and switch the parents */
	if (IS_ROOT(dentry)) {
		dentry->d_parent = target->d_parent;
		target->d_parent = target;
		INIT_LIST_HEAD(&target->d_u.d_child);
	} else {
		swap(dentry->d_parent, target->d_parent);

		/* And add them back to the (new) parent lists */
		list_add(&target->d_u.d_child, &target->d_parent->d_subdirs);
	}

	list_add(&dentry->d_u.d_child, &dentry->d_parent->d_subdirs);
	spin_unlock(&target->d_lock);

    // fsnotiry の通知だ!
	fsnotify_d_move(dentry);

    // dentry の更新が終わったのでスピンロック解除。
	spin_unlock(&dentry->d_lock);

    /* rename 終わり */
    /* もし同時に __d_lookup されていた場合、 __d_lookup はやり直しされる */
	write_sequnlock(&rename_lock);
}

/*
 * no dcache_lock, please.  The caller must decrement dentry_stat.nr_dentry
 * inside dcache_lock.
 */
static void d_free(struct dentry *dentry)
{
	if (dentry->d_op && dentry->d_op->d_release)
		dentry->d_op->d_release(dentry);
	/* if dentry was never inserted into hash, immediate free is OK */
	if (hlist_unhashed(&dentry->d_hash))
		__d_free(dentry);
	else
        /* d_callback をコールバックとして削除要求しょり? を出す */
		call_rcu(&dentry->d_u.d_rcu, d_callback);
}

static void d_callback(struct rcu_head *head)
{
	struct dentry * dentry = container_of(head, struct dentry, d_u.d_rcu);
	__d_free(dentry);
}

// __d_free は kmem_cache_free と kfree 
static void __d_free(struct dentry *dentry)
{
	WARN_ON(!list_empty(&dentry->d_alias));
	if (dname_external(dentry))
		kfree(dentry->d_name.name);
	kmem_cache_free(dentry_cache, dentry);
}
```