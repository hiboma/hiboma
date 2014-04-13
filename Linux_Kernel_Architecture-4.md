## 4.2.1 Layout of the Process Address Space

```c
struct mm_struct {
...
	unsigned long (*get_unmapped_area) (struct file *filp,
				unsigned long addr, unsigned long len,
				unsigned long pgoff, unsigned long flags);
       unsigned long (*get_unmapped_exec_area) (struct file *filp,
				unsigned long addr, unsigned long len,
				unsigned long pgoff, unsigned long flags);
	void (*unmap_area) (struct mm_struct *mm, unsigned long addr);
	unsigned long mmap_base;		/* base of mmap area */
	unsigned long task_size;		/* size of task vm space */

	pgd_t * pgd;
	atomic_t mm_users;			/* How many users with user space? */
	atomic_t mm_count;			/* How many references to "struct mm_struct" (users count as 1) */
	int map_count;				/* number of VMAs */

	unsigned long total_vm, locked_vm, shared_vm, exec_vm;
	unsigned long stack_vm, reserved_vm, def_flags, nr_ptes;
	unsigned long start_code, end_code, start_data, end_data;
	unsigned long start_brk, brk, start_stack;
	unsigned long arg_start, arg_end, env_start, env_end;

...
};
```

 * get_unmapped_area
 * mmap_base

## 4.2.2 Creating the Layout

exec(2) の load_elf_binary で address_space が決まる

![2014-04-13 16 19 44](https://cloud.githubusercontent.com/assets/172456/2688992/215f1e5a-c2dc-11e3-9b5e-7b726396ada1.png)

#### Figure-4.3

```
load_elf_binary
 -> PF_RANDOMIZE
 -> arch_pick_mmap_layout
 -> setup_arg_pages
```

___ASR = Address Space Randomization___

アドレス空間レイアウトのランダム化

 * **/proc/sys/kernel/randomize_va_space** で切り替え
   * 0 無効
   * 1 ヒープのみ無効 COFIG_COMPAT_BRK
     * http://tsueyasu.blogspot.jp/2008/12/randomizevaspace.html
   * 2 有効

#### randomize_va_space = 0 で無効にした場合

以下のレイアウトで固定される

```
[vagrant@vagrant-centos65 ~]$ bash -c 'pmap $$'
4765:   pmap 4765
0000000000400000     12K r-x--  /usr/bin/pmap
0000000000602000      4K rw---  /usr/bin/pmap
0000000000603000    132K rw---    [ anon ]
00007ffff7826000   1580K r-x--  /lib64/libc-2.12.so
00007ffff79b1000   2044K -----  /lib64/libc-2.12.so
00007ffff7bb0000     16K r----  /lib64/libc-2.12.so
00007ffff7bb4000      4K rw---  /lib64/libc-2.12.so
00007ffff7bb5000     20K rw---    [ anon ]
00007ffff7bba000     56K r-x--  /lib64/libproc-3.2.8.so
00007ffff7bc8000   2048K -----  /lib64/libproc-3.2.8.so
00007ffff7dc8000      4K rw---  /lib64/libproc-3.2.8.so
00007ffff7dc9000     80K rw---    [ anon ]
00007ffff7ddd000    128K r-x--  /lib64/ld-2.12.so
00007ffff7ff2000     12K rw---    [ anon ]
00007ffff7ff8000     12K rw---    [ anon ]
00007ffff7ffb000      4K r-x--    [ anon ]
00007ffff7ffc000      4K r----  /lib64/ld-2.12.so
00007ffff7ffd000      4K rw---  /lib64/ld-2.12.so
00007ffff7ffe000      4K rw---    [ anon ]
00007ffffffea000     84K rw---    [ stack ]
ffffffffff600000      4K r-x--    [ anon ]
 total             6256K
```

#### randomize_va_space = 1 で無効にした場合

ヒープのアドレスだけ固定で他はランダムに変わる。2 にするとヒープも変わる

```
[vagrant@vagrant-centos65 ~]$ bash -c 'pmap $$'
4822:   pmap 4822
0000000000400000     12K r-x--  /usr/bin/pmap
0000000000602000      4K rw---  /usr/bin/pmap
0000000000603000    132K rw---    [ anon ]                # <= ヒープ
00007f0bc5a15000   1580K r-x--  /lib64/libc-2.12.so
00007f0bc5ba0000   2044K -----  /lib64/libc-2.12.so
00007f0bc5d9f000     16K r----  /lib64/libc-2.12.so
00007f0bc5da3000      4K rw---  /lib64/libc-2.12.so
00007f0bc5da4000     20K rw---    [ anon ]
00007f0bc5da9000     56K r-x--  /lib64/libproc-3.2.8.so
00007f0bc5db7000   2048K -----  /lib64/libproc-3.2.8.so
00007f0bc5fb7000      4K rw---  /lib64/libproc-3.2.8.so
00007f0bc5fb8000     80K rw---    [ anon ]
00007f0bc5fcc000    128K r-x--  /lib64/ld-2.12.so
00007f0bc61e2000     12K rw---    [ anon ]
00007f0bc61e8000     12K rw---    [ anon ]
00007f0bc61eb000      4K r----  /lib64/ld-2.12.so
00007f0bc61ec000      4K rw---  /lib64/ld-2.12.so
00007f0bc61ed000      4K rw---    [ anon ]
00007fff83f8d000     84K rw---    [ stack ]
00007fff83fff000      4K r-x--    [ anon ]
ffffffffff600000      4K r-x--    [ anon ]
 total             6256K
```

address_space のレイアウトは ___arch_pick_mmap_layout___ で決まる

```c
/*
 * This function, called very early during the creation of a new
 * process VM image, sets up which VM layout function to use:
 */
void arch_pick_mmap_layout(struct mm_struct *mm)
{
	if (!(2 & exec_shield) && mmap_is_legacy()) {
       // レガシーレイアウト
		mm->mmap_base = mmap_legacy_base();
		mm->get_unmapped_area = arch_get_unmapped_area;
		mm->unmap_area = arch_unmap_area;
	} else {
		mm->mmap_base = mmap_base();
		mm->get_unmapped_area = arch_get_unmapped_area_topdown;
		if (!(current->personality & READ_IMPLIES_EXEC)
		    && mmap_is_ia32()) {
			mm->get_unmapped_exec_area = arch_get_unmapped_exec_area;
			mm->shlib_base = SHLIB_BASE + mmap_rnd();
		}
		mm->unmap_area = arch_unmap_area_topdown;
	}
}
```

### レガシーレイアウトとは?

 * `RLIMIT_STACK == RLIM_INFINITY`
 * `/proc/sys/vm/legacy_va_layout > 0`

```c 
static int mmap_is_legacy(void)
{
	if (current->personality & ADDR_COMPAT_LAYOUT)
		return 1;

	if (current->signal->rlim[RLIMIT_STACK].rlim_cur == RLIM_INFINITY)
		return 1;

	return sysctl_legacy_va_layout;
}
```