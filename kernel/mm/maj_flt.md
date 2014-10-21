# maj_flt

`/proc/$pid/stat` で吐き出される数値

#### fs/proc/array.c

```c
		/* add up live thread stats at the group level */
		if (whole) {
			struct task_struct *t = task;
			do {
				min_flt += t->min_flt;
				maj_flt += t->maj_flt;
				gtime = cputime_add(gtime, t->gtime);
				t = next_thread(t);
			} while (t != task);

			min_flt += sig->min_flt;
			maj_flt += sig->maj_flt;
			thread_group_times(task, &utime, &stime);
			gtime = cputime_add(gtime, sig->gtime);
		}
```