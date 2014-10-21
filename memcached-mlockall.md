# memcached の -k オプションと mlockall(2)

memcached は `-k` オプションをつけて起動すると、ページをロックする

>      -k     Lock down all paged memory. This is a somewhat dangerous option with large caches, so consult the README and memcached homepage for configuration suggestions.

すなわち、memcached がスワップしない君

## 実装

#### memcached.c

-k オプションを有効にすると、 lock_memory が true になる

```c
        case 'k':
            lock_memory = true;
            break;
```

ロックの実装は、 mlockall(2) を使っています

```c
    /* lock paged memory if needed */
    if (lock_memory) {
#ifdef HAVE_MLOCKALL
        int res = mlockall(MCL_CURRENT | MCL_FUTURE);
        if (res != 0) {
            fprintf(stderr, "warning: -k invalid, mlockall() failed: %s\n",
                    strerror(errno));
        }
#else
        fprintf(stderr, "warning: -k invalid, mlockall() not supported on this platform.  proceeding without.\n");
#endif
    }
```

これだけ。なかなか簡易の実装ですね

## mlockall とは?

http://linuxjm.sourceforge.jp/html/LDP_man-pages/man2/mlock.2.html

> mlock() と mlockall() はそれぞれ、呼び出し元プロセスの仮想アドレス空間の一部または全部を RAM 上にロックし、メモリがスワップエリアにページングされるのを防ぐ

```
MCL_CURRENT
現在、プロセスのアドレス空間にマップされている全てのページをロックする。
MCL_FUTURE
将来、プロセスのアドレス空間にマップされる全てのページをロックする。 例えば、ヒープ (heap) やスタックの成長により新しく必要になったページだけで なく、新しくメモリマップされたファイルや共有メモリ領域もロックされる。
```

カーネルがスワップアウトするページを探す際に、mlock されたページを対象外とするフラグを立てる、てな挙動だった気がします。がちゃぴん先生案件

## somewhat dangerous option

 * OS の RAM 搭載量と、キャッシュの使用量のバランスを考えて使えということだろう
 * mlockall(2) の挙動を理解できる人に可否を問うべき

## SEE ALSO

 * http://threebrothers.org/brendan/blog/using-memcached-k-prevent-paging/
   * ulimit の値に注意
 * http://mkosaki.blog46.fc2.com/blog-entry-352.html