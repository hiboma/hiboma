# mincore(2)

```c
#include <unistd.h> 
#include <sys/mman.h>
int mincore(void *addr, size_t length, unsigned char *vec);
```

## mm/mincore.c

mincore の実装は仮想アドレスからページフレーム `pte_t *pte` を探すのが肝

 * `find_vma(current->mm, addr)`  で vm_area_struct を見つける
 * `pgd_offset(vma->vm_mm, addr)` で pgd を見つける
 * `pud_offset(pgd, addr)` で pud を見つける
 * `pmd_offset(pud, addr)` で pmd を見つける
 * `pte_offset_map_lock(vma->vm_mm, pmd, addr, &ptl)` で ptep (ptd_tのポインタ) を出す
   * pte_none(pte) なら 0
   * pte_present(pte) なら +1
   * pte_file(pte) なら `find_get_page(mapping, pgoff)` で struct page を見つけたら +1
     * ページキャッシュだったら +1 てことだろう

実際はアドレスのアラインしたり何なりで複雑だけど、だいたいの動きは ↑ な感じ。
