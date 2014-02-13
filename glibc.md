# glibc

## ビルド方法とテスト方法

```
curl -L -O http://vault.centos.org/6.5/os/Source/SPackages/glibc-2.12-1.132.el6.src.rp
sudo yum-builddep glibc-2.12-1.132.el6.src.rpm

# RPM展開してもいいけど。好きなバージョンをビルド
curl -L -O http://ftp.gnu.org/gnu/glibc/glibc-2.1.2.tar.gz
tar xfz glibc-2.12.2.tar.gz
mkdir build-glibc-2.12.2

# ソースと同じディレクトリで configure が通らない
 ../glibc-2.12.2/configure --prefix=$HOME/app/glibc-2.12.2
 make
 make install
```

LD_LIBRARY_PATH, LD_PRELOAD でビルドした libc を読み込ませる

```
[vagrant@vagrant-centos65 build-glibc-2.1.2]$ LD_LIBRARY_PATH=/home/vagarnt/app/glibc-2.12.2/bin/ LD_PRELOAD=/home/vagrant/app/glibc-2.12.2/lib/libc.so.6 perl -e 'system("cat /proc/self/maps")'
00400000-0040b000 r-xp 00000000 08:01 4644                               /bin/cat
0060a000-0060b000 rw-p 0000a000 08:01 4644                               /bin/cat
0060b000-0060c000 rw-p 00000000 00:00 0 
01c5e000-01c7f000 rw-p 00000000 00:00 0                                  [heap]
7fb6c5b1e000-7fb6c5c7d000 r-xp 00000000 08:01 33843                      /home/vagrant/app/glibc-2.12.2/lib/libc-2.12.2.so
7fb6c5c7d000-7fb6c5e7d000 ---p 0015f000 08:01 33843                      /home/vagrant/app/glibc-2.12.2/lib/libc-2.12.2.so
7fb6c5e7d000-7fb6c5e81000 r--p 0015f000 08:01 33843                      /home/vagrant/app/glibc-2.12.2/lib/libc-2.12.2.so
7fb6c5e81000-7fb6c5e82000 rw-p 00163000 08:01 33843                      /home/vagrant/app/glibc-2.12.2/lib/libc-2.12.2.so
7fb6c5e82000-7fb6c5e87000 rw-p 00000000 00:00 0 
7fb6c5e87000-7fb6c5ea7000 r-xp 00000000 08:01 3051                       /lib64/ld-2.12.so
7fb6c60a2000-7fb6c60a6000 rw-p 00000000 00:00 0 
7fb6c60a6000-7fb6c60a7000 r--p 0001f000 08:01 3051                       /lib64/ld-2.12.so
7fb6c60a7000-7fb6c60a8000 rw-p 00020000 08:01 3051                       /lib64/ld-2.12.so
7fb6c60a8000-7fb6c60a9000 rw-p 00000000 00:00 0 
7fffa468b000-7fffa46a0000 rw-p 00000000 00:00 0                          [stack]
7fffa47ff000-7fffa4800000 r-xp 00000000 00:00 0                          [vdso]
ffffffffff600000-ffffffffff601000 r-xp 00000000 00:00 0                  [vsyscall]
```

GDB を起動しようとするも LD_LIBRARY_PATH 以下に共有ライブラリが無いので open(2) で ENOENT

```
$ LD_LIBRARY_PATH=/home/vagarnt/app/glibc-2.12.2 LD_PRELOAD=/home/vagrant/app/glibc-2.12.2/lib/libc.so.6 gdb --args nscd/nscd -d
/home/vagrant/build-glibc-2.1.2/nscd/nscd: error while loading shared libraries: libselinux.so.1: cannot open shared object file: No such file or directory
```

cp 面倒だ。どうやって共有ライブラリを集めたら楽だろうか? とりあえず単純に cp って、make install で libc らへんを上書き

```
sudo cp /usr/lib64/mysql/*.so* /home/vagrant/app/glibc-2.12.2/lib/
sudo cp /usr/lib64/*.so*       /home/vagrant/app/glibc-2.12.2/lib/
sudo cp /lib64/*.so*           /home/vagrant/app/glibc-2.12.2/lib/
make instlal
```

足らないライブラリは /lib64 や /usr/lib64 を open するみょうに LD_LIBRARY_PATH を複数指定しておけばよいか

```
sudo LD_LIBRARY_PATH="/home/vagarnt/app/glibc-2.12.2/lib:/lib64:/usr/lib64:/usr/lib64/mysql" LD_PRELOAD=/home/vagrant/app/glibc-2.12.2/lib/libc.so.6 strace -eopen nscd/nscd -d
```

## nscd + getgrouplist

