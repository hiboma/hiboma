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