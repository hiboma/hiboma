# i_size_read と 32bit

i_size_read は struct inode の .i_size を返す

```
static inline loff_t i_size_read(const struct inode *inode)
```

で、32bit では次の通り何故かややこしい実装になっている

```c
/*
 * NOTE: in a 32bit arch with a preemptable kernel and
 * an UP compile the i_size_read/write must be atomic
 * with respect to the local cpu (unlike with preempt disabled),
 * but they don't need to be atomic with respect to other cpus like in
 * true SMP (so they need either to either locally disable irq around
 * the read or for example on x86 they can be still implemented as a
 * cmpxchg8b without the need of the lock prefix). For SMP compiles
 * and 64bit archs it makes no difference if preempt is enabled or not.
 */
static inline loff_t i_size_read(const struct inode *inode)
{
#if BITS_PER_LONG==32 && defined(CONFIG_SMP)
	loff_t i_size;
	unsigned int seq;

	do {
		seq = read_seqcount_begin(&inode->i_size_seqcount);
		i_size = inode->i_size;
	} while (read_seqcount_retry(&inode->i_size_seqcount, seq));
	return i_size;
#elif BITS_PER_LONG==32 && defined(CONFIG_PREEMPT)
	loff_t i_size;

	preempt_disable();
	i_size = inode->i_size;
	preempt_enable();
	return i_size;
#else
	return inode->i_size;
#endif
}
```

inode->i_size の型 ***loff_t*** は `long long`

```c
#if defined(__GNUC__)
typedef __kernel_loff_t		loff_t;
#endif

// arch/x86/include/asm/posix_types_32.h

#ifdef __GNUC__
typedef long long	__kernel_loff_t;
#endif
```

 * 32bit だと1度のメモリアクセスだけで値をコピーできない
 * SMP の場合、同時に他のCPUから更新がかかると中途なサイズを返す可能性がある
 * CONFIG_PREEMPT が有効な場合、 i_size のコピー途中で preemption する可能性があるので、

ということからクリティカルセクションとして保護して扱う必要がある?