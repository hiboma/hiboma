# PAGE_SIZE

バイナリゆとりなので早見表を作ります

## arch/x86/include/asm/page_types.h

```c
/* PAGE_SHIFT determines the page size */
#define PAGE_SHIFT	12
#define PAGE_SIZE	(_AC(1,UL) << PAGE_SHIFT)
#define PAGE_MASK	(~(PAGE_SIZE-1))
```

## ビット演算

#### size を page 数に変換

```c
size >> PAGE_SHIFT
```

#### page を ページ数にアラインされたバイト数に変換

```c
page << PAGE_SHIFT
```

#### PAGE_MASK

```c
        0x00000fff /* 32bit */
0x0000000000000fff /* 64bit */
```

#### ~PAGE_MASK (~PAGE_CACHE_MASK)

```c
        0xfffff000 /* 32bit */
0xfffffffffffff000 /* 64bit */
```

#### pageサイズでアラインされているか否か

```c
if (addr & ~PAGE_MASK) {
    /* not aligned */
}
```

#### 隣のページ

```c
addr + PAGE_SIZE
```
