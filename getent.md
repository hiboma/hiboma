# getent

glibc の nss/getent.c

データベース名(groupとかhostsとかの種別) と 関数ポインタのごっつい配列

```
struct
  {
    const char *name;
    int (*func) (int number, char *key[]);
  } databases[] =
  {
#define D(name) { #name, name ## _keys },
D(ahosts)
D(ahostsv4)
D(ahostsv6)
D(aliases)
D(ethers)
D(group)
D(gshadow)
D(hosts)
D(initgroups)
D(netgroup)
D(networks)
D(passwd)
D(protocols)
D(rpc)
D(services)
D(shadow)
#undef D
    { NULL, NULL }
  };
```

```
static int
group_keys (int number, char *key[])
{
  int result = 0;
  int i;
  struct group *grp;

  if (number == 0)
    {
      setgrent ();
      while ((grp = getgrent ()) != NULL)
	print_group (grp);
      endgrent ();
      return result;
    }

  for (i = 0; i < number; ++i)
    {
      errno = 0;
      char *ep;
      gid_t arg_gid = strtoul(key[i], &ep, 10);

      if (errno != EINVAL && *key[i] != '\0' && *ep == '\0')
	/* Valid numeric gid.  */
	grp = getgrgid (arg_gid);
      else
	grp = getgrnam (key[i]);

      if (grp == NULL)
	result = 2;
      else
	print_group (grp);
    }

  return result;
}
```