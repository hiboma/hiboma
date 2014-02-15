# MySQL

## Out of memory (Needed %d bytes) 

https://github.com/hiboma/vagrant-inspect-vm.overcommit

 * CentOS 6.5
 * mysql 
 * vm.overcommit_ratio=99
 * vm.overcommit_memory=2

## 再現手順

```
for i in {0..100}; do mysql -e "select sleep(180)" & done
```

このまんまだと mysql に繋げないので、`fg` して Ctrl-C で mysql クライアントを 2-3個消す

改めて mysql で繋ぐ

```
mysql -uroot

# テスト用のテーブルを作る
mysql> use test;
mysql> create table hoge (id int);
```

おもむろに INSERT しまくると `Out of memory Needed( %d bytes)` を出す

```
mysql> INSERT INTO hoge VALUES (1);
Query OK, 1 row affected (0.00 sec)

mysql> INSERT INTO hoge SELECT * FROM hoge;
ERROR 5 (HY000): Out of memory (Needed 128016 bytes)
```

### なんで出るん?

 * `vm.overcommit_ratio=99`
 * `vm.overcommit_memory=2`
 * malloc(3), mmap, mprotect の ENOMEM が返してる

上の条件が重なって Commited_AS が CommitLimit に達して出てる ENOMEM と判定できる

## INSERT時の mysqld の strace

mprotect, mmap で ENOMEM を返す

```
[pid  1257] read(38, "\3insert into hoge select * from "..., 36) = 36
[pid  1257] fcntl(38, F_SETFL, O_RDWR|O_NONBLOCK) = 0
[pid  1257] sched_setparam(38, 0x4)     = -1 EINVAL (Invalid argument)
[pid  1257] lseek(31, 0, SEEK_CUR)      = 262144
[pid  1257] mprotect(0x7fb0e8021000, 102400, PROT_READ|PROT_WRITE) = -1 ENOMEM (Cannot allocate memory)
[pid  1257] mmap(NULL, 134217728, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = 0x7fb0d0000000
[pid  1257] munmap(0x7fb0d4000000, 67108864) = 0
[pid  1257] mprotect(0x7fb0d0000000, 266240, PROT_READ|PROT_WRITE) = -1 ENOMEM (Cannot allocate memory)
[pid  1257] munmap(0x7fb0d0000000, 67108864) = 0
[pid  1257] mmap(NULL, 135168, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (Cannot allocate memory)
[pid  1257] mprotect(0x7fb0e8021000, 102400, PROT_READ|PROT_WRITE) = -1 ENOMEM (Cannot allocate memory)
[pid  1257] mmap(0x7fb0d4000000, 67108864, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_NORESERVE, -1, 0) = 0x7fb0d4000000
[pid  1257] mprotect(0x7fb0d4000000, 266240, PROT_READ|PROT_WRITE) = -1 ENOMEM (Cannot allocate memory)
[pid  1257] munmap(0x7fb0d4000000, 67108864) = 0
[pid  1257] lseek(87, 0, SEEK_CUR)      = 1572864
```

## SELECT時の mysqld の strace

```
mysql> select * from hoge;
mysql: Out of memory (Needed 73440 bytes)
ERROR 2008 (HY000): MySQL client ran out of memory
mysql> select * from hoge;
ERROR 2013 (HY000): Lost connection to MySQL server during query
```

write(2) が EAGAIN

