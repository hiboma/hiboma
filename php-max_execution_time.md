## max_execution_time

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