# ngx_http_ssl_module, ngx_event_openssl

```c
    { ngx_string("ssl_protocols"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_CONF_1MORE,
      ngx_conf_set_bitmask_slot,
      NGX_HTTP_SRV_CONF_OFFSET,
      offsetof(ngx_http_ssl_srv_conf_t, protocols),
      &ngx_http_ssl_protocols },

static ngx_conf_bitmask_t  ngx_http_ssl_protocols[] = {
    { ngx_string("SSLv2"), NGX_SSL_SSLv2 },
    { ngx_string("SSLv3"), NGX_SSL_SSLv3 },
    { ngx_string("TLSv1"), NGX_SSL_TLSv1 },
    { ngx_string("TLSv1.1"), NGX_SSL_TLSv1_1 },
    { ngx_string("TLSv1.2"), NGX_SSL_TLSv1_2 },
    { ngx_null_string, 0 }
};
```

```c
ngx_int_t
ngx_ssl_create(ngx_ssl_t *ssl, ngx_uint_t protocols, void *data)
{
    ssl->ctx = SSL_CTX_new(SSLv23_method());

//...

    SSL_CTX_set_options(ssl->ctx, SSL_OP_SINGLE_DH_USE);

    if (!(protocols & NGX_SSL_SSLv2)) {
        SSL_CTX_set_options(ssl->ctx, SSL_OP_NO_SSLv2);
    }
    if (!(protocols & NGX_SSL_SSLv3)) {
        SSL_CTX_set_options(ssl->ctx, SSL_OP_NO_SSLv3);
    }
    if (!(protocols & NGX_SSL_TLSv1)) {
        SSL_CTX_set_options(ssl->ctx, SSL_OP_NO_TLSv1);
    }
#ifdef SSL_OP_NO_TLSv1_1
    if (!(protocols & NGX_SSL_TLSv1_1)) {
        SSL_CTX_set_options(ssl->ctx, SSL_OP_NO_TLSv1_1);
    }
#endif
#ifdef SSL_OP_NO_TLSv1_2
    if (!(protocols & NGX_SSL_TLSv1_2)) {
        SSL_CTX_set_options(ssl->ctx, SSL_OP_NO_TLSv1_2);
    }
#endif
```
