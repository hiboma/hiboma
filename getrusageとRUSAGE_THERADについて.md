# getrusage(2)

## RUSAGE_THREAD について調べた

RUSAGE_THREAD は Linux固有で、 __USE_GNU を定義すると扱える

```c
#include <stdio.h>
#include <sys/time.h> 

#define __USE_GNU
#include <sys/resource.h>

int main() { 
        struct rusage usage;
        if(getrusage(RUSAGE_THREAD, &usage)) { 
                perror("getrusage");
                return 1;
        }

        printf("%ld\n", usage.ru_maxrss);
        return 0;
}
```

RUSAGE_THREAD を指定するとカレントスレッドの rusage を取れる

```c
/* 2.6.32 kernel/sys.c */
static void k_getrusage(struct task_struct *p, int who, struct rusage *r)
{
	struct task_struct *t;
	unsigned long flags;
	cputime_t tgutime, tgstime, utime, stime;
	unsigned long maxrss = 0;

	memset((char *) r, 0, sizeof *r);
	utime = stime = cputime_zero;

	if (who == RUSAGE_THREAD) {
		utime = task_utime(current);
		stime = task_stime(current);
		accumulate_thread_rusage(p, r);
		maxrss = p->signal->maxrss;
		goto out;
	}

	if (!lock_task_sighand(p, &flags))
		return;

	switch (who) {
		case RUSAGE_BOTH:
		case RUSAGE_CHILDREN:
			utime = p->signal->cutime;
			stime = p->signal->cstime;
			r->ru_nvcsw = p->signal->cnvcsw;
			r->ru_nivcsw = p->signal->cnivcsw;
			r->ru_minflt = p->signal->cmin_flt;
			r->ru_majflt = p->signal->cmaj_flt;
			r->ru_inblock = p->signal->cinblock;
			r->ru_oublock = p->signal->coublock;
			maxrss = p->signal->cmaxrss;

			if (who == RUSAGE_CHILDREN)
				break;

		case RUSAGE_SELF:
			thread_group_times(p, &tgutime, &tgstime);
			utime = cputime_add(utime, tgutime);
			stime = cputime_add(stime, tgstime);
			r->ru_nvcsw += p->signal->nvcsw;
			r->ru_nivcsw += p->signal->nivcsw;
			r->ru_minflt += p->signal->min_flt;
			r->ru_majflt += p->signal->maj_flt;
			r->ru_inblock += p->signal->inblock;
			r->ru_oublock += p->signal->oublock;
			if (maxrss < p->signal->maxrss)
				maxrss = p->signal->maxrss;
			t = p;
			do {
				accumulate_thread_rusage(t, r);
				t = next_thread(t);
			} while (t != p);
			break;

		default:
			BUG();
	}
	unlock_task_sighand(p, &flags);

out:
	cputime_to_timeval(utime, &r->ru_utime);
	cputime_to_timeval(stime, &r->ru_stime);

	if (who != RUSAGE_CHILDREN) {
		struct mm_struct *mm = get_task_mm(p);
		if (mm) {
			setmax_mm_hiwater_rss(&maxrss, mm);
			mmput(mm);
		}
	}
	r->ru_maxrss = maxrss * (PAGE_SIZE / 1024); /* convert pages to KBs */
}
```

 * RUSAGE_THREAD だと current = システムコール呼び出しスレッドの統計のみ扱う
 * RUSAGE_SELF だとプロセス(全スレッド) の統計を扱ってるのが分かる
 * `struct signal_struct` にいろんな統計の数値が入ってるのが慧眼だった
   * フォルトの数やブロック入出力の回数? やなんで `struct signal_struct` にいれてるんだろうか
 * `(PAGE_SIZE / 1024); /* convert pages to KBs */`