```
[pid  1257] read(31, "\375\1\0\0\0\0\0\375\1\0\0\0\0\0\375\1\0\0\0\0\0\375\1\0\0\0\0\0\375\1\0\0"..., 131072) = 131072
[pid  1257] write(50, "\1\0\0\1\1&\0\0\2\3def\4test\4hoge\4hoge\2id\2"..., 16384) = 16384
[pid  1257] write(50, "\0\245\0011\2\0\0\246\0011\2\0\0\247\0011\2\0\0\250\0011\2\0\0\251\0011\2\0\0\252"..., 16384) = 16384
[pid  1257] write(50, "\2\0\0P\0011\2\0\0Q\0011\2\0\0R\0011\2\0\0S\0011\2\0\0T\0011\2\0"..., 16384) = 16384
[pid  1257] write(50, "\0011\2\0\0\373\0011\2\0\0\374\0011\2\0\0\375\0011\2\0\0\376\0011\2\0\0\377\0011"..., 16384) = 16384
[pid  1257] write(50, "\0\245\0011\2\0\0\246\0011\2\0\0\247\0011\2\0\0\250\0011\2\0\0\251\0011\2\0\0\252"..., 16384) = 16384
[pid  1257] write(50, "\2\0\0P\0011\2\0\0Q\0011\2\0\0R\0011\2\0\0S\0011\2\0\0T\0011\2\0"..., 16384) = 16384
[pid  1257] read(31, "\0\0\0\375\1\0\0\0\0\0\375\1\0\0\0\0\0\375\1\0\0\0\0\0\375\1\0\0\0\0\0\375"..., 131072) = 131072
[pid  1257] write(50, "\0011\2\0\0\373\0011\2\0\0\374\0011\2\0\0\375\0011\2\0\0\376\0011\2\0\0\377\0011"..., 16384) = 16384
[pid  1257] write(50, "\0\245\0011\2\0\0\246\0011\2\0\0\247\0011\2\0\0\250\0011\2\0\0\251\0011\2\0\0\252"..., 16384) = 16384
[pid  1257] write(50, "\2\0\0P\0011\2\0\0Q\0011\2\0\0R\0011\2\0\0S\0011\2\0\0T\0011\2\0"..., 16384) = 16384
[pid  1257] write(50, "\0011\2\0\0\373\0011\2\0\0\374\0011\2\0\0\375\0011\2\0\0\376\0011\2\0\0\377\0011"..., 16384) = 16384
[pid  1257] write(50, "\0\245\0011\2\0\0\246\0011\2\0\0\247\0011\2\0\0\250\0011\2\0\0\251\0011\2\0\0\252"..., 16384) = 16384
[pid  1257] write(50, "\2\0\0P\0011\2\0\0Q\0011\2\0\0R\0011\2\0\0S\0011\2\0\0T\0011\2\0"..., 16384) = 16384
[pid  1257] write(50, "\0011\2\0\0\373\0011\2\0\0\374\0011\2\0\0\375\0011\2\0\0\376\0011\2\0\0\377\0011"..., 16384) = 16000
[pid  1257] write(50, "\0e\0011\2\0\0f\0011\2\0\0g\0011\2\0\0h\0011\2\0\0i\0011\2\0\0j"..., 384) = -1 EAGAIN (Resource temporarily unavailable)
```

## "Out of memory (Needed %u bytes)" のソース

```
mysys/errors.c:  "Out of memory (Needed %u bytes)",
mysys/errors.c:  EE(EE_OUTOFMEMORY)	= "Out of memory (Needed %u bytes)";
```

### EE_OUTOFMEMORY が使われている箇所

```
$ fgrep -R EE_OUTOFMEMORY * 
include/mysys_err.h:#define EE_OUTOFMEMORY		5
mysql-test/t/error_simulation.test:# May fail with either ER_OUT_OF_RESOURCES or EE_OUTOFMEMORY
mysys/errors.c:  EE(EE_OUTOFMEMORY)	= "Out of memory (Needed %u bytes)";
mysys/mf_keycache.c:        my_error(EE_OUTOFMEMORY, MYF(0), blocks * keycache->key_cache_block_size);
mysys/my_lockmem.c:      my_error(EE_OUTOFMEMORY, MYF(ME_BELL+ME_WAITTANG),size);
mysys/my_malloc.c:      my_error(EE_OUTOFMEMORY, MYF(ME_BELL+ME_WAITTANG+ME_NOREFRESH),size);
mysys/my_once.c:	my_error(EE_OUTOFMEMORY, MYF(ME_BELL+ME_WAITTANG),get_size);
mysys/my_realloc.c:      my_error(EE_OUTOFMEMORY, MYF(ME_BELL+ME_WAITTANG),size);
mysys/my_realloc.c:      my_error(EE_OUTOFMEMORY, MYF(ME_BELL+ME_WAITTANG), size);
mysys/queues.c:    EE_OUTOFMEMORY	Wrong max_elements
mysys/safemalloc.c:      my_message(EE_OUTOFMEMORY, buff, MYF(ME_BELL+ME_WAITTANG+ME_NOREFRESH));
mysys/safemalloc.c:      my_message(EE_OUTOFMEMORY, buff, MYF(ME_BELL+ME_WAITTANG+ME_NOREFRESH));
sql/derror.cc:    EE(EE_OUTOFMEMORY)    = ER(ER_OUTOFMEMORY);
sql/sql_class.cc:    my_error(EE_OUTOFMEMORY, MYF(ME_BELL),
sql/sql_trigger.cc:    if (sql_errno != EE_OUTOFMEMORY &&
storage/myisam/myisampack.c:    my_error(EE_OUTOFMEMORY,MYF(ME_BELL),sizeof(uint)*length*2);
```