getgrouplist(3) で group を問い合わせると、nscd は addinitgroups で groupのキャッシュを作ってる

```c
void
addinitgroups (struct database_dyn *db, int fd, request_header *req, void *key,
	       uid_t uid)
{
  addinitgroupsX (db, fd, req, key, uid, NULL, NULL);
}
```

__nss_lookup_function (nip, "initgroups_dyn") で libnss_*** の実装を呼び出し

```c
static void
addinitgroupsX (struct database_dyn *db, int fd, request_header *req,
		void *key, uid_t uid, struct hashentry *const he,
		struct datahead *dh)
{
  /* Search for the entry matching the key.  Please note that we don't
     look again in the table whether the dataset is now available.  We
     simply insert it.  It does not matter if it is in there twice.  The
     pruning function only will look at the timestamp.  */


  /* We allocate all data in one memory block: the iov vector,
     the response header and the dataset itself.  */
  struct dataset
  {
    struct datahead head;
    initgr_response_header resp;
    char strdata[0];
  } *dataset = NULL;

  if (__builtin_expect (debug_level > 0, 0))
    {
      if (he == NULL)
	dbg_log (_("Haven't found \"%s\" in group cache!"), (char *) key);
      else
	dbg_log (_("Reloading \"%s\" in group cache!"), (char *) key);
    }

  static service_user *group_database;
  service_user *nip = NULL;
  int no_more;

  if (group_database != NULL)
    {
      nip = group_database;
      no_more = 0;
    }
  else
    no_more = __nss_database_lookup ("group", NULL,
				     "compat [NOTFOUND=return] files", &nip);

 /* We always use sysconf even if NGROUPS_MAX is defined.  That way, the
     limit can be raised in the kernel configuration without having to
     recompile libc.  */
  long int limit = __sysconf (_SC_NGROUPS_MAX);

  long int size;
  if (limit > 0)
    /* We limit the size of the intially allocated array.  */
    size = MIN (limit, 64);
  else
    /* No fixed limit on groups.  Pick a starting buffer size.  */
    size = 16;

  long int start = 0;
  bool all_tryagain = true;
  bool any_success = false;

  /* This is temporary memory, we need not (and must not) call
     mempool_alloc.  */
  // XXX This really should use alloca.  need to change the backends.
  gid_t *groups = (gid_t *) malloc (size * sizeof (gid_t));
  if (__builtin_expect (groups == NULL, 0))
    /* No more memory.  */
    goto out;

  /* Nothing added yet.  */
  while (! no_more)
    {
      long int prev_start = start;
      enum nss_status status;
      initgroups_dyn_function fct;
      fct = __nss_lookup_function (nip, "initgroups_dyn");

      if (fct == NULL)
	{
	  status = compat_call (nip, key, -1, &start, &size, &groups,
				limit, &errno);

	  if (nss_next_action (nip, NSS_STATUS_UNAVAIL) != NSS_ACTION_CONTINUE)
	    break;
	}
      else
	status = DL_CALL_FCT (fct, (key, -1, &start, &size, &groups,
				    limit, &errno));

      /* Remove duplicates.  */
      long int cnt = prev_start;
      while (cnt < start)
	{
	  long int inner;
	  for (inner = 0; inner < prev_start; ++inner)
	    if (groups[inner] == groups[cnt])
	      break;

	  if (inner < prev_start)
	    groups[cnt] = groups[--start];
	  else
	    ++cnt;
	}

      if (status != NSS_STATUS_TRYAGAIN)
	all_tryagain = false;

      /* This is really only for debugging.  */
      if (NSS_STATUS_TRYAGAIN > status || status > NSS_STATUS_RETURN)
	__libc_fatal ("illegal status in internal_getgrouplist");

      any_success |= status == NSS_STATUS_SUCCESS;

      if (status != NSS_STATUS_SUCCESS
	  && nss_next_action (nip, status) == NSS_ACTION_RETURN)
	 break;

      if (nip->next == NULL)
	no_more = -1;
      else
	nip = nip->next;
    }

  ssize_t total;
  ssize_t written;
 out:
  if (!any_success)
    {
      /* Nothing found.  Create a negative result record.  */
      written = total = sizeof (notfound);

      if (he != NULL && all_tryagain)
	{
	  /* If we have an old record available but cannot find one now
	     because the service is not available we keep the old record
	     and make sure it does not get removed.  */
	  if (reload_count != UINT_MAX && dh->nreloads == reload_count)
	    /* Do not reset the value if we never not reload the record.  */
	    dh->nreloads = reload_count - 1;
	}
      else
	{
	  /* We have no data.  This means we send the standard reply for this
	     case.  */
	  if (fd != -1)
	    written = TEMP_FAILURE_RETRY (send (fd, &notfound, total,
						MSG_NOSIGNAL));

	  dataset = mempool_alloc (db, sizeof (struct dataset) + req->key_len,
				   1);
	  /* If we cannot permanently store the result, so be it.  */
	  if (dataset != NULL)
	    {
	      dataset->head.allocsize = sizeof (struct dataset) + req->key_len;
	      dataset->head.recsize = total;
	      dataset->head.notfound = true;
	      dataset->head.nreloads = 0;
	      dataset->head.usable = true;

	      /* Compute the timeout time.  */
	      dataset->head.timeout = time (NULL) + db->negtimeout;

	      /* This is the reply.  */
	      memcpy (&dataset->resp, &notfound, total);

	      /* Copy the key data.  */
	      char *key_copy = memcpy (dataset->strdata, key, req->key_len);

	      /* If necessary, we also propagate the data to disk.  */
	      if (db->persistent)
		{
		  // XXX async OK?
		  uintptr_t pval = (uintptr_t) dataset & ~pagesize_m1;
		  msync ((void *) pval,
			 ((uintptr_t) dataset & pagesize_m1)
			 + sizeof (struct dataset) + req->key_len, MS_ASYNC);
		}

	      (void) cache_add (req->type, key_copy, req->key_len,
				&dataset->head, true, db, uid, he == NULL);

	      pthread_rwlock_unlock (&db->lock);

	      /* Mark the old entry as obsolete.  */
	      if (dh != NULL)
		dh->usable = false;
	    }
	}
    }
  else
    {

      written = total = (offsetof (struct dataset, strdata)
			 + start * sizeof (int32_t));

      /* If we refill the cache, first assume the reconrd did not
	 change.  Allocate memory on the cache since it is likely
	 discarded anyway.  If it turns out to be necessary to have a
	 new record we can still allocate real memory.  */
      bool alloca_used = false;
      dataset = NULL;

      if (he == NULL)
	dataset = (struct dataset *) mempool_alloc (db, total + req->key_len,
						    1);

      if (dataset == NULL)
	{
	  /* We cannot permanently add the result in the moment.  But
	     we can provide the result as is.  Store the data in some
	     temporary memory.  */
	  dataset = (struct dataset *) alloca (total + req->key_len);

	  /* We cannot add this record to the permanent database.  */
	  alloca_used = true;
	}

      dataset->head.allocsize = total + req->key_len;
      dataset->head.recsize = total - offsetof (struct dataset, resp);
      dataset->head.notfound = false;
      dataset->head.nreloads = he == NULL ? 0 : (dh->nreloads + 1);
      dataset->head.usable = true;

      /* Compute the timeout time.  */
      dataset->head.timeout = time (NULL) + db->postimeout;

      dataset->resp.version = NSCD_VERSION;
      dataset->resp.found = 1;
      dataset->resp.ngrps = start;

      char *cp = dataset->strdata;

      /* Copy the GID values.  If the size of the types match this is
	 very simple.  */
      if (sizeof (gid_t) == sizeof (int32_t))
	cp = mempcpy (cp, groups, start * sizeof (gid_t));
      else
	{
	  gid_t *gcp = (gid_t *) cp;

	  for (int i = 0; i < start; ++i)
	    *gcp++ = groups[i];

	  cp = (char *) gcp;
	}

      /* Finally the user name.  */
      memcpy (cp, key, req->key_len);

      assert (cp == dataset->strdata + total - offsetof (struct dataset,
							 strdata));

      /* Now we can determine whether on refill we have to create a new
	 record or not.  */
      if (he != NULL)
	{
	  assert (fd == -1);

	  if (total + req->key_len == dh->allocsize
	      && total - offsetof (struct dataset, resp) == dh->recsize
	      && memcmp (&dataset->resp, dh->data,
			 dh->allocsize - offsetof (struct dataset, resp)) == 0)
	    {
	      /* The data has not changed.  We will just bump the
		 timeout value.  Note that the new record has been
		 allocated on the stack and need not be freed.  */
	      dh->timeout = dataset->head.timeout;
	      ++dh->nreloads;
	    }
	  else
	    {
	      /* We have to create a new record.  Just allocate
		 appropriate memory and copy it.  */
	      struct dataset *newp
		= (struct dataset *) mempool_alloc (db, total + req->key_len,
						    1);
	      if (newp != NULL)
		{
		  /* Adjust pointer into the memory block.  */
		  cp = (char *) newp + (cp - (char *) dataset);

		  dataset = memcpy (newp, dataset, total + req->key_len);
		  alloca_used = false;
		}

	      /* Mark the old record as obsolete.  */
	      dh->usable = false;
	    }
	}
      else
	{
	  /* We write the dataset before inserting it to the database
	     since while inserting this thread might block and so would
	     unnecessarily let the receiver wait.  */
	  assert (fd != -1);

#ifdef HAVE_SENDFILE
	  if (__builtin_expect (db->mmap_used, 1) && !alloca_used)
	    {
	      assert (db->wr_fd != -1);
	      assert ((char *) &dataset->resp > (char *) db->data);
	      assert ((char *) dataset - (char *) db->head
		      + total
		      <= (sizeof (struct database_pers_head)
			  + db->head->module * sizeof (ref_t)
			  + db->head->data_size));
	      written = sendfileall (fd, db->wr_fd,
				     (char *) &dataset->resp
				     - (char *) db->head, dataset->head.recsize);
# ifndef __ASSUME_SENDFILE
	      if (written == -1 && errno == ENOSYS)
		goto use_write;
# endif
	    }
	  else
# ifndef __ASSUME_SENDFILE
	  use_write:
# endif
#endif
	    written = writeall (fd, &dataset->resp, dataset->head.recsize);
	}


      /* Add the record to the database.  But only if it has not been
	 stored on the stack.  */
      if (! alloca_used)
	{
	  /* If necessary, we also propagate the data to disk.  */
	  if (db->persistent)
	    {
	      // XXX async OK?
	      uintptr_t pval = (uintptr_t) dataset & ~pagesize_m1;
	      msync ((void *) pval,
		     ((uintptr_t) dataset & pagesize_m1) + total +
		     req->key_len, MS_ASYNC);
	    }

	  (void) cache_add (INITGROUPS, cp, req->key_len, &dataset->head, true,
			    db, uid, he == NULL);

	  pthread_rwlock_unlock (&db->lock);
	}
    }

  free (groups);

  if (__builtin_expect (written != total, 0) && debug_level > 0)
    {
      char buf[256];
      dbg_log (_("short write in %s: %s"), __FUNCTION__,
	       strerror_r (errno, buf, sizeof (buf)));
    }
}
```

