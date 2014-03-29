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