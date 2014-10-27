# Unable to allocate memory for pool.

apc_main.php

```c
    ctxt.pool = apc_pool_create(APC_MEDIUM_POOL, apc_sma_malloc, apc_sma_free, 
                                                 apc_sma_protect, apc_sma_unprotect);
    if (!ctxt.pool) {
        apc_wprint("Unable to allocate memory for pool.");
        return FAILURE;
    }
```

``c
        ctxt.pool = apc_pool_create(APC_UNPOOL, apc_php_malloc, apc_php_free,
                                                apc_sma_protect, apc_sma_unprotect);
        if (!ctxt.pool) {
            apc_wprint("Unable to allocate memory for pool.");
            return old_compile_file(h, type TSRMLS_CC);
        }
```

php_apc.php

```c
    ctxt.pool = apc_pool_create(APC_SMALL_POOL, apc_sma_malloc, apc_sma_free, apc_sma_protect, apc_sma_unprotect);
    if (!ctxt.pool) {
        apc_wprint("Unable to allocate memory for pool.");
        return 0;
    }    
```

```c
    ctxt.pool = apc_pool_create(APC_UNPOOL, apc_php_malloc, apc_php_free, NULL, NULL);
    if (!ctxt.pool) {
        apc_wprint("Unable to allocate memory for pool.");
        RETURN_FALSE;
    }    
```

#### apc_php_malloc

```c
void* apc_php_malloc(size_t n)
{
    return emalloc(n);
}
```