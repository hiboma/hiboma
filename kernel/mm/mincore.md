# mincore(2)

```c
#include <unistd.h> 
#include <sys/mman.h>
int mincore(void *addr, size_t length, unsigned char *vec);
```

 * `find_vma(current->mm, addr)`  で vm_area_struct を見つける
 * `pgd_offset(vma->vm_mm, addr)` で pgd を見つける
 * `pud_offset(pgd, addr)` で pud を見つける
 * `pmd_offset(pud, addr)` で pmd を見つける
 * `pte_offset_map_lock(vma->vm_mm, pmd, addr, &ptl)` で ptep (ptd_tのポインタ) を出す