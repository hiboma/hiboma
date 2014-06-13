# mincore(2)

## TODO

非線形マッピング?( Nonlinear Mappings ) が分からない

remap_file_pages

## mincore(2) API

```c
#include <unistd.h> 
#include <sys/mman.h>
int mincore(void *addr, size_t length, unsigned char *vec);
```

> mincore() は、呼び出し元プロセスの仮想メモリのページがコア (RAM) 内に存在し、 ページ参照時にディスクアクセス (ページフォールト) を起こさないか どうかを示すベクトルを返す。カーネルは、アドレス addr から始まる length バイトの範囲のページに関する存在情報を返す。

 * 対象のアドレスが anon か file backed かを問わない
 * ページキャッシュとして存在するか否かは mmap(2) して見るとよい [refs](http://d.hatena.ne.jp/syuu1228/20110106/1294323955)

## mm/mincore.c

mincore の実装は仮想アドレスからページフレーム `pte_t *pte` を探すのが肝

 * `find_vma(current->mm, addr)`  で vm_area_struct を見つける
 * `pgd_offset(vma->vm_mm, addr)` で pgd を見つける
 * `pud_offset(pgd, addr)` で pud を見つける
 * `pmd_offset(pud, addr)` で pmd を見つける
 * `pte_offset_map_lock(vma->vm_mm, pmd, addr, &ptl)` で ptep (ptd_tのポインタ) を出す
   * pte_none(pte) なら 非線形マッピングか否かを見る
   * pte_present(pte) なら +1
   * pte_file(pte) なら `find_get_page(mapping, pgoff)` で radix ツリーから struct page を見つけたら +1
     * ページキャッシュだったら +1 てことだろう
   * swap entry ? の場合も +1

実際はアドレスのアラインしたり何なりで複雑だけど、だいたいの動きは ↑ な感じ。

![](https://camo.githubusercontent.com/a8c84292852eb14dd1aedd8a7f8c389788f27e14/68747470733a2f2f662e636c6f75642e6769746875622e636f6d2f6173736574732f3137323435362f323334313732392f33303963393066652d613465322d313165332d393038332d6434326534366366613638372e676966)

### mincore_pte_range

```c
static void mincore_pte_range(struct vm_area_struct *vma, pmd_t *pmd,
			unsigned long addr, unsigned long end,
			unsigned char *vec)
{
	unsigned long next;
	spinlock_t *ptl;
	pte_t *ptep;

	ptep = pte_offset_map_lock(vma->vm_mm, pmd, addr, &ptl);
	do {
		pte_t pte = *ptep;
		pgoff_t pgoff;

		next = addr + PAGE_SIZE;
		if (pte_none(pte))
			mincore_unmapped_range(vma, addr, next, vec);
		else if (pte_present(pte))
			*vec = 1;
		else if (pte_file(pte)) {
			pgoff = pte_to_pgoff(pte);
			*vec = mincore_page(vma->vm_file->f_mapping, pgoff);
		} else { /* pte is a swap entry */
			swp_entry_t entry = pte_to_swp_entry(pte);

			if (is_migration_entry(entry)) {
				/* migration entries are always uptodate */
				*vec = 1;
			} else {
#ifdef CONFIG_SWAP
				pgoff = entry.val;
				*vec = mincore_page(&swapper_space, pgoff);
#else
				WARN_ON(1);
				*vec = 1;
#endif
			}
		}
		vec++;
	} while (ptep++, addr = next, addr != end);
	pte_unmap_unlock(ptep - 1, ptl);
}
```