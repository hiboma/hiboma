# dnetry cache

 * slubで割り当て ->　kmem_cache_alloc, kmem_cache_free
 * 4つの状態

 　 | inode | dcount | 破棄 |
--- | --- | --- | ---
Free | - | - | - |
Active | ○ | 0 | ○ 
Inactive  | ○ | 1以上 | × 
Negative | NULL | 0 | ○? 


## procfs の drop_cache

 * `/proc/sys/vm/drop_caches`
 * `sysctl -w vm.drop_caches=N でも同じ`
 * 下記のビット演算で 1 と 2 と 3 に対応する。なるほど
   * invalidate_mapping_pages ... 全部破棄
   * shrink_slab              ... 全破棄する訳じゃない

```c
		if (sysctl_drop_caches & 1)
			drop_pagecache();
		if (sysctl_drop_caches & 2)
			drop_slab();
``` 

```c
/*
 * Implement the manual drop-all-pagecache function
 */

#include <linux/kernel.h>
#include <linux/mm.h>
#include <linux/fs.h>
#include <linux/writeback.h>
#include <linux/sysctl.h>
#include <linux/gfp.h>

static void drop_pagecache_sb(struct super_block *sb)
{
	struct inode *inode, *toput_inode = NULL;

	spin_lock(&inode_lock);
    // superblock に繋がった VFS inode を全走査する
	list_for_each_entry(inode, &sb->s_inodes, i_sb_list) {
        // dirty でない inode は何もしない
		if (inode->i_state & (I_FREEING|I_CLEAR|I_WILL_FREE|I_NEW))
			continue;
        // マッピングしてるページサイズがゼロならなんもしない
        // どゆこと?
		if (inode->i_mapping->nrpages == 0)
			continue;
		__iget(inode);
		spin_unlock(&inode_lock);
        // ページキャッシュの破棄 !!!!
		invalidate_mapping_pages(inode->i_mapping, 0, -1);
		iput(toput_inode);
		toput_inode = inode;
		spin_lock(&inode_lock);
	}
	spin_unlock(&inode_lock);
	iput(toput_inode);
}

static void drop_pagecache(void)
{
	struct super_block *sb;

	spin_lock(&sb_lock);
restart:
    // super_blocks をイテレート => マウント済みの全ファイルシステムが対象
	list_for_each_entry(sb, &super_blocks, s_list) {
		sb->s_count++;
		spin_unlock(&sb_lock);
		down_read(&sb->s_umount);
		if (sb->s_root)
            // superblock ごとに ページキャッシュの破棄
			drop_pagecache_sb(sb);
		up_read(&sb->s_umount);
		spin_lock(&sb_lock);
		if (__put_super_and_need_restart(sb))
			goto restart;
	}
	spin_unlock(&sb_lock);
}

static void drop_slab(void)
{
	int nr_objects;

	do {
		nr_objects = shrink_slab(1000, GFP_KERNEL, 1000);
	} while (nr_objects > 10);
}

int drop_caches_sysctl_handler(ctl_table *table, int write,
	void __user *buffer, size_t *length, loff_t *ppos)
{
	proc_dointvec_minmax(table, write, buffer, length, ppos);
	if (write) {
		if (sysctl_drop_caches & 1)
			drop_pagecache();
		if (sysctl_drop_caches & 2)
			drop_slab();
	}
	return 0;
}
```

```
	register_shrinker(&dcache_shrinker);
```

## dentry_operations

```c
struct dentry_operations {
	int (*d_revalidate)(struct dentry *, struct nameidata *);
	int (*d_hash) (struct dentry *, struct qstr *);
	int (*d_compare) (struct dentry *, struct qstr *, struct qstr *);
	int (*d_delete)(struct dentry *);
	void (*d_release)(struct dentry *);
	void (*d_iput)(struct dentry *, struct inode *);
    // pipefs が 動的に dentry の名前作るのに使ってた
	char *(*d_dname)(struct dentry *, char *, int);
#ifndef __GENKSYMS__
	struct vfsmount *(*d_automount)(struct path *);
	int (*d_manage)(struct dentry *, bool);
	int (*d_weak_revalidate)(struct dentry *, struct nameidata *);
#endif
};
```

## tmpfs

 * tmpfs は .lookup する際に dentry_operations .d_delete をセットしている
   * backing store が RAM の場合は、削除済みファイルの dentry をキッシュしてもメモリと探索時間の無駄になる
   * ので、すぐに消すとの事
   * simple_delete_dentry は dput で呼ばれる

```c
/*
 * Retaining negative dentries for an in-memory filesystem just wastes
 * memory and lookup time: arrange for them to be deleted immediately.
 */
static int simple_delete_dentry(struct dentry *dentry)
{
	return 1;
}

/*
 * Lookup the data. This is trivial - if the dentry didn't already
 * exist, we know it is negative.  Set d_op to delete negative dentries.
 */
struct dentry *simple_lookup(struct inode *dir, struct dentry *dentry, struct nameidata *nd)
{
	static const struct dentry_operations simple_dentry_operations = {
		.d_delete = simple_delete_dentry,
	};

	if (dentry->d_name.len > NAME_MAX)
		return ERR_PTR(-ENAMETOOLONG);
	dentry->d_op = &simple_dentry_operations;
	d_add(dentry, NULL);
	return NULL;
}
```

