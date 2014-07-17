# kernel-hugemem


# CONFIG_X86_4G マクロ

 * 4g/4g split

```
config X86_4G
        bool "4 GB kernel-space and 4 GB user-space virtual memory support"
        help
          This option is only useful for systems that have more than 1 GB
          of RAM.

          The default kernel VM layout leaves 1 GB of virtual memory for
          kernel-space mappings, and 3 GB of VM for user-space applications.
          This option ups both the kernel-space VM and the user-space VM to
          4 GB.

          The cost of this option is additional TLB flushes done at
          system-entry points that transition from user-mode into kernel-mode.
          I.e. system calls and page faults, and IRQs that interrupt user-mode
          code. There's also additional overhead to kernel operations that copy
          memory to/from user-space. The overhead from this is hard to tell and
          depends on the workload - it can be anything from no visible overhead
          to 20-30% overhead. A good rule of thumb is to count with a runtime
          overhead of 20%.

          The upside is the much increased kernel-space VM, which more than
          quadruples the maximum amount of RAM supported. Kernels compiled with
          this option boot on 64GB of RAM and still have more than 3.1 GB of
          'lowmem' left. Another bonus is that highmem IO bouncing decreases,
          if used with drivers that still use bounce-buffers.

          There's also a 33% increase in user-space VM size - database
          applications might see a boost from this.

          But the cost of the TLB flushes and the runtime overhead has to be
          weighed against the bonuses offered by the larger VM spaces. The
          dividing line depends on the actual workload - there might be 4 GB
          systems that benefit from this option. Systems with less than 4 GB
          of RAM will rarely see a benefit from this option - but it's not
          out of question, the exact circumstances have to be considered.
 
``` 
 * http://lwn.net/Articles/39283/
 * http://docs.oracle.com/cd/E16338_01/server.112/b56317/appi_vlm.htm
 * http://sourceforge.jp/magazine/03/07/10/034238

```
struct page *mem_map;
```

arch/i386/kernel/setup.c

```
#ifndef CONFIG_X86_4G
		/*
		 * For kernels without 4G/4G split, printk a note
		 * pointing at the hugemem kernel from 16Gb onwards:
		 */
		if (start + size >= 0x400000000ULL && !sillymemwarning++) {
			printk("********************************************************\n");
			printk("* This system has more than 16 Gigabyte of memory.     *\n");
			printk("* It is recommended that you read the release notes    *\n");
			printk("* that accompany your copy of the CentOS distribution  *\n");
			printk("* about the recommended kernel for such configurations *\n");
			printk("********************************************************\n");		
		}
#endif
```

arch/i386/mm/fault.c

```c
asmlinkage void do_page_fault(struct pt_regs *regs, unsigned long error_code) {

//...

#ifdef CONFIG_X86_4G
	/*
	 * On 4/4 all kernels faults are either bugs, vmalloc or prefetch
	 */
	/* If it's vm86 fall through */
	if (unlikely(!(regs->eflags & VM_MASK) && ((regs->xcs & 3) == 0))) {
		if (error_code & 3)
			goto bad_area_nosemaphore;
		goto vmalloc_fault;
	}
#else
```