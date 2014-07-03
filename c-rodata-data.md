# C の .rodata と .data

`char []` と `char *` の違いについて、#あるある のやつ

 * http://c-faq.com/aryptr/aryptr2.html
 * http://stackoverflow.com/questions/10186765/char-array-vs-char-pointer-in-c

### char *

```c
char string[] = "@@@@@@@@@@@@@";

int main()
{
	return 0;
}
```

string は rodata に配置されている

```
$ objdump -s -j .rodata ./a.out 

./a.out:     file format elf64-x86-64

Contents of section .rodata:
 400568 01000200 00000000 00000000 00000000  ................
 400578 40404040 40404040 40404040 4000      @@@@@@@@@@@@@.
```

data は特にない

```
$ objdump -s -j .data ./a.out 

./a.out:     file format elf64-x86-64

Contents of section .data:
 600810 00000000 00000000 78054000 00000000  ........x.@.....
```

### char []

```c
char string[] = "@@@@@@@@@@@@@";

int main()
{
	return 0;
}
```

rodata には何も無い

``` 
$ objdump -s -j .rodata ./a.out 

./a.out:     file format elf64-x86-64

Contents of section .rodata:
 400568 01000200 00000000 00000000 00000000  ................
```

string は .data に配置されている

```
$ objdump -s -j .data ./a.out 

./a.out:     file format elf64-x86-64

Contents of section .data:
 600800 00000000 40404040 40404040 40404040  ....@@@@@@@@@@@@
 600810 40000000                             @...
```

rodata のデータは書き込み権限の無いメモリリージョンに配置されるので、変更を加えようとすると SIGSEGV を出す