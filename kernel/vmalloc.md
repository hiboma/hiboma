## "allocation failed: out of vmalloc space - use vmalloc=<size> to increase size.\n");

ソースは驚きの 2.6.9

 * vmalloc
 * __vmalloc
 * get_vm_area
 * __get_vm_area

```c
struct vm_struct *__get_vm_area(unsigned long size, unsigned long flags,
				unsigned long start, unsigned long end)
{
	struct vm_struct **p, *tmp, *area;
	unsigned long align = 1;
	unsigned long addr;

	if (flags & VM_IOREMAP) {
		int bit = fls(size);

		if (bit > IOREMAP_MAX_ORDER)
			bit = IOREMAP_MAX_ORDER;
		else if (bit < PAGE_SHIFT)
			bit = PAGE_SHIFT;

		align = 1ul << bit;
	}
	addr = ALIGN(start, align);

	area = kmalloc(sizeof(*area), GFP_KERNEL);
	if (unlikely(!area))
		return NULL;

	/*
	 * We always allocate a guard page.
	 */
	size += PAGE_SIZE;
	if (unlikely(!size)) {
		kfree (area);
		return NULL;
	}

	write_lock(&vmlist_lock);
	for (p = &vmlist; (tmp = *p) != NULL ;p = &tmp->next) {
		if ((unsigned long)tmp->addr < addr) {
			if((unsigned long)tmp->addr + tmp->size >= addr)
				addr = ALIGN(tmp->size + 
					     (unsigned long)tmp->addr, align);
			continue;
		}
		if ((size + addr) < addr)
			goto out;
		if (size + addr <= (unsigned long)tmp->addr)
			goto found;
		addr = ALIGN(tmp->size + (unsigned long)tmp->addr, align);
		if (addr > end - size)
			goto out;
	}

found:
	area->next = *p;
	*p = area;

	area->flags = flags;
	area->addr = (void *)addr;
	area->size = size;
	area->pages = NULL;
	area->nr_pages = 0;
	area->phys_addr = 0;
	write_unlock(&vmlist_lock);

	return area;

out:
	write_unlock(&vmlist_lock);
	kfree(area);
	if (printk_ratelimit())
		printk(KERN_WARNING "allocation failed: out of vmalloc space - use vmalloc=<size> to increase size.\n");
	return NULL;
}
```