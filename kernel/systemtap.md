
probe ポイント多過ぎてカーネルごと死ぬ例

```c
probe kernel.function("*").call
{
 if (pid() == target())
     printf ("%s -> %s\n", thread_indent(1), probefunc())
}

probe kernel.function("*").return
{
 if (pid() == target())
     printf ("%s <- %s\n", thread_indent(-1), probefunc())
}
```

次くらいだと動いてくれる

```c
probe kernel.function("*/fs/*.c").call
{
 if (pid() == target())
     printf ("%s -> %s\n", thread_indent(1), probefunc())
}
```