# mod_status.c

## R = Reading Request

```c
     if (short_report)
         ap_rputs("\n", r);
     else {
         ap_rputs("</pre>\n", r);
         ap_rputs("<p>Scoreboard Key:<br />\n", r);
         ap_rputs("\"<b><code>_</code></b>\" Waiting for Connection, \n", r);
         ap_rputs("\"<b><code>S</code></b>\" Starting up, \n", r);
         ap_rputs("\"<b><code>R</code></b>\" Reading Request,<br />\n", r);
         ap_rputs("\"<b><code>W</code></b>\" Sending Reply, \n", r);
         ap_rputs("\"<b><code>K</code></b>\" Keepalive (read), \n", r);
         ap_rputs("\"<b><code>D</code></b>\" DNS Lookup,<br />\n", r);
         ap_rputs("\"<b><code>C</code></b>\" Closing connection, \n", r);
         ap_rputs("\"<b><code>L</code></b>\" Logging, \n", r);
         ap_rputs("\"<b><code>G</code></b>\" Gracefully finishing,<br /> \n", r);
         ap_rputs("\"<b><code>I</code></b>\" Idle cleanup of worker, \n", r);
         ap_rputs("\"<b><code>.</code></b>\" Open slot with no current process</p>\n", r);
         ap_rputs("<p />\n", r);
         if (!ap_extended_status) {
             int j;
             int k = 0;
             ap_rputs("PID Key: <br />\n", r);
             ap_rputs("<pre>\n", r);
             for (i = 0; i < server_limit; ++i) {
                 for (j = 0; j < thread_limit; ++j) {
                     int indx = (i * thread_limit) + j;
 
                     if (stat_buffer[indx] != '.') {
                         ap_rprintf(r, "   %" APR_PID_T_FMT
                                    " in state: %c ", pid_buffer[i],
                                    stat_buffer[indx]);
```

status_flags に統計情報が入ってる

```c
            stat_buffer[indx] = status_flags[res];
```

status_flags は ↓ みたいな array

```c
static int status_init(apr_pool_t *p, apr_pool_t *plog, apr_pool_t *ptemp,
                       server_rec *s)
{
    status_flags[SERVER_DEAD] = '.';  /* We don't want to assume these are in */
    status_flags[SERVER_READY] = '_'; /* any particular order in scoreboard.h */
    status_flags[SERVER_STARTING] = 'S';
    status_flags[SERVER_BUSY_READ] = 'R';
```

SERVER_BUSY_READ にセットされるのは **ap_process_http_connection**

 * accept(2) してヘッダを読んでパース、ap_process_request の直前までが SERVER_BUSY_READ

```c
static int ap_process_http_connection(conn_rec *c)
{
    request_rec *r;
    apr_socket_t *csd = NULL;

    /*
     * Read and process each request found on our connection
     * until no requests are left or we decide to close.
     */

    ap_update_child_status(c->sbh, SERVER_BUSY_READ, NULL);
    while ((r = ap_read_request(c)) != NULL) {

        c->keepalive = AP_CONN_UNKNOWN;
        /* process the request if it was read without error */

        ap_update_child_status(c->sbh, SERVER_BUSY_WRITE, r);
        if (r->status == HTTP_OK)
            ap_process_request(r);

        if (ap_extended_status)
            ap_increment_counts(c->sbh, r);

        if (c->keepalive != AP_CONN_KEEPALIVE || c->aborted)
            break;

        ap_update_child_status(c->sbh, SERVER_BUSY_KEEPALIVE, r);
        apr_pool_destroy(r->pool);

        if (ap_graceful_stop_signalled())
            break;

        if (!csd) {
            csd = ap_get_module_config(c->conn_config, &core_module);
        }
        apr_socket_opt_set(csd, APR_INCOMPLETE_READ, 1);
        apr_socket_timeout_set(csd, c->base_server->keep_alive_timeout);
        /* Go straight to select() to wait for the next request */
    }

    return OK;
}
```

ap_read_request の中身

 * read_request_line でブロックしそう
 * time ??? を呼び出したら ap_rgetline 終わり

