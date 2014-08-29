# proftpd + .ftpaccess

```c
(gdb) bt
#0  0x08064e9d in merge_down (s=0x8c9974c, dynamic=1) at dirtree.c:2383
#1  0x0806505b in merge_down (s=0x8c3b7c4, dynamic=1) at dirtree.c:2435
#2  0x08063595 in build_dyn_config (p=0x96329ec, _path=0xbfeeeab0 "/web/32", stp=0xbfeee8d0, recurse=1 '\001') at dirtree.c:1801
#3  0x0806385a in dir_check_full (pp=0x8c3b52c, cmd=0x8c3af24, group=0x8c3afd4 "DIRS", path=0xbfeeeab0 "/web/32", hidden=0xbfef1c24) at dirtree.c:1902
#4  0x080640a0 in dir_check (pp=0x8c3b52c, cmd=0x8c3af24, group=0x8c3afd4 "DIRS", path=0xbfeeeab0 "/web/32", hidden=0xbfef1c24) at dirtree.c:2039
#5  0x080bb5f7 in ls_perms (p=0x8c3b52c, cmd=0x8c3af24, path=0x8c448b8 "32", hidden=0xbfef1c24) at mod_ls.c:231
#6  0x080bbd9d in listfile (cmd=0x8c3af24, p=0x8c3b52c, name=0x8c448b8 "32") at mod_ls.c:449
#7  0x080bd561 in listdir (cmd=0x8c3af24, workp=0x8c3b52c, name=0x8c5075c "web") at mod_ls.c:1075
#8  0x080be9e2 in dolist (cmd=0x8c3af24, opt=0x8c3af7c "web", clearflags=1) at mod_ls.c:1752
#9  0x080bf79f in genericlist (cmd=0x8c3af24) at mod_ls.c:2135
#10 0x080c01e1 in ls_list (cmd=0x8c3af24) at mod_ls.c:2297
#11 0x0807cbf6 in pr_module_call (m=0x8113140, func=0x80c0193 <ls_list>, cmd=0x8c3af24) at modules.c:502
#12 0x08056b7c in _dispatch (cmd=0x8c3af24, cmd_type=2, validate=1, match=0x8c3af74 "LIST") at main.c:458
#13 0x08057385 in pr_cmd_dispatch_phase (cmd=0x8c3af24, phase=0, flags=3) at main.c:719
#14 0x080576ab in pr_cmd_dispatch (cmd=0x8c3af24) at main.c:792
#15 0x08057bcf in cmd_loop (server=0x8c16a04, c=0x8c5341c) at main.c:935
#16 0x08058ba6 in fork_server (fd=0, l=0x8c50f7c, nofork=1 '\001') at main.c:1457
#17 0x0805a873 in inetd_main () at main.c:2474
#18 0x0805b71d in main (argc=1, argv=0xbfef72a4, envp=0xbfef72ac) at main.c:3167
```

## build_dyn_config

`Manage .ftpaccess dynamic directory sections ` とのこと

```c
/* Manage .ftpaccess dynamic directory sections
 *
 * build_dyn_config() is called to check for and then handle .ftpaccess 
 * files.  It determines:
 *
 *   - whether an .ftpaccess file exists in a directory
 *   - whether an existing .ftpaccess section for that file exists
 *   - whether a new .ftpaccess section needs to be constructed
 *   - whether an existing .ftpaccess section needs rebuilding 
 *         as its corresponding .ftpaccess file has been modified   
 *   - whether an existing .ftpaccess section must now be removed
 *         as its corresponding .ftpaccess file has disappeared
 *
 * The routine must check for .ftpaccess files in each directory that is
 * a component of the path argument.  The input path may be for either a 
 * directory or file, and that may or may not already exist.  
 *
 * build_dyn_config() may be called with a path to:
 *
 *   - an existing directory        - start check in that dir
 *   - an existing file             - start check in containing dir
 *   - a proposed directory         - start check in containing dir
 *   - a proposed file              - start check in containing dir
 *
 * As in 1.3.3b code, the key is that for path "/a/b/c", one of either 
 * "/a/b/c" or "/a/b" is an existing directory, or we MUST give up as we
 * cannot even start scanning for .ftpaccess files without a valid starting
 * directory.
 */
void build_dyn_config(pool *p, const char *_path, struct stat *stp,
```

