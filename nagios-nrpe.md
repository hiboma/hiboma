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

### DHアルゴリズム

鍵交換 key exchange => 鍵合意 key agreemnet

 * p 素数
   * (p-1)/2 「安全な素数」
 * g 生成元
   * 2〜5 が適正らしい
 * priv_key 秘密鍵
   * p, g から整数を無作為に選択
   * priv_key から pub_key 公開鍵を生成
   * priv_key 共通鍵暗号化方式の鍵に使える

### ADH   

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

### SSL_kEDH

ssl/s3_clnt.c

```c
int ssl3_get_key_exchange(SSL *s)
//...

#ifndef OPENSSL_NO_DH
	else if (alg_k & SSL_kEDH)
		{
		if ((dh=DH_new()) == NULL)
			{
			SSLerr(SSL_F_SSL3_GET_KEY_EXCHANGE,ERR_R_DH_LIB);
			goto err;
			}
		n2s(p,i);
		param_len=i+2;
		if (param_len > n)
			{
			al=SSL_AD_DECODE_ERROR;
			SSLerr(SSL_F_SSL3_GET_KEY_EXCHANGE,SSL_R_BAD_DH_P_LENGTH);
			goto f_err;
			}
		if (!(dh->p=BN_bin2bn(p,i,NULL)))
			{
			SSLerr(SSL_F_SSL3_GET_KEY_EXCHANGE,ERR_R_BN_LIB);
			goto err;
			}
		p+=i;

		n2s(p,i);
		param_len+=i+2;
		if (param_len > n)
			{
			al=SSL_AD_DECODE_ERROR;
			SSLerr(SSL_F_SSL3_GET_KEY_EXCHANGE,SSL_R_BAD_DH_G_LENGTH);
			goto f_err;
			}
		if (!(dh->g=BN_bin2bn(p,i,NULL)))
			{
			SSLerr(SSL_F_SSL3_GET_KEY_EXCHANGE,ERR_R_BN_LIB);
			goto err;
			}
		p+=i;

		n2s(p,i);
		param_len+=i+2;
		if (param_len > n)
			{
			al=SSL_AD_DECODE_ERROR;
			SSLerr(SSL_F_SSL3_GET_KEY_EXCHANGE,SSL_R_BAD_DH_PUB_KEY_LENGTH);
			goto f_err;
			}
		if (!(dh->pub_key=BN_bin2bn(p,i,NULL)))
			{
			SSLerr(SSL_F_SSL3_GET_KEY_EXCHANGE,ERR_R_BN_LIB);
			goto err;
			}
		p+=i;
		n-=param_len;
```

