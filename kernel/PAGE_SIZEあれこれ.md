# PAGE_SIZE

バイナリゆとりなので早見表を作ります

```c
/* PAGE_SHIFT determines the page size */
#define PAGE_SHIFT	13
#define PAGE_SIZE	(_AC(1,UL) << PAGE_SHIFT)
#define PAGE_MASK	(~(PAGE_SIZE-1))
```

size >> PAGE_SHIFT 

size を page 数に変換

page << PAGE_SHIFT 

page を ページ数にアラインされたバイト数に変換

PAGE_SIZE 

page のサイズ。まんま

PAGE_MASK

0x00000fff

~PAGE_MASK

0xfffff000

addr & ~PAGE_MASK

page サイズでアライン

addr + PAGE_SIZE