```c
request_rec *ap_read_request(conn_rec *conn)
{
    request_rec *r;
    apr_pool_t *p;
    const char *expect;
    int access_status;
    apr_bucket_brigade *tmp_bb;
    apr_socket_t *csd;
    apr_interval_time_t cur_timeout;

    apr_pool_create(&p, conn->pool);
    apr_pool_tag(p, "request");
    r = apr_pcalloc(p, sizeof(request_rec));
    r->pool            = p;
    r->connection      = conn;
    r->server          = conn->base_server;

    r->user            = NULL;
    r->ap_auth_type    = NULL;

    r->allowed_methods = ap_make_method_list(p, 2);

    r->headers_in      = apr_table_make(r->pool, 25);
    r->subprocess_env  = apr_table_make(r->pool, 25);
    r->headers_out     = apr_table_make(r->pool, 12);
    r->err_headers_out = apr_table_make(r->pool, 5);
    r->notes           = apr_table_make(r->pool, 5);

    r->request_config  = ap_create_request_config(r->pool);
    /* Must be set before we run create request hook */

    r->proto_output_filters = conn->output_filters;
    r->output_filters  = r->proto_output_filters;
    r->proto_input_filters = conn->input_filters;
    r->input_filters   = r->proto_input_filters;
    ap_run_create_request(r);
    r->per_dir_config  = r->server->lookup_defaults;

    r->sent_bodyct     = 0;                      /* bytect isn't for body */

    r->read_length     = 0;
    r->read_body       = REQUEST_NO_BODY;

    r->status          = HTTP_OK;  /* Until further notice */
    r->the_request     = NULL;

    /* Begin by presuming any module can make its own path_info assumptions,
     * until some module interjects and changes the value.
     */
    r->used_path_info = AP_REQ_DEFAULT_PATH_INFO;

    tmp_bb = apr_brigade_create(r->pool, r->connection->bucket_alloc);

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
        else if (r->status == HTTP_REQUEST_TIME_OUT) {
            ap_update_child_status(conn->sbh, SERVER_BUSY_LOG, r);
            if (!r->connection->keepalives) {
                ap_run_log_transaction(r);
            }
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

    if (!r->assbackwards) {
        ap_get_mime_headers_core(r, tmp_bb);
        if (r->status != HTTP_OK) {
            ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, r,
                          "request failed: error reading the headers");
            ap_send_error_response(r, 0);
            ap_update_child_status(conn->sbh, SERVER_BUSY_LOG, r);
            ap_run_log_transaction(r);
            apr_brigade_destroy(tmp_bb);
            return r;
        }

        if (apr_table_get(r->headers_in, "Transfer-Encoding")
            && apr_table_get(r->headers_in, "Content-Length")) {
            /* 2616 section 4.4, point 3: "if both Transfer-Encoding
             * and Content-Length are received, the latter MUST be
             * ignored"; so unset it here to prevent any confusion
             * later. */
            apr_table_unset(r->headers_in, "Content-Length");
        }
    }
    else {
        if (r->header_only) {
            /*
             * Client asked for headers only with HTTP/0.9, which doesn't send
             * headers! Have to dink things just to make sure the error message
             * comes through...
             */
            ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, r,
                          "client sent invalid HTTP/0.9 request: HEAD %s",
                          r->uri);
            r->header_only = 0;
            r->status = HTTP_BAD_REQUEST;
            ap_send_error_response(r, 0);
            ap_update_child_status(conn->sbh, SERVER_BUSY_LOG, r);
            ap_run_log_transaction(r);
            apr_brigade_destroy(tmp_bb);
            return r;
        }
    }

    apr_brigade_destroy(tmp_bb);

    /* update what we think the virtual host is based on the headers we've
     * now read. may update status.
     */
    ap_update_vhost_from_headers(r);

    /* Toggle to the Host:-based vhost's timeout mode to fetch the
     * request body and send the response body, if needed.
     */
    if (cur_timeout != r->server->timeout) {
        apr_socket_timeout_set(csd, r->server->timeout);
        cur_timeout = r->server->timeout;
    }

    /* we may have switched to another server */
    r->per_dir_config = r->server->lookup_defaults;

    if ((!r->hostname && (r->proto_num >= HTTP_VERSION(1, 1)))
        || ((r->proto_num == HTTP_VERSION(1, 1))
            && !apr_table_get(r->headers_in, "Host"))) {
        /*
         * Client sent us an HTTP/1.1 or later request without telling us the
         * hostname, either with a full URL or a Host: header. We therefore
         * need to (as per the 1.1 spec) send an error.  As a special case,
         * HTTP/1.1 mentions twice (S9, S14.23) that a request MUST contain
         * a Host: header, and the server MUST respond with 400 if it doesn't.
         */
        r->status = HTTP_BAD_REQUEST;
        ap_log_rerror(APLOG_MARK, APLOG_ERR, 0, r,
                      "client sent HTTP/1.1 request without hostname "
                      "(see RFC2616 section 14.23): %s", r->uri);
    }

    /*
     * Add the HTTP_IN filter here to ensure that ap_discard_request_body
     * called by ap_die and by ap_send_error_response works correctly on
     * status codes that do not cause the connection to be dropped and
     * in situations where the connection should be kept alive.
     */

    ap_add_input_filter_handle(ap_http_input_filter_handle,
                               NULL, r, r->connection);

    if (r->status != HTTP_OK) {
        ap_send_error_response(r, 0);
        ap_update_child_status(conn->sbh, SERVER_BUSY_LOG, r);
        ap_run_log_transaction(r);
        return r;
    }

    if ((access_status = ap_run_post_read_request(r))) {
        ap_die(access_status, r);
        ap_update_child_status(conn->sbh, SERVER_BUSY_LOG, r);
        ap_run_log_transaction(r);
        return NULL;
    }

    if (((expect = apr_table_get(r->headers_in, "Expect")) != NULL)
        && (expect[0] != '\0')) {
        /*
         * The Expect header field was added to HTTP/1.1 after RFC 2068
         * as a means to signal when a 100 response is desired and,
         * unfortunately, to signal a poor man's mandatory extension that
         * the server must understand or return 417 Expectation Failed.
         */
        if (strcasecmp(expect, "100-continue") == 0) {
            r->expecting_100 = 1;
        }
        else {
            r->status = HTTP_EXPECTATION_FAILED;
            ap_log_rerror(APLOG_MARK, APLOG_INFO, 0, r,
                          "client sent an unrecognized expectation value of "
                          "Expect: %s", expect);
            ap_send_error_response(r, 0);
            ap_update_child_status(conn->sbh, SERVER_BUSY_LOG, r);
            ap_run_log_transaction(r);
            return r;
        }
    }

    return r;
}
```