```c
int ssl3_send_client_key_exchange(SSL *s)

//...

#ifndef OPENSSL_NO_DH
		else if (alg_k & (SSL_kEDH|SSL_kDHr|SSL_kDHd))
			{
			DH *dh_srvr,*dh_clnt;

			if (s->session->sess_cert == NULL) 
				{
				ssl3_send_alert(s,SSL3_AL_FATAL,SSL_AD_UNEXPECTED_MESSAGE);
				SSLerr(SSL_F_SSL3_SEND_CLIENT_KEY_EXCHANGE,SSL_R_UNEXPECTED_MESSAGE);
				goto err;
				}

			if (s->session->sess_cert->peer_dh_tmp != NULL)
				dh_srvr=s->session->sess_cert->peer_dh_tmp;
			else
				{
				/* we get them from the cert */
				ssl3_send_alert(s,SSL3_AL_FATAL,SSL_AD_HANDSHAKE_FAILURE);
				SSLerr(SSL_F_SSL3_SEND_CLIENT_KEY_EXCHANGE,SSL_R_UNABLE_TO_FIND_DH_PARAMETERS);
				goto err;
				}
			
			/* generate a new random key */
			if ((dh_clnt=DHparams_dup(dh_srvr)) == NULL)
				{
				SSLerr(SSL_F_SSL3_SEND_CLIENT_KEY_EXCHANGE,ERR_R_DH_LIB);
				goto err;
				}

            /* 鍵の生成 */
			if (!DH_generate_key(dh_clnt))
				{
				SSLerr(SSL_F_SSL3_SEND_CLIENT_KEY_EXCHANGE,ERR_R_DH_LIB);
				DH_free(dh_clnt);
				goto err;
				}

			/* use the 'p' output buffer for the DH key, but
			 * make sure to clear it out afterwards */

            /* p を buffer に載せる。ちゃんと消さないとならない */
			n=DH_compute_key(p,dh_srvr->pub_key,dh_clnt);

			if (n <= 0)
				{
				SSLerr(SSL_F_SSL3_SEND_CLIENT_KEY_EXCHANGE,ERR_R_DH_LIB);
				DH_free(dh_clnt);
				goto err;
				}

			/* generate master key from the result */
            /* master key = 共有秘密? */
			s->session->master_key_length=
				s->method->ssl3_enc->generate_master_secret(s,
					s->session->master_key,p,n);

			/* clean up */
            /* p を 0 化 */
			memset(p,0,n);

			/* send off the data */
			n=BN_num_bytes(dh_clnt->pub_key);
			s2n(n,p);
			BN_bn2bin(dh_clnt->pub_key,p);
			n+=2;

			DH_free(dh_clnt);

			/* perhaps clean things up a bit EAY EAY EAY EAY*/
			}
#endif
```

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

//...

#ifndef OPENSSL_NO_DH
    /* 十分に安全なビットを持ってるとかそんなこんな ?*/
	if ((alg_k & SSL_kEDH) &&
		!(has_bits(i,EVP_PK_DH|EVP_PKT_EXCH) || (dh != NULL)))
		{
		SSLerr(SSL_F_SSL3_CHECK_CERT_AND_ALGORITHM,SSL_R_MISSING_DH_KEY);
		goto f_err;
		}
	else if ((alg_k & SSL_kDHr) && !has_bits(i,EVP_PK_DH|EVP_PKS_RSA))
		{
		SSLerr(SSL_F_SSL3_CHECK_CERT_AND_ALGORITHM,SSL_R_MISSING_DH_RSA_CERT);
		goto f_err;
		}
```

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

//...

#ifndef OPENSSL_NO_DH
			if (alg_k & (SSL_kEDH|SSL_kDHr|SSL_kDHd))
			    {
			    if (dh == NULL
				|| DH_size(dh)*8 > SSL_C_EXPORT_PKEYLENGTH(s->s3->tmp.new_cipher))
				{
				SSLerr(SSL_F_SSL3_CHECK_CERT_AND_ALGORITHM,SSL_R_MISSING_EXPORT_TMP_DH_KEY);
				goto f_err;
				}
			}
		else
#endif
```

ssl/s3_srvr.c

