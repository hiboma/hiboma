# Apache の IPv4 mapped IPv6 の扱い

**IPv4-mapped IPv6 address** (::ffff: の prefix を持つ IPv6 アドレス) の扱いについて

 * **APR_HAVE_IPV6** マクロで定義された区間だけ読めば追える
 * IPv4 か IPv6 かは sockaddr に隠蔽されている
 * IPv4 mapped IPv6 の扱いは apr の層だけで完結して、httpd本体では実装が隠蔽されている感じ * `sockaddr->family == AF_INET6`, `sockaddr->family == AF_INET`, IN6_IS_ADDR_V4MAPPED で分岐させてよしなしに扱う

## 参考

 * http://www2s.biglobe.ne.jp/~hig/ipv6/rfc2133.html
 * http://itpro.nikkeibp.co.jp/article/COLUMN/20100330/346408/

## IN6_IS_ADDR_V4MAPPED

glibc の実装 ( inet/netinet/in.h )。IPv4-mapped IPv6 アドレスかどうかを見る

```c
# define IN6_IS_ADDR_V4MAPPED(a) \
	((((const uint32_t *) (a))[0] == 0)				      \
	 && (((const uint32_t *) (a))[1] == 0)				      \
	 && (((const uint32_t *) (a))[2] == htonl (0xffff)))
```

`::ffff:` => `0:0:0:0:0:ffff:` を見てるのかな?

## apr_sockaddr_ip_getbuf

IPv4-mapped IPv6 address の文字列表記を IPv4 に変換して変えす処理が入っている

```c
APR_DECLARE(apr_status_t) apr_sockaddr_ip_getbuf(char *buf, apr_size_t buflen,
                                                 apr_sockaddr_t *sockaddr)
{
    /* buf に プロトコルファミリに応じたアドレスをコピー */
    if (!apr_inet_ntop(sockaddr->family, sockaddr->ipaddr_ptr, buf, buflen)) {
        return APR_ENOSPC;
    }

#if APR_HAVE_IPV6
    if (sockaddr->family == AF_INET6 
        && IN6_IS_ADDR_V4MAPPED((struct in6_addr *)sockaddr->ipaddr_ptr)
        && buflen > strlen("::ffff:")) {
        /* This is an IPv4-mapped IPv6 address; drop the leading
         * part of the address string so we're left with the familiar
         * IPv4 format.
         */
        memmove(buf, buf + strlen("::ffff:"),
                strlen(buf + strlen("::ffff:"))+1);
    }
#endif
    /* ensure NUL termination if the buffer is too short */
    buf[buflen-1] = '\0';
    return APR_SUCCESS;
}
```

memmove で `::ffff:192.168.0.1`  -> `192.168.0.1` な処理にしていますね