### dput

 * 参照カウントをデクリメント
   * __d_drop -> d_kill
    * dentry tree を情報に走査する必要がある。削除をスケジュールされる

```c
/* 
 * This is dput
 *
 * This is complicated by the fact that we do not want to put
 * dentries that are no longer on any hash chain on the unused
 * list: we'd much rather just get rid of them immediately.
 *
 * However, that implies that we have to traverse the dentry
 * tree upwards to the parents which might _also_ now be
 * scheduled for deletion (it may have been only waiting for
 * its last child to go away).
 *
 * This tail recursion is done by hand as we don't want to depend
 * on the compiler to always get this right (gcc generally doesn't).
 * Real recursion would eat up our stack space.
 */

/*
 * dput - release a dentry
 * @dentry: dentry to release 
 *
 * Release a dentry. This will drop the usage count and if appropriate
 * call the dentry unlink method as well as removing it from the queues and
 * releasing its resources. If the parent dentries were scheduled for release
 * they too may now get deleted.
 *
 * no dcache lock, please.
 */

void dput(struct dentry *dentry)
{
	if (!dentry)
		return;

repeat:
	if (atomic_read(&dentry->d_count) == 1)
		might_sleep();
	if (!atomic_dec_and_lock(&dentry->d_count, &dcache_lock))
		return;

	spin_lock(&dentry->d_lock);
	if (atomic_read(&dentry->d_count)) {
		spin_unlock(&dentry->d_lock);
		spin_unlock(&dcache_lock);
		return;
	}

	/*
	 * AV: ->d_delete() is _NOT_ allowed to block now.
	 */
	if (dentry->d_op && dentry->d_op->d_delete) {
        // .d_delete が 1 返したら unhash_it に飛ぶ
		if (dentry->d_op->d_delete(dentry))
			goto unhash_it;
	}
	/* Unreachable? Get rid of it */
 	if (d_unhashed(dentry)) // DCACHE_UNHASHED
		goto kill_it;
  	if (list_empty(&dentry->d_lru)) {
  		dentry->d_flags |= DCACHE_REFERENCED;
		dentry_lru_add(dentry);
  	}
 	spin_unlock(&dentry->d_lock);
	spin_unlock(&dcache_lock);
	return;

unhash_it:
	__d_drop(dentry);
kill_it:
	/* if dentry was on the d_lru list delete it from there */
	dentry_lru_del(dentry);
	dentry = d_kill(dentry);
	if (dentry)
		goto repeat;
}
```

### d_drop

 * 親 dentry から unhash する ( __DCACHE_UNHASHED__ が立つ)
 * VFS の lookup で見つからない
 * d_delete との違いは?
   * d_delete は (可能なら) negative とマークする
   * d_delete は ___negative___ lookup でひっかかる
   * d_drop は ___cache___ lookup しないようにする

```c
/**
 * d_drop - drop a dentry
 * @dentry: dentry to drop
 *
 * d_drop() unhashes the entry from the parent dentry hashes, so that it won't
 * be found through a VFS lookup any more. Note that this is different from
 * deleting the dentry - d_delete will try to mark the dentry negative if
 * possible, giving a successful _negative_ lookup, while d_drop will
 * just make the cache lookup fail.
 *
 * d_drop() is used mainly for stuff that wants to invalidate a dentry for some
 * reason (NFS timeouts or autofs deletes).
 *
 * __d_drop requires dentry->d_lock.
 */

static inline void __d_drop(struct dentry *dentry)
{
	if (!(dentry->d_flags & DCACHE_UNHASHED)) {
		dentry->d_flags |= DCACHE_UNHASHED;
		hlist_del_rcu(&dentry->d_hash);
	}
}
```

### d_kill

 * unhashed で LRU から外されてる dentry を削除する
  * d_free -> __d_free -> kfree

```c
/**
 * d_kill - kill dentry and return parent
 * @dentry: dentry to kill
 *
 * The dentry must already be unhashed and removed from the LRU.
 *
 * If this is the root of the dentry tree, return NULL.
 */
static struct dentry *d_kill(struct dentry *dentry)
	__releases(dentry->d_lock)
	__releases(dcache_lock)
{
	struct dentry *parent;

	list_del(&dentry->d_u.d_child);
	dentry_stat.nr_dentry--;	/* For d_free, below */
	/*drops the locks, at that point nobody can reach this dentry */
	dentry_iput(dentry);
	if (IS_ROOT(dentry))
		parent = NULL;
	else
		parent = dentry->d_parent;
	d_free(dentry);
	return parent;
}
```