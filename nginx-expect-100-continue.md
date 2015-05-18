# upstream に Expect: ヘッダを送らないようにする実装

Nginx をリバースプロキシとして扱うと、クライアントが送った `Expect: 100-continue` ヘッダはリバースプロキシで削除され、upstream まで送られない

どのような仕様と実装になっているのか?

## 実装

src/http/modules/ngx_http_proxy_module.c に下記のような実装がある

 * クライアントから送られてきたヘッダを `&headers_merged` に集める
 * ただし `ngx_http_proxy_cache_headers` もしくは `ngx_http_proxy_headers` にリストされたヘッダは除く

```c
#if (NGX_HTTP_CACHE)

    h = conf->upstream.cache ? ngx_http_proxy_cache_headers:
                               ngx_http_proxy_headers;
#else

    h = ngx_http_proxy_headers;

#endif

    src = conf->headers_source->elts;
    for (i = 0; i < conf->headers_source->nelts; i++) {

        s = ngx_array_push(&headers_merged);
        if (s == NULL) {
            return NGX_ERROR;
        }

        *s = src[i];
    }

    while (h->key.len) {

        src = headers_merged.elts;
        for (i = 0; i < headers_merged.nelts; i++) {

            /* ここでマッチしたら除外される */
            if (ngx_strcasecmp(h->key.data, src[i].key.data) == 0) {
                goto next;
            }
        }

        s = ngx_array_push(&headers_merged);
        if (s == NULL) {
            return NGX_ERROR;
        }

        *s = *h;

    next:

        h++;
    }
```

`ngx_http_proxy_headers` と `ngx_http_proxy_cache_headers` は以下の通り

```c
static ngx_str_t  ngx_http_proxy_hide_headers[] = {
    ngx_string("Date"),
    ngx_string("Server"),
    ngx_string("X-Pad"),
    ngx_string("X-Accel-Expires"),
    ngx_string("X-Accel-Redirect"),
    ngx_string("X-Accel-Limit-Rate"),
    ngx_string("X-Accel-Buffering"),
    ngx_string("X-Accel-Charset"),
    ngx_null_string
};


#if (NGX_HTTP_CACHE)

static ngx_keyval_t  ngx_http_proxy_cache_headers[] = {
    { ngx_string("Host"), ngx_string("$proxy_host") },
    { ngx_string("Connection"), ngx_string("close") },
    { ngx_string("Content-Length"), ngx_string("$proxy_internal_body_length") },
    { ngx_string("Transfer-Encoding"), ngx_string("") },
    { ngx_string("Keep-Alive"), ngx_string("") },
    { ngx_string("Expect"), ngx_string("") },
    { ngx_string("Upgrade"), ngx_string("") },
    { ngx_string("If-Modified-Since"),
      ngx_string("$upstream_cache_last_modified") },
    { ngx_string("If-Unmodified-Since"), ngx_string("") },
    { ngx_string("If-None-Match"), ngx_string("") },
    { ngx_string("If-Match"), ngx_string("") },
    { ngx_string("Range"), ngx_string("") },
    { ngx_string("If-Range"), ngx_string("") },
    { ngx_null_string, ngx_null_string }
};

#endif
```