## ltrace でプロファイルを取った結果

```c
# sudo ltrace -c -p $( pgrep proftpd | tail -1 )
% time     seconds  usecs/call     calls      function
------ ----------- ----------- --------- --------------------
 82.82   27.418897          48    561804 __errno_location
 10.15    3.361056          42     78186 memset
  3.43    1.134936          17     66728 strcmp
  2.66    0.881332          17     51836 strlen
  0.87    0.287005          17     16379 malloc
  0.02    0.005752          20       274 memcpy
  0.01    0.003311          47        70 time
  0.01    0.003022          43        70 write
  0.00    0.001643          17        94 snprintf
  0.00    0.001428          68        21 strrchr
  0.00    0.001344          19        70 vsnprintf
  0.00    0.001342          17        76 localtime
  0.00    0.001235          17        70 strftime
  0.00    0.000882          40        22 __xstat64
  0.00    0.000823          15        52 strchr
  0.00    0.000638          15        42 strncmp
  0.00    0.000436          36        12 __lxstat64
  0.00    0.000425          35        12 read
  0.00    0.000225          37         6 close
  0.00    0.000220          36         6 open64
  0.00    0.000214          35         6 __fxstat64
  0.00    0.000088          14         6 __ctype_b_loc
------ ----------- ----------- --------- --------------------
100.00   33.106254                775842 total
```

## __errno_location のおそいとこ

```c
void pr_signals_handle(void) {
  table_handling_signal(TRUE);

  if (errno == EINTR &&
      PR_TUNABLE_EINTR_RETRY_INTERVAL > 0) {
    struct timeval tv;
    unsigned long interval_usecs = PR_TUNABLE_EINTR_RETRY_INTERVAL * 1000000;
```

key_hash の中で呼び出されているのが遅い
 
```c
/* Use Perl's hashing algorithm by default. */
static unsigned int key_hash(const void *key, size_t keysz) {
  unsigned int i = 0;
  size_t sz = !keysz ? strlen((const char *) key) : keysz;

  while (sz--) {
    const char *k = key;
    unsigned int c = *k;
    k++;

    if (!handling_signal) {
      /* Always handle signals in potentially long-running while loops. */
      pr_signals_handle();
    }

    i = (i * 33) + c;
  }

  return i; 
}
```

## memset

