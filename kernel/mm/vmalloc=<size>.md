# allocation failed: out of vmalloc space - use vmalloc=<size> to increase size.

## 2.6.9

fs/proc/proc_misc.c

```c
//...
	vmtot = (VMALLOC_END-VMALLOC_START)>>10;
	vmi = get_vmalloc_info();
	vmi.used >>= 10;
	vmi.largest_chunk >>= 10;

//...    
		"VmallocTotal: %8lu kB\n"
		"VmallocUsed:  %8lu kB\n"
		"VmallocChunk: %8lu kB\n",

//...        
		vmtot,
		vmi.used,
		vmi.largest_chunk
		);
```

 * http://www.csn.ul.ie/~mel/projects/vm/guide/text/graphs/vmalloc_address.png
 * http://img.my.csdn.net/uploads/201105/8/0_1304840785zUQS.gif

```c
static struct vmalloc_info get_vmalloc_info(void)
{
	unsigned long prev_end = VMALLOC_START;
	struct vm_struct* vma;
	struct vmalloc_info vmi;
	vmi.used = 0;

	read_lock(&vmlist_lock);

	if(!vmlist)
		vmi.largest_chunk = (VMALLOC_END-VMALLOC_START);
	else
		vmi.largest_chunk = 0;

    /* vm_struct* をイテレートして、割り当てサイズを加算 */
	for (vma = vmlist; vma; vma = vma->next) {
		unsigned long free_area_size =
			(unsigned long)vma->addr - prev_end;
		vmi.used += vma->size;
		if (vmi.largest_chunk < free_area_size )

			vmi.largest_chunk = free_area_size;
		prev_end = vma->size + (unsigned long)vma->addr;
	}
	if(VMALLOC_END-prev_end > vmi.largest_chunk)
		vmi.largest_chunk = VMALLOC_END-prev_end;

	read_unlock(&vmlist_lock);
	return vmi;
}
```

VMALLOC_START

```
#define VMALLOC_START	(((unsigned long) high_memory + vmalloc_earlyreserve + \
			2*VMALLOC_OFFSET-1) & ~(VMALLOC_OFFSET-1))
```