## max_execution_time

#### USAGE

> スクリプトがパーサにより強制終了されるまでに許容される最大の 時間を秒単位で指定します。この命令は、いい加減に書かれた スクリプトがサーバーの負荷を上げることを防止するのに役立ちます。 デフォルトでは、30 に設定されています。 PHP を コマンドライン から実行する場合のデフォルト設定は 0 です。

> 最大実行時間は、システムコール、ストリーム操作等の 影響を受けません。より詳細な情報については、 set_time_limit() 関数の説明を参照ください。

> セーフモードで実行している場合にはこの設定を ini_set() で変更することはできません。次善策としては セーフモード をオフにするか あるいは php.ini 上で制限時間を変えるしかありません。

> Web サーバー側でもタイムアウトの設定項目を持ち、 その設定で PHP の実行が中断されることもあります。 Apache には Timeout ディレクティブ、IIS には CGI タイムアウト関数があり、どちらもデフォルトで 300 秒に設定されています。 これらの意味については、Web サーバーのドキュメントを参照ください。

via http://php.net/max-execution-time

#### 実装

*NIX では SIGPROF を利用してタイムアウトを実装している

```c
			zend_set_timeout(INI_INT("max_execution_time"), 0);
```

zend_set_timeout の実装は、↓

```c
void zend_set_timeout(long seconds, int reset_signals) /* {{{ */
{
	TSRMLS_FETCH();

	EG(timeout_seconds) = seconds;

#ifdef ZEND_WIN32
	if(!seconds) {
		return;
	}
	if (timeout_thread_initialized == 0 && InterlockedIncrement(&timeout_thread_initialized) == 1) {
		/* We start up this process-wide thread here and not in zend_startup(), because if Zend
		 * is initialized inside a DllMain(), you're not supposed to start threads from it.
		 */
		zend_init_timeout_thread();
	}
	PostThreadMessage(timeout_thread_id, WM_REGISTER_ZEND_TIMEOUT, (WPARAM) GetCurrentThreadId(), (LPARAM) seconds);
#else
#	ifdef HAVE_SETITIMER
	{
		struct itimerval t_r;		/* timeout requested */
		sigset_t sigset;

		if(seconds) {
			t_r.it_value.tv_sec = seconds;
			t_r.it_value.tv_usec = t_r.it_interval.tv_sec = t_r.it_interval.tv_usec = 0;

#	ifdef __CYGWIN__
			setitimer(ITIMER_REAL, &t_r, NULL);
		}
		if(reset_signals) {
			signal(SIGALRM, zend_timeout);
			sigemptyset(&sigset);
			sigaddset(&sigset, SIGALRM);
		}
#	else
			setitimer(ITIMER_PROF, &t_r, NULL);
		}
		if(reset_signals) {
			signal(SIGPROF, zend_timeout);
			sigemptyset(&sigset);
			sigaddset(&sigset, SIGPROF);
		}
#	endif
		if(reset_signals) {
			sigprocmask(SIG_UNBLOCK, &sigset, NULL);
		}
	}
#	endif
#endif
}
/* }}} */
```

SIGPROF のシグナルハンドラは `zend_timeout` で実装されている

```c
ZEND_API void zend_timeout(int dummy) /* {{{ */
{
	TSRMLS_FETCH();

	if (zend_on_timeout) {
		zend_on_timeout(EG(timeout_seconds) TSRMLS_CC);
	}

	zend_error(E_ERROR, "Maximum execution time of %d second%s exceeded", EG(timeout_seconds), EG(timeout_seconds) == 1 ? "" : "s");
}
/* }}} */
```

そして ***Maximum execution time of %d second%s exceeded*** で死ぬ