```c
int ssl3_send_server_key_exchange(SSL *s)

//...

#ifndef OPENSSL_NO_DH
			if (type & SSL_kEDH)
			{
			dhp=cert->dh_tmp;
			if ((dhp == NULL) && (s->cert->dh_tmp_cb != NULL))
				dhp=s->cert->dh_tmp_cb(s,
				      SSL_C_IS_EXPORT(s->s3->tmp.new_cipher),
				      SSL_C_EXPORT_PKEYLENGTH(s->s3->tmp.new_cipher));
			if (dhp == NULL)
				{
				al=SSL_AD_HANDSHAKE_FAILURE;
				SSLerr(SSL_F_SSL3_SEND_SERVER_KEY_EXCHANGE,SSL_R_MISSING_TMP_DH_KEY);
				goto f_err;
				}

			if (s->s3->tmp.dh != NULL)
				{
				SSLerr(SSL_F_SSL3_SEND_SERVER_KEY_EXCHANGE, ERR_R_INTERNAL_ERROR);
				goto err;
				}

			if ((dh=DHparams_dup(dhp)) == NULL)
				{
				SSLerr(SSL_F_SSL3_SEND_SERVER_KEY_EXCHANGE,ERR_R_DH_LIB);
				goto err;
				}

			s->s3->tmp.dh=dh;
			if ((dhp->pub_key == NULL ||
			     dhp->priv_key == NULL ||
			     (s->options & SSL_OP_SINGLE_DH_USE)))
				{
                /* か犠牲性 */
				if(!DH_generate_key(dh))
				    {
				    SSLerr(SSL_F_SSL3_SEND_SERVER_KEY_EXCHANGE,
					   ERR_R_DH_LIB);
				    goto err;
				    }
				}
			else
				{
				dh->pub_key=BN_dup(dhp->pub_key);
				dh->priv_key=BN_dup(dhp->priv_key);
				if ((dh->pub_key == NULL) ||
					(dh->priv_key == NULL))
					{
					SSLerr(SSL_F_SSL3_SEND_SERVER_KEY_EXCHANGE,ERR_R_DH_LIB);
					goto err;
					}
				}

            /* 型は BIGNUM *r[4] */
			r[0]=dh->p;
			r[1]=dh->g;
			r[2]=dh->pub_key;
			}
		else
#endif

//...

		for (i=0; r[i] != NULL; i++)
			{
			nr[i]=BN_num_bytes(r[i]);
			n+=2+nr[i];
			}

	s->state = SSL3_ST_SW_KEY_EXCH_B;
	EVP_MD_CTX_cleanup(&md_ctx);
	return(ssl3_do_write(s,SSL3_RT_HANDSHAKE));            
```

```c
int ssl3_get_client_key_exchange(SSL *s)
//...

#ifndef OPENSSL_NO_DH
		if (alg_k & (SSL_kEDH|SSL_kDHr|SSL_kDHd))
		{
		n2s(p,i);
		if (n != i+2)
			{
			if (!(s->options & SSL_OP_SSLEAY_080_CLIENT_DH_BUG))
				{
				SSLerr(SSL_F_SSL3_GET_CLIENT_KEY_EXCHANGE,SSL_R_DH_PUBLIC_VALUE_LENGTH_IS_WRONG);
				goto err;
				}
			else
				{
				p-=2;
				i=(int)n;
				}
			}

		if (n == 0L) /* the parameters are in the cert */
			{
			al=SSL_AD_HANDSHAKE_FAILURE;
			SSLerr(SSL_F_SSL3_GET_CLIENT_KEY_EXCHANGE,SSL_R_UNABLE_TO_DECODE_DH_CERTS);
			goto f_err;
			}
		else
			{
			if (s->s3->tmp.dh == NULL)
				{
				al=SSL_AD_HANDSHAKE_FAILURE;
				SSLerr(SSL_F_SSL3_GET_CLIENT_KEY_EXCHANGE,SSL_R_MISSING_TMP_DH_KEY);
				goto f_err;
				}
			else
				dh_srvr=s->s3->tmp.dh;
			}

		pub=BN_bin2bn(p,i,NULL);
		if (pub == NULL)
			{
			SSLerr(SSL_F_SSL3_GET_CLIENT_KEY_EXCHANGE,SSL_R_BN_LIB);
			goto err;
			}

		i=DH_compute_key(p,pub,dh_srvr);

		if (i <= 0)
			{
			SSLerr(SSL_F_SSL3_GET_CLIENT_KEY_EXCHANGE,ERR_R_DH_LIB);
			BN_clear_free(pub);
			goto err;
			}

		DH_free(s->s3->tmp.dh);
		s->s3->tmp.dh=NULL;

		BN_clear_free(pub);
		pub=NULL;
		s->session->master_key_length=
			s->method->ssl3_enc->generate_master_secret(s,
				s->session->master_key,p,i);
		OPENSSL_cleanse(p,i);
		}
	else
#endif
```

### SSL_aNULL

証明書の検証(認証?)をすっ飛ばすフラグ?

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