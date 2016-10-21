# pthread_mutex_lock returns EINVAL after mutex pthread_mutex_destroy

**NPTL** で、pthread_mutex_destroy した後に pthread_mutex_lock を呼び出すと EINVAL を返す実装を追う

## sample

```c
#include <stdlib.h>
#include <string.h>
#include <err.h>
#include <pthread.h>

pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;

int main()
{
	int err;

	err = pthread_mutex_init(&m, NULL);
	if (err)
		errx(err, "pthread_mutex_init %s", strerror(err));
	
	err = pthread_mutex_destroy(&m);
	if (err)
		errx(err, "pthread_mutex_destroy %s", strerror(err));

	err = pthread_mutex_lock(&m);
	if (err)
		errx(err, "pthread_mutex_lock %s", strerror(err)); /* 
	
	exit(0);
}
```

```sh
$ ./return-EINVAL 
return-EINVAL: pthread_mutex_lock Invalid argument

$ ltrace ./return-EINVAL 
__libc_start_main(0x400790, 1, 0x7fffc4df1748, 0x400850 <unfinished ...>
pthread_mutex_init(0x601080, 0, 0x7fffc4df1758, 0x400850)                                                                         = 0
pthread_mutex_destroy(0x601080, 0x7f686ec698d8, 0, 0)                                                                             = 0
pthread_mutex_lock(0x601080, 0x7f686ec698d8, 0, 0)                                                                                = 22
strerror(22)                                                                                                                      = "Invalid argument"
errx(22, 0x40090f, 0x7f686ea1311d, 0lock-return-EINVAL: pthread_mutex_lock Invalid argument
 <no return ...>
+++ exited (status 22) +++
```

```sh
$ grep -R EINVAL /usr/include/
/usr/include/asm-generic/errno-base.h:#define   EINVAL          22      /* Invalid argument */
```

**invalid** とあるけど、実際のところ何がどう **invalid** なのか曖昧だよな

## API 

```c
#include <pthread.h>

int pthread_mutex_destroy(pthread_mutex_t *mutex);
int pthread_mutex_init(pthread_mutex_t *restrict mutex,
       const pthread_mutexattr_t *restrict attr);
pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
```

## pthread_mutex_lock

glibc-2.17-106.el7_2.8 のソースを読んでいく

```c
/* Copyright (C) 2002-2012 Free Software Foundation, Inc.
   This file is part of the GNU C Library.
   Contributed by Ulrich Drepper <drepper@redhat.com>, 2002.

   The GNU C Library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   The GNU C Library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with the GNU C Library; if not, see
   <http://www.gnu.org/licenses/>.  */

#include <errno.h>
#include "pthreadP.h"

#include <stap-probe.h>


int
__pthread_mutex_destroy (mutex)
     pthread_mutex_t *mutex;
{
  LIBC_PROBE (mutex_destroy, 1, mutex);

  if ((mutex->__data.__kind & PTHREAD_MUTEX_ROBUST_NORMAL_NP) == 0
      && mutex->__data.__nusers != 0)
    return EBUSY;

  /* Set to an invalid value.  */
  mutex->__data.__kind = -1; ★

  return 0;
}
strong_alias (__pthread_mutex_destroy, pthread_mutex_destroy)
hidden_def (__pthread_mutex_destroy)
```

なんと、これだけのことしかやっていない

```c
  /* Set to an invalid value.  */
  mutex->__data.__kind = -1;
```

`-1` が invalid value として扱われる

 * pthread_mutex_destroy の中で「リソースの解放」をやってるかと思ってたけど、そういうものではなかった
 * mutex 変数が (スタック変数か|静的変数か|ヒープ上か) は呼び出し側にしか分からないので、破棄の責務は呼び出し側が担うべきなのだろう

pthread_mutex_lock は `mutex->__data.__kind = -1` をどう扱うのだろう?

## pthread_mutex_lock

pthread_mutex_destroy した mutext で pthread_mutex_lock が EINVAL を返す実装をよむ

```c
static int
__pthread_mutex_lock_full (pthread_mutex_t *mutex)
{
  int oldval;
  pid_t id = THREAD_GETMEM (THREAD_SELF, tid);

  switch (PTHREAD_MUTEX_TYPE (mutex))
    {
    case PTHREAD_MUTEX_ROBUST_RECURSIVE_NP:
    case PTHREAD_MUTEX_ROBUST_ERRORCHECK_NP:
    case PTHREAD_MUTEX_ROBUST_NORMAL_NP:

/* ... */

    default:
      /* Correct code cannot set any other type.  */
      return EINVAL;
    }
```

PTHREAD_MUTEX_TYPE が肝で、下記のようなマクロとなっている

```
#define PTHREAD_MUTEX_TYPE(m) \
  ((m)->__data.__kind & 127)
```

このマクロの評価によって `return EINVAL` に辿り着くのだった

## The Open Group Base Specifications Issue 7

実装をざっと読んだので、ついでに標準ではどのように記載されているかを眺める

[http://pubs.opengroup.org/onlinepubs/9699919799/functions/pthread_mutex_destroy.html](The Open Group Base Specifications Issue 7 / pthread_mutex_destroy) の項には下記のような記載がある

> The pthread_mutex_destroy() function shall destroy the mutex object referenced by mutex; the mutex object becomes, in effect, uninitialized. An implementation may cause pthread_mutex_destroy() to set the object referenced by mutex to an invalid value.

 * `mutex` と `mutex object` と分かれていてややこしいが、メモリ上のデータ(= どう実装されているか) を指すのは後者になるのだろうか
 * detroy すると uninitialized になる
 * mutex object に invalid value をセットするかも

> If an implementation detects that the value specified by the mutex argument to pthread_mutex_destroy() does not refer to an initialized mutex, it is recommended that the function should fail and report an [EINVAL] error.

 * pthread_mutex_destroy の引数で initialized されてない mutex を参照したら EINVAL を返すよにするといいよ

> An implementation is permitted, but not required, to have pthread_mutex_destroy() store an illegal value into the mutex. This may help detect erroneous programs that try to lock (or otherwise reference) a mutex that has already been destroyed.

 * pthread_mutex_destroy したら illegal value を mutext にセットする実装でもいいよ (必須ではない)
   * NPTL がまさにこの実装をとっているね! 
 * destroy 済みの mutex をロックしようとしたり参照しているエラーのあるプログラムをみつけられる

> Destroying Mutexes
> 
> A mutex can be destroyed immediately after it is unlocked. However, since attempting to destroy a locked mutex, or a mutex that another thread is attempting to lock, or a mutex that is being used in a pthread_cond_timedwait() or pthread_cond_wait() call by another thread, results in undefined behavior, care must be taken to ensure that no other thread may be referencing the mutex.

 * 未定義なふるまについて