# Apache の IPv4 mapped IPv6 の扱い

**IPv4-mapped IPv6 address** (::ffff: の prefix を持つ IPv6 アドレス) の扱いについて

 * **APR_HAVE_IPV6** マクロで定義された区間だけ読めば追える
 * IPv4 か IPv6 かは sockaddr に隠蔽されている
 * IPv4 mapped IPv6 の扱いは apr の層だけで完結して、httpd本体では実装が隠蔽されている感じ * `sockaddr->family == AF_INET6`, `sockaddr->family == AF_INET`, IN6_IS_ADDR_V4MAPPED で分岐させてよしなしに扱う

## 参考

 * http://www2s.biglobe.ne.jp/~hig/ipv6/rfc2133.html
 * http://itpro.nikkeibp.co.jp/article/COLUMN/20100330/346408/

## 例えばこんなコード

### apr_sockaddr_ip_getbuf

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

## 他にもこんなコード

```c
APR_DECLARE(apr_status_t) apr_parse_addr_port(char **addr,
                                              char **scope_id,
                                              apr_port_t *port,
                                              const char *str,
                                              apr_pool_t *p)
{
    const char *ch, *lastchar;
    int big_port;
    apr_size_t addrlen;

// ...

#if APR_HAVE_IPV6
    if (*str == '[') {
        const char *end_bracket = memchr(str, ']', addrlen);
        struct in6_addr ipaddr;
        const char *scope_delim;

        if (!end_bracket || end_bracket != lastchar) {
            *port = 0;
            return APR_EINVAL;
        }

        /* handle scope id; this is the only context where it is allowed */
        scope_delim = memchr(str, '%', addrlen);
        if (scope_delim) {
            if (scope_delim == end_bracket - 1) { /* '%' without scope id */
                *port = 0;
                return APR_EINVAL;
            }
            addrlen = scope_delim - str - 1;
            *scope_id = apr_palloc(p, end_bracket - scope_delim);
            memcpy(*scope_id, scope_delim + 1, end_bracket - scope_delim - 1);
            (*scope_id)[end_bracket - scope_delim - 1] = '\0';
        }
        else {
            addrlen = addrlen - 2; /* minus 2 for '[' and ']' */
        }

        *addr = apr_palloc(p, addrlen + 1);
        memcpy(*addr,
               str + 1,
               addrlen);
        (*addr)[addrlen] = '\0';
        if (apr_inet_pton(AF_INET6, *addr, &ipaddr) != 1) {
            *addr = NULL;
            *scope_id = NULL;
            *port = 0;
            return APR_EINVAL;
        }
    }
    else 
#endif
```

```c
        hostname = family == AF_INET6 ? "::" : "0.0.0.0";
        servname = NULL;
```

```c
    ai = ai_list;
    while (ai) { /* while more addresses to report */
        apr_sockaddr_t *new_sa;

        /* Ignore anything bogus: getaddrinfo in some old versions of
         * glibc will return AF_UNIX entries for APR_UNSPEC+AI_PASSIVE
         * lookups. */
#if APR_HAVE_IPV6
        if (ai->ai_family != AF_INET && ai->ai_family != AF_INET6) {
#else
        if (ai->ai_family != AF_INET) {
#endif
            ai = ai->ai_next;
            continue;
        }

        new_sa = apr_pcalloc(p, sizeof(apr_sockaddr_t));

        new_sa->pool = p;
        memcpy(&new_sa->sa, ai->ai_addr, ai->ai_addrlen);
        apr_sockaddr_vars_set(new_sa, ai->ai_family, port);
```

```c
static apr_status_t parse_ip(apr_ipsubnet_t *ipsub, const char *ipstr, int network_allowed)
{
    /* supported flavors of IP:
     *
     * . IPv6 numeric address string (e.g., "fe80::1")
     * 
     *   IMPORTANT: Don't store IPv4-mapped IPv6 address as an IPv6 address.
     *
     * . IPv4 numeric address string (e.g., "127.0.0.1")
     *
     * . IPv4 network string (e.g., "9.67")
     *
     *   IMPORTANT: This network form is only allowed if network_allowed is on.
     */
    int rc;

#if APR_HAVE_IPV6
    rc = apr_inet_pton(AF_INET6, ipstr, ipsub->sub);
    if (rc == 1) {
        if (IN6_IS_ADDR_V4MAPPED((struct in6_addr *)ipsub->sub)) {
            /* apr_ipsubnet_test() assumes that we don't create IPv4-mapped IPv6
             * addresses; this of course forces the user to specify IPv4 addresses
             * in a.b.c.d style instead of ::ffff:a.b.c.d style.
             */
            return APR_EBADIP;
        }
        ipsub->family = AF_INET6;
    }
    else
#endif
    {
        rc = apr_inet_pton(AF_INET, ipstr, ipsub->sub);
        if (rc == 1) {
            ipsub->family = AF_INET;
        }
    }
    if (rc != 1) {
        if (network_allowed) {
            return parse_network(ipsub, ipstr);
        }
        else {
            return APR_EBADIP;
        }
    }
    return APR_SUCCESS;
}
```

## IN6_IS_ADDR_V4MAPPED

glibc の実装 ( inet/netinet/in.h )。IPv4-mapped IPv6 アドレスかどうかを見る

```c
# define IN6_IS_ADDR_V4MAPPED(a) \
	((((const uint32_t *) (a))[0] == 0)				      \
	 && (((const uint32_t *) (a))[1] == 0)				      \
	 && (((const uint32_t *) (a))[2] == htonl (0xffff)))
```

`::ffff:` => `0:0:0:0:0:ffff:` を見てるのかな?
