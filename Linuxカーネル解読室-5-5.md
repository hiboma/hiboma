# プロセス空間へのアクセスと例外テーブル

## 5.5.1 アドレス範囲チェック

```c
struct thread_info {

//

	mm_segment_t		addr_limit;
```