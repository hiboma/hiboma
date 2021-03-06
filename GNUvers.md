# Symbol Versioning

http://www.tux.org/pub/tux/eric/elf/docs/GNUvers.txt

## Here is a normal Sun style of config file:

 * Sun の実装とドキュメントから説明
 * Sun のスタイルだと ↓ な感じ

```
	VERS_1.1 { 
			global:   foo1;
			local:    bar2; *_tmp;
		 };
	VERS_1.2 { 
			foo2; 
		 } VERS_1.1;
	VERS_2.0 {  } VERS_1.2;
```

 * 依存関係は下記の通りになる 
   * VERS_2.0 => VERS_1.2 => VERS_1.1
   * VERS_1.1 より以前のバージョンは mapfile に記述されていない全てのシンボルの base となる
 * シンボルを特定のレベルに bind しておくことができる
   * ローカルディレクティブを使ってシンボルが shared library からエクスポートされるのを防ぐ事ができる

## There are two problems with Sun's approach   
    
 * 1. 互換性の無い複数のバージョンの関数を同じライブラリで定義できない
 * 2. インタフェースが変わった際に master の設定ファイルを書き換える必要がある

 おんなじ source file で関数のバージョンを指定できるようにしたい

## Let us say we have 3 different implementations of the
function foob().

 ```c
 original_foo()
{
	return 1+bar();

}

old_foo()
{
	return 2+bar();

}

old_foo1()
{
	return 3+bar();

}

new_foo()
{
	return 4+bar();

}

__asm__(".symver original_foo,foo@");
__asm__(".symver old_foo,foo@VERS_1.1");
__asm__(".symver old_foo1,foo@VERS_1.2");
__asm__(".symver new_foo,foo@@VERS_2.0");
```

foo として export されるバージョンを指定

 * original_foo, old_foo, old_foo1, new_foo は内部の参照として使うだけで shared library から export される必要は無い
 * **local:**
 * global, weak ???
 * foo@
   * base となるバージョン
 * **foo@@VERS_2.0**
   * @が2個ついてる
   * バージョン指定されない場合にデフォルトのバージョンとして export されるシンボル
 * *Sun does have this concept of a 'weak' version, which is a
version node that has no symbols bound into it.*
   * シンボルがバインドされていないバージョン
   * バグフィックス => 新しい関数がないけど、古い関数が取り除かれる ???
 * アプリケーションが version 付きライブラリにリンクすると required interface のリストを持つ
   * shared library にリンクするとインポートされるシンボル、 required interface のリストが生成される
   * ランタイムに dynamic loader が required interface がロードされたかどうかを走査する

## Specifying the version script.


```   
	$ ld --shared ... --version-script foo.map
```

foo.map の中身

```
VERS_1.1 {
		 foo1;
};
```

別のやり方

```
	$ ld --shared ...  foo2.map
```

foo2.map の中身

```
VERSION {
	VERS_1.1 {
			 foo1;
	};
}
```

## Diagnosing problems - verifying correct usage.

```
bash$ ../binutils/objdump --dynamic-syms test2.so

test2.so:     file format elf32-i386

DYNAMIC SYMBOL TABLE:
000012c0 g    DO *ABS*	00000000 _DYNAMIC
000012b0 g    DO *ABS*	00000000 _GLOBAL_OFFSET_TABLE_
000002a0 g    DF .text	0000000c main@@GNU_1.1
00000000 l    D  *UND*	00000000 
000002ac g    DO *ABS*	00000000 _etext
00001360 g    DO *ABS*	00000000 _edata
00001360 g    DO *ABS*	00000000 __bss_start
00001360 g    DO *ABS*	00000000 _end
00000000      DF *UND*	0000001d foo@SUNW_1.3a
00000000 g    DO *ABS*	00000000 GNU_1.1
```

**--dynamic-reloc**

```
bash$ ../binutils/objdump --dynamic-reloc test2.so

test2.so:     file format elf32-i386

DYNAMIC RELOCATION RECORDS
OFFSET   TYPE              VALUE 
000012bc R_386_JUMP_SLOT   foo@SUNW_1.3a
```

 * foo が @SUNW_1.3a を要求する
 * **objdump --private-header** で確認出来る

```
bash$ ../binutils/objdump --private-header test2.so

test2.so:     file format elf32-i386

[...]

Version definitions:
1 0x01 0x0ca7523f test2.so
	
2 0x00 0x0c3b2451 GNU_1.1
	

Version references:
	Interfaces required from ./test.so:
		0x03d27931 0x00 03 SUNW_1.3a
```
