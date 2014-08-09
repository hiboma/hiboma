# VmRSS

```c
struct mm_struct {

//...

	/* Special counters, in some configurations protected by the
	 * page_table_lock, in other configurations by being atomic.
	 */
	mm_counter_t _file_rss;
	mm_counter_t _anon_rss;
	mm_counter_t _swap_usage;
```

USE_SPLIT_PTLOCKS は http://d.hatena.ne.jp/hsyd/20100515/1273945372 を読んで理解

```c
#if USE_SPLIT_PTLOCKS
/*
 * The mm counters are not protected by its page_table_lock,
 * so must be incremented atomically.
 */
#define set_mm_counter(mm, member, value) atomic_long_set(&(mm)->_##member, value)
#define get_mm_counter(mm, member) ((unsigned long)atomic_long_read(&(mm)->_##member))
#define add_mm_counter(mm, member, value) atomic_long_add(value, &(mm)->_##member)
#define inc_mm_counter(mm, member) atomic_long_inc(&(mm)->_##member)
#define dec_mm_counter(mm, member) atomic_long_dec(&(mm)->_##member)

#else  /* !USE_SPLIT_PTLOCKS */
/*
 * The mm counters are protected by its page_table_lock,
 * so can be incremented directly.
 */
#define set_mm_counter(mm, member, value) (mm)->_##member = (value)
#define get_mm_counter(mm, member) ((mm)->_##member)
#define add_mm_counter(mm, member, value) (mm)->_##member += (value)
#define inc_mm_counter(mm, member) (mm)->_##member++
#define dec_mm_counter(mm, member) (mm)->_##member--

#endif /* !USE_SPLIT_PTLOCKS */

#define get_mm_rss(mm)					\
	(get_mm_counter(mm, file_rss) + get_mm_counter(mm, anon_rss))
#define update_hiwater_rss(mm)	do {			\
	unsigned long _rss = get_mm_rss(mm);		\
	if ((mm)->hiwater_rss < _rss)			\
		(mm)->hiwater_rss = _rss;		\
} while (0)

static inline unsigned long get_mm_hiwater_rss(struct mm_struct *mm)
{
	return max(mm->hiwater_rss, get_mm_rss(mm));
}

static inline void setmax_mm_hiwater_rss(unsigned long *maxrss,
					 struct mm_struct *mm)
{
	unsigned long hiwater_rss = get_mm_hiwater_rss(mm);

	if (*maxrss < hiwater_rss)
		*maxrss = hiwater_rss;
}
```

## set_mm_counter

 * kernel/fork.c
 * mm_init で mm_struct の初期化時に使われるマクロ

```c
static struct mm_struct * mm_init(struct mm_struct * mm, struct task_struct *p)
{
	atomic_set(&mm->mm_users, 1);
	atomic_set(&mm->mm_count, 1);
	init_rwsem(&mm->mmap_sem);
	INIT_LIST_HEAD(&mm->mmlist);
	mm->flags = (current->mm) ?
		(current->mm->flags & MMF_INIT_MASK) : default_dump_filter;
	mm->core_state = NULL;
	mm->nr_ptes = 0;
	set_mm_counter(mm, file_rss, 0);
	set_mm_counter(mm, anon_rss, 0);
	set_mm_counter(mm, swap_usage, 0);
```