# Apache の IPv4 mapped IPv6 の扱い

 * **IPv4-mapped IPv6 address** なら IPv4 に変換して扱う
 * それ以外は AF_INET, AF_INET6 それぞれとして扱う
   * 一部 IN6_IS_ADDR_V4MAPPED で分岐させてよしなしに扱う
 * apr の層だけで完結して本体では実装は隠蔽されている

## apr_sockaddr_ip_getbuf

**IPv4-mapped IPv6 address** の文字列を IPv4 に変換する

#### 実装の詳細

 * IN6_IS_ADDR_V4MAPPED で IPv4-mapped IPv6 アドレスかどうかを見る
   * glibc の実装 ( inet/netinet/in.h )
   * `::ffff:` => `0:0:0:0:0:ffff:` を見てるのかな?

```
# define IN6_IS_ADDR_V4MAPPED(a) \
	((((const uint32_t *) (a))[0] == 0)				      \
	 && (((const uint32_t *) (a))[1] == 0)				      \
	 && (((const uint32_t *) (a))[2] == htonl (0xffff)))
```   
    
memmove で `::ffff:192.168.0.1`  -> `192.168.0.1` にする 


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
 