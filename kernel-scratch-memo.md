
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