```
(gdb) 
#0  0x00ad84c0 in memset () from /lib/tls/libc.so.6
#1  0x0805d1b2 in pcalloc (p=0x9b517cc, sz=24) at pool.c:552
#2  0x0805eded in tab_entry_alloc (tab=0x9b517f4) at table.c:195
#3  0x0805f09d in pr_table_kadd (tab=0x9b517f4, key_data=0x9fa4a2c, key_datasz=13, value_data=0x9fa426c, value_datasz=4) at table.c:320
#4  0x0805fa6d in pr_table_add (tab=0x9b517f4, key_data=0x9fa4a2c "TransferRate", value_data=0x9fa426c, value_datasz=4) at table.c:692
#5  0x08066e4d in pr_config_set_id (name=0x9fa4a2c "TransferRate") at dirtree.c:3446
#6  0x080615cd in add_config_set (set=0x9b84824, name=0x9b85de4 "TransferRate") at dirtree.c:627
#7  0x08064f1c in merge_down (s=0x9b8242c, dynamic=0) at dirtree.c:2412
#8  0x0806552b in fixup_dirs (s=0x9b51a04, flags=16) at dirtree.c:2596
#9  0x08063598 in build_dyn_config (p=0x9dbd5d4, _path=0xbff3a2d0 "/web/24", stp=0xbff3a0f0, recurse=1 '\001') at dirtree.c:1804
#10 0x0806382c in dir_check_full (pp=0x9b7652c, cmd=0x9b75f24, group=0x9b75fd4 "DIRS", path=0xbff3a2d0 "/web/24", hidden=0xbff3d444) at dirtree.c:1902
#11 0x08064072 in dir_check (pp=0x9b7652c, cmd=0x9b75f24, group=0x9b75fd4 "DIRS", path=0xbff3a2d0 "/web/24", hidden=0xbff3d444) at dirtree.c:2039
#12 0x080bb5bf in ls_perms (p=0x9b7652c, cmd=0x9b75f24, path=0x9b7f7d8 "24", hidden=0xbff3d444) at mod_ls.c:231
#13 0x080bbd65 in listfile (cmd=0x9b75f24, p=0x9b7652c, name=0x9b7f7d8 "24") at mod_ls.c:449
#14 0x080bd529 in listdir (cmd=0x9b75f24, workp=0x9b7652c, name=0x9b8b75c "web") at mod_ls.c:1075
#15 0x080be9aa in dolist (cmd=0x9b75f24, opt=0x9b75f7c "web", clearflags=1) at mod_ls.c:1752
#16 0x080bf767 in genericlist (cmd=0x9b75f24) at mod_ls.c:2135
#17 0x080c01a9 in ls_list (cmd=0x9b75f24) at mod_ls.c:2297
#18 0x0807cbbe in pr_module_call (m=0x8113140, func=0x80c015b <ls_list>, cmd=0x9b75f24) at modules.c:502
#19 0x08056b7c in _dispatch (cmd=0x9b75f24, cmd_type=2, validate=1, match=0x9b75f74 "LIST") at main.c:458
#20 0x08057385 in pr_cmd_dispatch_phase (cmd=0x9b75f24, phase=0, flags=3) at main.c:719
#21 0x080576ab in pr_cmd_dispatch (cmd=0x9b75f24) at main.c:792
---Type <return> to continue, or q <return> to quit---
#22 0x08057bcf in cmd_loop (server=0x9b51a04, c=0x9b8e41c) at main.c:935
#23 0x08058ba6 in fork_server (fd=0, l=0x9b8bf7c, nofork=1 '\001') at main.c:1457
#24 0x0805a873 in inetd_main () at main.c:2474
#25 0x0805b71d in main (argc=1, argv=0xbff42ac4, envp=0xbff42acc) at main.c:3167
```

## set_transferrate

```c
static void merge_down(xaset_t *s, int dynamic) {
  config_rec *c, *dst, *newconf;
  int argc;
  void **argv, **sargv;

  if (!s ||
      !s->xas_list)
    return;

  for (c = (config_rec *) s->xas_list; c; c = c->next) {
    if ((c->flags & CF_MERGEDOWN) ||
        (c->flags & CF_MERG.adEDOWN_MULTI))
      for (dst = (config_rec *) s->xas_list; dst; dst = dst->next) {
        if (dst->config_type == CONF_ANON ||
           dst->config_type == CONF_DIR) {

          /* If an option of the same name/type is found in the
           * next level down, it overrides, so we don't merge.
           */
          if ((c->flags & CF_MERGEDOWN) &&
              find_config(dst->subset, c->config_type, c->name, FALSE))
            continue;

          if (dynamic) {
            /* If we are doing a dynamic merge (i.e. .ftpaccess files) then
             * we do not need to re-merge the static configs that are already
             * there.  Otherwise we are creating copies needlessly of any
             * config_rec marked with the CF_MERGEDOWN_MULTI flag, which
             * adds to the memory usage/processing time.
             *
             * If neither the src or the dst config have the CF_DYNAMIC
             * flag, it's a static config, and we can skip this merge and move
             * on.  Otherwise, we can merge it.
             */
            if (!(c->flags & CF_DYNAMIC) && !(dst->flags & CF_DYNAMIC)) {
              continue;
            }
          }

          if (!dst->subset)
            dst->subset = xaset_create(dst->pool, NULL);

          newconf = add_config_set(&dst->subset, c->name);
          newconf->config_type = c->config_type;
          newconf->flags = c->flags | (dynamic ? CF_DYNAMIC : 0);
          newconf->argc = c->argc;
          newconf->argv = pcalloc(newconf->pool, (c->argc+1) * sizeof(void *));
          argv = newconf->argv;
          sargv = c->argv;
          argc = newconf->argc;

          while (argc--) {
            *argv++ = *sargv++;
          }

          *argv++ = NULL;
        }
      }
  }
```

```
  c->flags |= CF_MERGEDOWN_MULTI;
```
