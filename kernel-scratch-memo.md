 * http://opensuse-man-ja.berlios.de/opensuse-html/cha.tuning.oprofile.html
 * unlock -> schedule -> lock の構造
```c
	spin_unlock(&q->lock);
	timeout = schedule_timeout(timeout);
	spin_lock_irq(&q->lock);
```

 * struct file からファイル名だす
```c
char *filename = filp->f_dentry->d_name.name
```

 * 文字列の長さ strlen
 * 文字列のコピー
``` c
char *str = kstrdup(target, GFP_KERNEL)
```

 * mutex_lock, mutex_unlock
```c
static DEFINE_MUTEX(chrdevs_lock);
mutex_lock(&chrdevs_lock)

//  ...

mutex_unlock(&chrdevs_lock);
```

 * INIT_LIST_HEAD(list)
```c
	struct list_head list;
```

 * 0初期化
```c
memset(p, 0, sizeof(type p))
```

 * CPUをイテレート (* 2.6.15)
```c
	unsigned long i, sum = 0;

 	for_each_online_cpu(i)
		sum += cpu_rq(i)->nr_running;
```        

 * CPUの番号
```c
   int cpu = smp_processor_id();
```
 * CPU のランキュー
``` c
    int cpu = smp_processor_id();
    struct rq *rq = cpu_rq(cpu);
```

 * list_for_each_entry_safe
 * tasklist_lock
   * __cacheline_aligned DEFINE_RWLOCK(tasklist_lock);  /* outer */
 * void *page_address(const struct page *page)


 * 文字列のパスから path を探索
   *flags … LOOKUP_FOLLOW
```c   
int kern_path(const char *name, unsigned int flags, struct path *path)
```

 * 親ディレクトリの探索
```c
path_lookup(sunaddr->sun_path, LOOKUP_PARENT, &nd);
```
 