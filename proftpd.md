# proftpd

 * サーバからクライアントにファイルを転送するのは RETRコマンド
 * modules/mod_xfer.c の `MODRET xfer_retr(cmd_rec *cmd)` で実装されている
 * fadvise(2) できる?

## APIメモ

 * `pr_fh_t *pr_fsio_open(const char *name, int flags)`
   * open(2) のラッパー

```c
typedef struct fh_rec pr_fh_t;
struct fh_rec {

  /* Pool for this object's use */
  pool *fh_pool;

  int fh_fd;
  char *fh_path;

  /* Arbitrary data associated with this file. */
  void *fh_data;

  /* Pointer to the filesystem in which this file is located. */
  pr_fs_t *fh_fs;

  /* For buffer I/O on this file, should anything choose to use it. */
  pr_buffer_t *fh_buf;

  /* Hint of the optimal buffer size for IO on this file. */
  size_t fh_iosz;
};
```

 * fh_fd がファイルデスクリプタかな?