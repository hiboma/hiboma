# The dynamic debugging interface

## dynamic debugging interface

 * 2.6.39 でマイナーチェンジ
 * LWN でも取り上げてなかったよ

----

 * カーネルの挙動調べるのに print 埋めまくるよね
 * 大半はの出力は興味無いもの
 * 大概はコメントアウトしておけるものだけど、 edit/rebuild/reboot するサイクルの時は必要な時がある
 * で、ランタイムで enable/disable する仕組みが幾多の開発者によって作られたのであった
