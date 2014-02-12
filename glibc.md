# glibc

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
  
