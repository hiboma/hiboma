# nagios nrpe

## OpenSSL の実装メモ

check_nrpe 側のコードだと以下のふたつのコードで 非SSLのインタフェースを SSL に対応できるようにしている

TLS1 で通信

### OpenSSL セットアップのコード

```c
#ifdef HAVE_SSL
	/* initialize SSL */
	if(use_ssl==TRUE){
		SSL_library_init();
		SSLeay_add_ssl_algorithms();
		meth=SSLv23_client_method();
		SSL_load_error_strings();
		if((ctx=SSL_CTX_new(meth))==NULL){
			printf("CHECK_NRPE: Error - could not create SSL context.\n");
			exit(STATE_CRITICAL);
		        }

		/* ADDED 01/19/2004 */
		/* use only TLSv1 protocol */
		SSL_CTX_set_options(ctx,SSL_OP_NO_SSLv2 | SSL_OP_NO_SSLv3);
                }
#endif
```

### connect(2) した fd を使って SSL_connect するコード

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

### 暗号化方式

OpenSSL のADH を使っている

```c
			SSL_CTX_set_cipher_list(ctx,"ADH");
```

ADH は **anonymous DH cipher suite** の略。証明書を事前に用意しないやつかな

```
/* https://www.openssl.org/docs/apps/ciphers.html */
ADH
anonymous DH cipher suites, note that this does not include anonymous Elliptic Curve DH (ECDH) cipher suites.
````

## Host %s is not allowed to talk to us!

nrpe に繋いできたクライアントが allowed で無い場合に弾いて syslog に出るログ。

 * nrpe は accpet(2) -> getppername(2) で ピア側の IP を出す
 * IP が allowed_hosts に含まれていない場合に上記メッセージを出して弾く様子
 * **is_an_allowed_host** で弾くべきかどうかを判定する

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
   * gethostbyname(3) がコケる場合 意図しない判定を返す可能性がある (DNS の障害, /etc/hosts の不備)

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

check_nrp の原因のよく分からないエラーとしてみるログ。nrpe-2.15/src/check_nrpe.c の実装を追うと下記の通り

 * プラグインの SSL_connect が原因で出るログ
 * **is_an_allowed_host** で弾かれるとこのログでコケる 
 * connect(2) の fd を SSL_set_fd して SSL_connect しているので、TCP/IP で ESTABLIHSED であることは保証されているはず

DEBUG をつけないと errorno 等見れない。ヒドイわー。nrpe サーバ側のログを見て判定すべきなのだろう

ちなみに `-n` を着けて SSL を無効にすると下記のログになる

```
CHECK_NRPE: Error receiving data from daemon.
```

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

一方の nrpe (デーモン) 側ではエラーを syslog で出す。SSL_accept の段階らしい

 * SSL_accept する前に accept(2) + SSL_set_fd しているので TCP で ESTABLIHSED になっている
 * nrpe のログを見ないと正確なエラーの原因が分からないことがよみとれる

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
				return;
			        }
		        }
		else{
			syslog(LOG_ERR,"Error: Could not create SSL connection structure.\n");
			return;
		        }
	        }
#endif
```

## OpenSSL ADH

include/openssl/ssl.h

```c
#define SSL_TXT_ADH		"ADH"
```

ssl/ssl_ciph.c

```
static const SSL_CIPHER cipher_aliases[]={
//…
	{0,SSL_TXT_ADH,0,     SSL_kEDH,SSL_aNULL,0,0,0,0,0,0,0},

```

```
/* key exchange algorithm */
#define SSL_kEDH		0x00000008L /* tmp DH key no DH cert */


/* server authentication */
#define SSL_aNULL 		0x00000004L /* no auth (i.e. use ADH or AECDH) */
```

```c
/* used to hold info on the particular ciphers used */
typedef struct ssl_cipher_st
	{
	int valid;
	const char *name;		/* text name */
	unsigned long id;		/* id, 4 bytes, first is version */

	/* changed in 0.9.9: these four used to be portions of a single value 'algorithms' */
	unsigned long algorithm_mkey;	/* key exchange algorithm */
	unsigned long algorithm_auth;	/* server authentication */
	unsigned long algorithm_enc;	/* symmetric encryption */
	unsigned long algorithm_mac;	/* symmetric authentication */
	unsigned long algorithm_ssl;	/* (major) protocol version */

	unsigned long algo_strength;	/* strength and export flags */
	unsigned long algorithm2;	/* Extra flags */
	int strength_bits;		/* Number of bits really used */
	int alg_bits;			/* Number of bits for algorithm */
	} SSL_CIPHER;
```

### SSL_aNULL

証明書の検証をすっ飛ばすフラグ?

ssl/s3_clnt.c 

 * algorithm_auth & SSL_aNULL なら ssl3_get_server_certificate をすっ飛ばしてる

```c
int ssl3_connect(SSL *s)
	{
//…

	for (;;)
		{
		switch(s->state)
			{
		switch(s->state)
//…
		case SSL3_ST_CR_CERT_B:
			/* Check if it is anon DH/ECDH */
			/* or PSK */
			if (!(s->s3->tmp.new_cipher->algorithm_auth & SSL_aNULL) &&
			    !(s->s3->tmp.new_cipher->algorithm_mkey & SSL_kPSK))
				{
				ret=ssl3_get_server_certificate(s);
				if (ret <= 0) goto end;
			else
				skip=1;
```

ssl3_check_cert_and_algorithm では証明書の検査を飛ばす

```c
int ssl3_check_cert_and_algorithm(SSL *s)
	{
	int i,idx;
	long alg_k,alg_a;
	EVP_PKEY *pkey=NULL;
	SESS_CERT *sc;
#ifndef OPENSSL_NO_RSA
	RSA *rsa;
#endif
#ifndef OPENSSL_NO_DH
	DH *dh;
#endif

	alg_k=s->s3->tmp.new_cipher->algorithm_mkey;
	alg_a=s->s3->tmp.new_cipher->algorithm_auth;

	/* we don't have a certificate */
	if ((alg_a & (SSL_aDH|SSL_aNULL|SSL_aKRB5)) || (alg_k & SSL_kPSK))
		return(1);
```

ssl/s3_srvr.c でも ssl3_send_server_certificate を飛ばしている

```c
		case SSL3_ST_SW_CERT_B:
			/* Check if it is anon DH or anon ECDH, */
			/* normal PSK or KRB5 */
			if (!(s->s3->tmp.new_cipher->algorithm_auth & SSL_aNULL)
				&& !(s->s3->tmp.new_cipher->algorithm_mkey & SSL_kPSK)
				&& !(s->s3->tmp.new_cipher->algorithm_auth & SSL_aKRB5))
				{
				ret=ssl3_send_server_certificate(s);
				if (ret <= 0) goto end;
				}
			else
				skip=1;
```