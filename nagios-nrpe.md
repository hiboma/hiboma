## Host %s is not allowed to talk to us!

nrpe が syslog で出すログ

 * allowed_hosts に含まれていない場合に弾く様子

```c
					/* is this is a blessed machine? */
					if(allowed_hosts) {
						switch(addr.ss_family) {
						case AF_INET:
							nptr = (struct sockaddr_in *)&addr;

							/* log info to syslog facility */
							if(debug==TRUE) {
								syslog(LOG_DEBUG, "Connection from %s port %d",
										inet_ntoa(nptr->sin_addr), 
										nptr->sin_port);
								}
							if(!is_an_allowed_host(AF_INET,
									(void *)&(nptr->sin_addr))) {
								/* log error to syslog facility */
								syslog(LOG_ERR,
										"Host %s is not allowed to talk to us!",
										inet_ntoa(nptr->sin_addr));
```

## CHECK_NRPE: Error - Could not complete SSL handshake

原因のよく分からないエラーのあれ。nrpe-2.15/src/check_nrpe.c の実装を追うと下記の通り

 * プラグインの SSL_connect が原因だが ..
 * DEBUG をつけないと errorno 等見れない。ヒドイ

```c
#ifdef HAVE_SSL
	/* do SSL handshake */
	if(result==STATE_OK && use_ssl==TRUE){
		if((ssl=SSL_new(ctx))!=NULL){
			SSL_CTX_set_cipher_list(ctx,"ADH");
			SSL_set_fd(ssl,sd);
			if((rc=SSL_connect(ssl))!=1){
				printf("CHECK_NRPE: Error - Could not complete SSL handshake.\n");
#ifdef DEBUG
				printf("SSL_connect=%d\n",rc);
				/*
				rc=SSL_get_error(ssl,rc);
				printf("SSL_get_error=%d\n",rc);
				printf("ERR_get_error=%lu\n",ERR_get_error());
				printf("%s\n",ERR_error_string(rc,NULL));
				*/
				ERR_print_errors_fp(stdout);
#endif
				result=STATE_CRITICAL;
			        }
		        }
		else{
			printf("CHECK_NRPE: Error - Could not create SSL connection structure.\n");
			result=STATE_CRITICAL;
		        }

		/* bail if we had errors */
		if(result!=STATE_OK){
			SSL_CTX_free(ctx);
			close(sd);
			exit(result);
		        }
	        }
#endif
```

一方の nrpe (デーモン) 側ではエラーを syslog で出す様だけど、SSL_accept の段階らしい

```c
#ifdef HAVE_SSL
	/* do SSL handshake */
	if(result==STATE_OK && use_ssl==TRUE){
		if((ssl=SSL_new(ctx))!=NULL){
			SSL_set_fd(ssl,sock);

			/* keep attempting the request if needed */
                        while(((rc=SSL_accept(ssl))!=1) && (SSL_get_error(ssl,rc)==SSL_ERROR_WANT_READ));

			if(rc!=1){
				syslog(LOG_ERR,"Error: Could not complete SSL handshake. %d\n",SSL_get_error(ssl,rc));
#ifdef DEBUG
				errfp=fopen("/tmp/err.log","w");
				ERR_print_errors_fp(errfp);
				fclose(errfp);
#endif
				return;
			        }
		        }
		else{
			syslog(LOG_ERR,"Error: Could not create SSL connection structure.\n");
#ifdef DEBUG
			errfp=fopen("/tmp/err.log","w");
			ERR_print_errors_fp(errfp);
			fclose(errfp);
#endif
			return;
		        }
	        }
#endif
```