## glibc + nss

getgrouplist(3) から libnss_* を呼び出す部分までを追う

```
/* Store at most *NGROUPS members of the group set for USER into
   *GROUPS.  Also include GROUP.  The actual number of groups found is
   returned in *NGROUPS.  Return -1 if the if *NGROUPS is too small.  */
int
getgrouplist (const char *user, gid_t group, gid_t *groups, int *ngroups)
```

 * glibc-2.12.1/grp/compat-initgroups.c

```c

static enum nss_status
compat_call (service_user *nip, const char *user, gid_t group, long int *start,
	     long int *size, gid_t **groupsp, long int limit, int *errnop)

  // ...         
         
  getgrent_fct = __nss_lookup_function (nip, "getgrent_r");
  if (getgrent_fct == NULL)
    return NSS_STATUS_UNAVAIL;

  setgrent_fct = __nss_lookup_function (nip, "setgrent");
  if (setgrent_fct)
    {
      status = DL_CALL_FCT (setgrent_fct, ());
      if (status != NSS_STATUS_SUCCESS)
	return status;
    }

  endgrent_fct = __nss_lookup_function (nip, "endgrent");
```

 * glibc-2.12.1/nss/nsswitch.c

```c
void *
__nss_lookup_function (service_user *ni, const char *fct_name)
{
  void **found, *result;

  //...

	      /* Construct shared object name.  */
	      __stpcpy (__stpcpy (__stpcpy (__stpcpy (shlib_name,
						      "libnss_"),
					    ni->library->name),
				  ".so"),
			__nss_shlib_revision);

	      ni->library->lib_handle = __libc_dlopen (shlib_name);
```

 * dlopen(3) が近い!

```c
#define __libc_dlopen(name) \
  __libc_dlopen_mode (name, RTLD_LAZY | __RTLD_DLOPEN)
```  

```c
void *
__libc_dlopen_mode (const char *name, int mode)
{
  struct do_dlopen_args args;
  args.name = name;
  args.mode = mode;

#ifdef SHARED
  if (__builtin_expect (_dl_open_hook != NULL, 0))
    return _dl_open_hook->dlopen_mode (name, mode);
  return (dlerror_run (do_dlopen, &args) ? NULL : (void *) args.map);
#else
  if (dlerror_run (do_dlopen, &args))
    return NULL;

  __libc_register_dl_open_hook (args.map);
  __libc_register_dlfcn_hook (args.map);
  return (void *) args.map;
#endif
}
libc_hidden_def (__libc_dlopen_mode)
```  
  
