# rsync のタイムアウト

## まとめ

rsync のタイムアウトは 3種ある。下記は内部で使われる変数名である

 * io_timeout
   * --timeout でセットされる
   * I/O のタイムアウト。
     * 一定時間パケットの送受信が無い場合にタイムアウトする
     * 「転送時間のタイムアウト」といったらこれ
 * select_timeout
   * 暗黙的にセットされる
   * 最大60秒、io_timeout と同値にセットされる
 * connect_timeout
   * --contimeout でセットされる
   * 2系には無い
   * rsync daemon に繋ぐ際のタイムアウト値である。ssh の場合は ssh_config の設定が採用されるのかな?

これらの数値を追うとタイムアウトの実装が追える   

## コマンドラインオプションと定義

```c
  rprintf(F,"     --timeout=SECONDS       set I/O timeout in seconds\n");
  rprintf(F,"     --contimeout=SECONDS    set daemon connection timeout in seconds\n");
```

main.c に書いてあるオプション

```c
int io_timeout = 0;
int connect_timeout = 0;

/* 略 */

  {"timeout",          0,  POPT_ARG_INT,    &io_timeout, 0, 0, 0 },
  {"no-timeout",       0,  POPT_ARG_VAL,    &io_timeout, 0, 0, 0 },
  {"contimeout",       0,  POPT_ARG_INT,    &connect_timeout, 0, 0, 0 },
  {"no-contimeout",    0,  POPT_ARG_VAL,    &connect_timeout, 0, 0, 0 },
```

## io_timeout

io_timeout は **set_io_timeout** を通してセットする

```c
	set_io_timeout(io_timeout);
```

io_timeout とは別で **select_timeout** が存在する

SELECT_TIMEOUT = 60秒 を上限として select(2) のタイムアウトとして用いられる

```
/** If no timeout is specified then use a 60 second select timeout */
#define SELECT_TIMEOUT 60

void set_io_timeout(int secs)
{
	io_timeout = secs;

	if (!io_timeout || io_timeout > SELECT_TIMEOUT)
		select_timeout = SELECT_TIMEOUT;
	else
		select_timeout = io_timeout;

	allowed_lull = read_batch ? 0 : (io_timeout + 1) / 2;
}
```

alarm(2) などは使わずに 

 * select(2) でタイムアウトを指定して待つ
 * ブロックが続くと select(2) がタイムアウトする
 * タイムアウトした時間の累計が io_timeout をオーバーしていたら転送を中断

という実装な様子

### io_timeout の判定コード

タイムアウトは check_timeout で判定される

 * last_io_in 最後に IO の input ? した時刻と現在時刻の差分 と io_timeout を比較
 * RERR_TIMEOUT = 30 で exit する

```c
static void check_timeout(void)
{
	time_t t;

	if (!io_timeout || ignore_timeout)
		return;

	if (!last_io_in) {
		last_io_in = time(NULL);
		return;
	}

	t = time(NULL);

	if (t - last_io_in >= io_timeout) {
		if (!am_server && !am_daemon) {
			rprintf(FERROR, "io timeout after %d seconds -- exiting\n",
				(int)(t-last_io_in));
		}
		exit_cleanup(RERR_TIMEOUT);
	}
}
```

check_timeout がどのように使われているかは割愛

## connect_timeout

rsync daemon に繋ぐ際のタイムアウト値である

```
       --contimeout
              This option allows you to set the amount of time that rsync will
              wait  for  its connection to an rsync daemon to succeed.  If the
              timeout is reached, rsync exits with an error.

```

connect(2) のタイムアウトで、alarm(2) で実装されている

```c
		if (connect_timeout > 0) {
			SIGACTION(SIGALRM, contimeout_handler);
			alarm(connect_timeout);
		}

		set_socket_options(s, sockopts);
		while (connect(s, res->ai_addr, res->ai_addrlen) < 0) {
			if (connect_timeout < 0)
				exit_cleanup(RERR_CONTIMEOUT);
			if (errno == EINTR)
				continue;
			close(s);
			s = -1;
			break;
		}

		if (connect_timeout > 0)
			alarm(0);
```