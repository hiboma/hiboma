# 2.2系 の Timeout

> TimeOut ディレクティブ

```
説明:	各イベントについて、リクエストを失敗させるまでにサーバが 待つ時間を設定
構文:	TimeOut seconds
デフォルト:	TimeOut 300
コンテキスト:	サーバ設定ファイル, バーチャルホスト
ステータス:	Core
モジュール:	core
TimeOut ディレクティブは、現在のところ 以下の三つの待ち時間についての定義を行います:
```

 * GET リクエストを受け取るのにかかる総時間
 * POST や PUTリクエストにおいて、次の TCP パケットが届くまでの待ち時間
 * レスポンスを返す際、TCP の ACK が帰ってくるまでの時間

```
将来には別々の設定をすることが可能にできるよう考慮中です。 Apache 1.2 以前はタイマーは 1200 がデフォルトでしたが、 300 に下げられました。300 でもほとんどの場合は十分すぎる値です。 コード中の変な場所にまだパケットを送る際にタイマをリセットしない 場所があるかもしれないので、デフォルトをより小さい値にはしていません。
```

## ソースを追う

ディレクトティブの設定は server/core.c

```c
AP_INIT_TAKE1("Timeout", set_timeout, NULL, RSRC_CONF,
  "Timeout duration (sec)"),
```

set_timeout で値をセットする

```c
static const char *set_timeout(cmd_parms *cmd, void *dummy, const char *arg)
{
    const char *err = ap_check_cmd_context(cmd, NOT_IN_DIR_LOC_FILE|NOT_IN_LIMIT);

    if (err != NULL) {
        return err;
    }

    cmd->server->timeout = apr_time_from_sec(atoi(arg));
    return NULL;
}
```

Timeout は server_rec で保持されることが分かる


```c
static int core_pre_connection(conn_rec *c, void *csd)
{

//...

    /* The core filter requires the timeout mode to be set, which
     * incidentally sets the socket to be nonblocking.  If this
     * is not initialized correctly, Linux - for example - will
     * be initially blocking, while Solaris will be non blocking
     * and any initial read will fail.
     */
    rv = apr_socket_timeout_set(csd, c->base_server->timeout);
    if (rv != APR_SUCCESS) {
        /* expected cause is that the client disconnected already */
        ap_log_cerror(APLOG_MARK, APLOG_DEBUG, rv, c,
                      "apr_socket_timeout_set");
    }
```


```
request_rec *ap_read_request(conn_rec *conn)
{
    request_rec *r;
    apr_pool_t *p;
    const char *expect;
    int access_status;
    apr_bucket_brigade *tmp_bb;
    apr_socket_t *csd;
    apr_interval_time_t cur_timeout;

//...

    /* Get the request... */
    if (!read_request_line(r, tmp_bb)) {
        if (r->status == HTTP_REQUEST_URI_TOO_LARGE) {
            ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, r,
                          "request failed: URI too long (longer than %d)", r->server->limit_req_line);
            ap_send_error_response(r, 0);
            ap_update_child_status(conn->sbh, SERVER_BUSY_LOG, r);
            ap_run_log_transaction(r);
            apr_brigade_destroy(tmp_bb);
            return r;
        }

        apr_brigade_destroy(tmp_bb);
        return NULL;
    }

    /* We may have been in keep_alive_timeout mode, so toggle back
     * to the normal timeout mode as we fetch the header lines,
     * as necessary.
     */
    csd = ap_get_module_config(conn->conn_config, &core_module);
    apr_socket_timeout_get(csd, &cur_timeout);
    if (cur_timeout != conn->base_server->timeout) {
        apr_socket_timeout_set(csd, conn->base_server->timeout);
        cur_timeout = conn->base_server->timeout;
    }

//...

    /* Toggle to the Host:-based vhost's timeout mode to fetch the
     * request body and send the response body, if needed.
     */
    if (cur_timeout != r->server->timeout) {
        apr_socket_timeout_set(csd, r->server->timeout);
        cur_timeout = r->server->timeout;
    }

//...

    if ((access_status = ap_run_post_read_request(r))) {
        ap_die(access_status, r);
        ap_update_child_status(conn->sbh, SERVER_BUSY_LOG, r);
        ap_run_log_transaction(r);
        return NULL;
    }
```