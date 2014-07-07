# プロセス空間へのアクセスと例外テーブル

## 5.5.1 アドレス範囲チェック

thread_info の addr_limit がプロセスのアクセス可能範囲

```c
struct thread_info {

//

	mm_segment_t		addr_limit;
```
               
 * 32bit では 0x00000000 〜 0xC000000000
 * set_fs で設定、get_fs で値を取り出す

```c 
#define get_fs()	(current_thread_info()->addr_limit)
#define set_fs(x)	(current_thread_info()->addr_limit = (x))
``` 