# kernel-hugemem

 * 4g/4g split
 * CONFIG_X86_4G マクロ
 * http://lwn.net/Articles/39283/
 * http://docs.oracle.com/cd/E16338_01/server.112/b56317/appi_vlm.htm
 * http://sourceforge.jp/magazine/03/07/10/034238

```
struct page *mem_map;
```

 * arch/i386/kernel/setup.c

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