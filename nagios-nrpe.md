## Host %s is not allowed to talk to us!

nrpe が syslog で出すログ

 * accpet -> getppername で ピア側の IP を出す
 * IP が allowed_hosts に含まれていない場合に弾く様子

```c
			/* accept a new connection request */
			new_sd = accept(listen_socks[i], (struct sockaddr *)&from, &fromlen);

//...

					/* find out who just connected... */
					addrlen=sizeof(addr);
					rc=getpeername(new_sd, (struct sockaddr *)&addr, &addrlen);

//...

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

is_an_allowed_host で許可されたホストかどうかの ACL 判定する。

 * ピアのIP を IP許可リストと照らし合わせる
 * ピアのIP を ホスト名での許可リストと照らし合わせる
   * gethostbyname(3) でホスト名を IP に変換してから比較する

```c
/* Checks connectiong host in ACL
 *
 * Returns:
 * 1 - on success
 * 0 - on failure
 */

int is_an_allowed_host(int family, void *host) {
	struct ip_acl *ip_acl_curr = ip_acl_head;
	int		nbytes;
	int		x;
	struct dns_acl *dns_acl_curr = dns_acl_head;
	struct in_addr addr;
	struct in6_addr addr6;
	struct hostent *he;

	while (ip_acl_curr != NULL) {
		if(ip_acl_curr->family == family) {
			switch(ip_acl_curr->family) {
			case AF_INET:
				if((((struct in_addr *)host)->s_addr & 
						ip_acl_curr->mask.s_addr) == 
						ip_acl_curr->addr.s_addr) {
					return 1;
					}
				break;
			case AF_INET6:
				nbytes = sizeof(ip_acl_curr->mask6.s6_addr) / 
						sizeof(ip_acl_curr->mask6.s6_addr[0]);
				for(x = 0; x < nbytes; x++) {
					if((((struct in6_addr *)host)->s6_addr[x] & 
							ip_acl_curr->mask6.s6_addr[x]) != 
							ip_acl_curr->addr6.s6_addr[x]) {
						break;
						}
					}
				if(x == nbytes) { 
					/* All bytes in host's address pass the netmask mask */
					return 1;
					}
				break;
				}
			}
		ip_acl_curr = ip_acl_curr->next;
        }

	while(dns_acl_curr != NULL) {
        /* ホスト名を IP に返る */
   		he = gethostbyname(dns_acl_curr->domain);
		if (he == NULL) return 0;

		while (*he->h_addr_list) {
			switch(he->h_addrtype) {
			case AF_INET:
				memmove((char *)&addr,*he->h_addr_list++, sizeof(addr));
				if (addr.s_addr == ((struct in_addr *)host)->s_addr) return 1;
				break;
			case AF_INET6:
				memcpy((char *)&addr6, *he->h_addr_list++, sizeof(addr6));
				for(x = 0; x < nbytes; x++) {
					if(addr6.s6_addr[x] != 
							((struct in6_addr *)host)->s6_addr[x]) {
						break;
						}
					}
				if(x == nbytes) { 
					/* All bytes in host's address match the ACL */
					return 1;
					}
				break;
				}
			}
		dns_acl_curr = dns_acl_curr->next;
		}
	return 0;
	}
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