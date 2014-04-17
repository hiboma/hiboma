# The dynamic debugging interface

## dynamic debugging interface

 * 2.6.39 でマイナーチェンジ
 * LWN でも取り上げてなかったよ

----

 * カーネルの挙動調べるのに print 埋めまくるよね
 * 大半はの出力は興味無いもの
 * 大概はコメントアウトしておけるものだけど、 edit/rebuild/reboot するサイクルの時は必要な時がある
 * で、ランタイムで enable/disable する仕組みが幾多の開発者によって作られたのであった

## dynamic debugging interface で統一的なインタフェース

```c
    pr_debug(char *format, ...);
    dev_dbg(struct device *dev, char *format, ...);
```

 * CONFIG_DYNAMIC_DEBUG がセットされてない場合
   * printk + KERN_DEBUG になる
 * CONFIG_DYNAMIC_DEBUG がセットされている場合
   * 特別なデスクリプタをセットする
   * モジュールじゃなくて function, ファイル名で, 行数
     * ブート時にはオフになってる
     * でバッグメッセージが syslogd daemon にとんでっても出力されない

## /sys/kernel/debug/dynamic_debug/control

 