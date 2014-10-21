# memcached の mlockall

```
      -k     Lock down all paged memory. This is a somewhat dangerous option with large caches, so consult the README and memcached homepage for configuration suggestions.
```

-k オプションでページをロックする

```c
        case 'k':
            lock_memory = true;
            break;
```

ロックの実装は mlockall(2) である

```c
    /* lock paged memory if needed */
    if (lock_memory) {
#ifdef HAVE_MLOCKALL
        int res = mlockall(MCL_CURRENT | MCL_FUTURE);
        if (res != 0) {
            fprintf(stderr, "warning: -k invalid, mlockall() failed: %s\n",
                    strerror(errno));
        }
#else
        fprintf(stderr, "warning: -k invalid, mlockall() not supported on this platform.  proceeding without.\n");
#endif
    }
```

## see also

 * http://threebrothers.org/brendan/blog/using-memcached-k-prevent-paging/
 * ulimit の値に注意