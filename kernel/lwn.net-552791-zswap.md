# lwn.net: zswap: compressed swap caching

 * http://lwn.net/Articles/552791/

## 斜め訳

 * v3.11 から
 * ___memory compression___

``` 
Useful References:

LSFMM: In-kernel memory compression
https://lwn.net/Articles/548109/

The zswap compressed swap cache
https://lwn.net/Articles/537422/
```

## zswap

swap page の圧縮

 * プロセスの swapout されるページを、動的に確保されたRAMのメモリプールにいれとく
   * 成功すると swap device への writeback を遅延、もしくは 防ぐことができる
   * swap するシステムでめっちゃ I/O 減らせる

ベンチマーク

 * 53% の runtime reduction
 * 76% の I/O reduction
 * プールのサイズ制限に達したか buddy アロケータからページを確保できない時に圧縮したキャッシュを swap device に追いやることができる

基本原則

 * CPU <=> swap I/O 削減 とのトレードオフ
 * 圧縮キャッシュへの read/write >>>> swap device の非同期ブロックI/O

使えそうなとこ

 * RAMの少ないデスクトップ/ラップトップで swap の軽減
 * I/O を共有しててオーバーコミットしてるVMゲストで swap プレッシャーの軽減
   * hypervisor へひどい I/O がいってしまうのを防ぐ
 * SSD を swap にしている場合に write で寿命縮むのを防ぐ

zcache

 * zcache は RAM で page cache 圧縮。zcache でも swap の圧縮はできる
 * zswap は別のやり方で swap 圧縮の利便性を提供

## 設計

 *

```
 Documentation/vm/zswap.txt |   68 ++++
 fs/debugfs/file.c          |   42 ++
 include/linux/debugfs.h    |    2 +
 include/linux/zbud.h       |   22 ++
 lib/fault-inject.c         |   21 -
 mm/Kconfig                 |   30 ++
 mm/Makefile                |    2 +
 mm/zbud.c                  |  526 ++++++++++++++++++++++++
 mm/zswap.c                 |  943 ++++++++++++++++++++++++++++++++++++++++++++
 9 files changed, 1635 insertions(+), 21 deletions(-)
 create mode 100644 Documentation/vm/zswap.txt
 create mode 100644 include/linux/zbud.h
 create mode 100644 mm/zbud.c
 create mode 100644 mm/zswap.c
```