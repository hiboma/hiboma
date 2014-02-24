
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

```
	struct list_head list;
```