### my_malloc と EE_OUTOFMEMORY

 * malloc(3) のラッパー
 * `my_error = errno`
 
```c
void *my_malloc(size_t size, myf my_flags)
{
  void* point;
  DBUG_ENTER("my_malloc");
  DBUG_PRINT("my",("size: %lu  my_flags: %d", (ulong) size, my_flags));

  if (!size)
    size=1;					/* Safety */

  point= (char *) malloc(size);
  DBUG_EXECUTE_IF("simulate_out_of_memory",
                  {
                    free(point);
                    point= NULL;
                  });

  if (point == NULL)
  {
    my_errno=errno;
    if (my_flags & MY_FAE)
      error_handler_hook=fatal_error_handler_hook;
    if (my_flags & (MY_FAE+MY_WME))
      my_error(EE_OUTOFMEMORY, MYF(ME_BELL+ME_WAITTANG+ME_NOREFRESH),size);
    DBUG_EXECUTE_IF("simulate_out_of_memory",
                    DBUG_SET("-d,simulate_out_of_memory"););
    if (my_flags & MY_FAE)
      exit(1);
  }
  else if (my_flags & MY_ZEROFILL)
    bzero(point,size);
  DBUG_PRINT("exit",("ptr: 0x%lx", (long) point));
  DBUG_RETURN((void*) point);
} /* my_malloc */
```
 
### my_once_alloc と EE_OUTOFMEMORY

 * free する必要のない malloc
 * malloc のラッパー
   * システムコールは ENOMEM でよさそ

```
/*
  Alloc for things we don't nead to free

  SYNOPSIS
    my_once_alloc()
      Size
      MyFlags

  NOTES
    No DBUG_ENTER... here to get smaller dbug-startup 
*/

void* my_once_alloc(size_t Size, myf MyFlags)
{
  size_t get_size, max_left;
  uchar* point;
  reg1 USED_MEM *next;
  reg2 USED_MEM **prev;

  Size= ALIGN_SIZE(Size);
  prev= &my_once_root_block;
  max_left=0;
  for (next=my_once_root_block ; next && next->left < Size ; next= next->next)
  {
    if (next->left > max_left)
      max_left=next->left;
    prev= &next->next;
  }
  if (! next)
  {						/* Time to alloc new block */
    get_size= Size+ALIGN_SIZE(sizeof(USED_MEM));
    if (max_left*4 < my_once_extra && get_size < my_once_extra)
      get_size=my_once_extra;			/* Normal alloc */

    if ((next = (USED_MEM*) malloc(get_size)) == 0)
    {
      my_errno=errno;
      if (MyFlags & (MY_FAE+MY_WME))
	my_error(EE_OUTOFMEMORY, MYF(ME_BELL+ME_WAITTANG),get_size);
      return((uchar*) 0);
    }
    DBUG_PRINT("test",("my_once_malloc %lu byte malloced", (ulong) get_size));
    next->next= 0;
    next->size= get_size;
    next->left= get_size-ALIGN_SIZE(sizeof(USED_MEM));
    *prev=next;
  }
  point= (uchar*) ((char*) next+ (next->size-next->left));
  next->left-= Size;

  if (MyFlags & MY_ZEROFILL)
    bzero(point, Size);
  return((void*) point);
} /* my_once_alloc */
```