## 6.4.7 RCU

**Read Copy Update**

#### スピンロック、アトミック操作のキャッシュラインフラッシュ???

#### 古い実装

```c
static inline void __raw_spin_lock(raw_spinlock_t *lock)
{
	__asm__ __volatile__(
		__raw_spin_lock_string
		:"=m" (lock->slock) : : "memory");
}
```

```c
#define __raw_spin_lock_string \
	"\n1:\t" \
	"lock ; decb %0\n\t" \
	"jns 3f\n" \
	"2:\t" \
	"rep;nop\n\t" \
	"cmpb $0,%0\n\t" \
	"jle 2b\n\t" \
	"jmp 1b\n" \
	"3:\n\t"
```

#### 新しい実装 ticket spinlock

ticket spinlock is なに?

   * http://linuxkernelpanic.blogspot.jp/2013/01/ticket-spinlocks-for-user-space.html
   * https://access.redhat.com/documentation/ja-JP/Red_Hat_Enterprise_Linux/6/html/Performance_Tuning_Guide/s-ticket-spinlocks.html
   * http://lwn.net/Articles/267968/
   * http://kernhack.hatenablog.com/entry/2013/04/26/084041
   * http://d.hatena.ne.jp/meech/20101208/1291819984

```c
#define spin_lock(lock)			_spin_lock(lock)

void __lockfunc _spin_lock(spinlock_t *lock)		__acquires(lock);

void __lockfunc _spin_lock(spinlock_t *lock)
{
	__spin_lock(lock);
}

static inline void __spin_lock(spinlock_t *lock)
{
	preempt_disable();
	spin_acquire(&lock->dep_map, 0, 0, _RET_IP_);
	LOCK_CONTENDED(lock, _raw_spin_trylock, _raw_spin_lock);
}

# define _raw_spin_trylock(lock)	__raw_spin_trylock(&(lock)->raw_lock)

static __always_inline int __raw_spin_trylock(raw_spinlock_t *lock)
{
	return __ticket_spin_trylock(lock);
}

arch/x86/include/asm/spinlock.h

```c
/*
 * Your basic SMP spinlocks, allowing only a single CPU anywhere
 *
 * Simple spin lock operations.  There are two variants, one clears IRQ's
 * on the local processor, one does not.
 *
 * These are fair FIFO ticket locks, which are currently limited to 256
 * CPUs.
 *
 * (the type definitions are in asm/spinlock_types.h)
 */

 //...

/*
 * Ticket locks are conceptually two parts, one indicating the current head of
 * the queue, and the other indicating the current tail. The lock is acquired
 * by atomically noting the tail and incrementing it by one (thus adding
 * ourself to the queue and noting our position), then waiting until the head
 * becomes equal to the the initial value of the tail.
 *
 * We use an xadd covering *both* parts of the lock, to increment the tail and
 * also load the position of the head, which takes care of memory ordering
 * issues and should be optimal for the uncontended case. Note the tail must be
 * in the high part, because a wide xadd increment of the low part would carry
 * up and contaminate the high part.
 *
 * With fewer than 2^8 possible CPUs, we can use x86's partial registers to
 * save some instructions and make the code more elegant. There really isn't
 * much between them in performance though, especially as locks are out of line.
 */

// CPU/コア数によってスピンロックの実装が違う 256以上って化け物感ある
#if (NR_CPUS < 256)
static __always_inline int __ticket_spin_trylock(raw_spinlock_t *lock)
{
	int tmp, new;

	asm volatile("movzwl %2, %0\n\t"
		     "cmpb %h0,%b0\n\t"
		     "leal 0x100(%" REG_PTR_MODE "0), %1\n\t"
		     "jne 1f\n\t"
		     LOCK_PREFIX "cmpxchgw %w1,%2\n\t"
		     "1:"
		     "sete %b1\n\t"
		     "movzbl %b1,%0\n\t"
		     : "=&a" (tmp), "=&q" (new), "+m" (lock->slock)
		     :
		     : "memory", "cc");

	return tmp;
}

//...

#else
static __always_inline int __ticket_spin_trylock(raw_spinlock_t *lock)
{
	int tmp;
	int new;

	asm volatile("movl %2,%0\n\t"
		     "movl %0,%1\n\t"
		     "roll $16, %0\n\t"
		     "cmpl %0,%1\n\t"
		     "leal 0x00010000(%" REG_PTR_MODE "0), %1\n\t"
		     "jne 1f\n\t"
		     LOCK_PREFIX "cmpxchgl %1,%2\n\t"
		     "1:"
		     "sete %b1\n\t"
		     "movzbl %b1,%0\n\t"
		     : "=&a" (tmp), "=&q" (new), "+m" (lock->slock)
		     :
		     : "memory", "cc");

	return tmp;
}
```

## 6.4.8 メモリバリア

 * アウトオブオーダー実行
 *

