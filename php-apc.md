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

#### apc_sma_malloc

```c
/* {{{ apc_sma_malloc */
void* apc_sma_malloc(size_t n)
{
    size_t allocated;
    void *p = apc_sma_malloc_ex(n, MINBLOCKSIZE, &allocated);

    return p;
}
/* }}} */
```

```c
/* {{{ apc_sma_malloc_ex */
void* apc_sma_malloc_ex(size_t n, size_t fragment, size_t* allocated)
{
    size_t off;
    uint i;

    TSRMLS_FETCH();
    assert(sma_initialized);
    LOCK(SMA_LCK(sma_lastseg));

    off = sma_allocate(SMA_HDR(sma_lastseg), n, fragment, allocated);

    if(off == -1 && APCG(current_cache)) { 
        /* retry failed allocation after we expunge */
        UNLOCK(SMA_LCK(sma_lastseg));
        APCG(current_cache)->expunge_cb(APCG(current_cache), n);
        LOCK(SMA_LCK(sma_lastseg));
        off = sma_allocate(SMA_HDR(sma_lastseg), n, fragment, allocated);
    }

    if (off != -1) {
        void* p = (void *)(SMA_ADDR(sma_lastseg) + off);
        UNLOCK(SMA_LCK(sma_lastseg));
#ifdef VALGRIND_MALLOCLIKE_BLOCK
        VALGRIND_MALLOCLIKE_BLOCK(p, n, 0, 0);
#endif
        return p;
    }
    
    UNLOCK(SMA_LCK(sma_lastseg));

    for (i = 0; i < sma_numseg; i++) {
        if (i == sma_lastseg) {
            continue;
        }
        LOCK(SMA_LCK(i));
        off = sma_allocate(SMA_HDR(i), n, fragment, allocated);
        if(off == -1 && APCG(current_cache)) { 
            /* retry failed allocation after we expunge */
            UNLOCK(SMA_LCK(i));
            APCG(current_cache)->expunge_cb(APCG(current_cache), n);
            LOCK(SMA_LCK(i));
            off = sma_allocate(SMA_HDR(i), n, fragment, allocated);
        }
        if (off != -1) {
            void* p = (void *)(SMA_ADDR(i) + off);
            UNLOCK(SMA_LCK(i));
            sma_lastseg = i;
#ifdef VALGRIND_MALLOCLIKE_BLOCK
            VALGRIND_MALLOCLIKE_BLOCK(p, n, 0, 0);
#endif
            return p;
        }
        UNLOCK(SMA_LCK(i));
    }

    return NULL;
}
/* }}} */
```

sma_allocate

```c
/* {{{ sma_allocate: tries to allocate at least size bytes in a segment */
static size_t sma_allocate(sma_header_t* header, size_t size, size_t fragment, size_t *allocated)
{
    void* shmaddr;          /* header of shared memory segment */
    block_t* prv;           /* block prior to working block */
    block_t* cur;           /* working block in list */
    block_t* prvnextfit;    /* block before next fit */
    size_t realsize;        /* actual size of block needed, including header */
    const size_t block_size = ALIGNWORD(sizeof(struct block_t));

    realsize = ALIGNWORD(size + block_size);

    /*
     * First, insure that the segment contains at least realsize free bytes,
     * even if they are not contiguous.
     */
    shmaddr = header;

    if (header->avail < realsize) {
        return -1;
    }

    prvnextfit = 0;     /* initially null (no fit) */
    prv = BLOCKAT(ALIGNWORD(sizeof(sma_header_t)));
    CHECK_CANARY(prv);

    while (prv->fnext != 0) {
        cur = BLOCKAT(prv->fnext);
#ifdef __APC_SMA_DEBUG__
        CHECK_CANARY(cur);
#endif
        /* If it can fit realsize bytes in cur block, stop searching */
        if (cur->size >= realsize) {
            prvnextfit = prv;
            break;
        }
        prv = cur;
    }

    if (prvnextfit == 0) {
        return -1;
    }

    prv = prvnextfit;
    cur = BLOCKAT(prv->fnext);

    CHECK_CANARY(prv);
    CHECK_CANARY(cur);

    if (cur->size == realsize || (cur->size > realsize && cur->size < (realsize + (MINBLOCKSIZE + fragment)))) {
        /* cur is big enough for realsize, but too small to split - unlink it */
        *(allocated) = cur->size - block_size;
        prv->fnext = cur->fnext;
        BLOCKAT(cur->fnext)->fprev = OFFSET(prv);
        NEXT_SBLOCK(cur)->prev_size = 0;  /* block is alloc'd */
    } else {
        /* nextfit is too big; split it into two smaller blocks */
        block_t* nxt;      /* the new block (chopped part of cur) */
        size_t oldsize;    /* size of cur before split */

        oldsize = cur->size;
        cur->size = realsize;
        *(allocated) = cur->size - block_size;
        nxt = NEXT_SBLOCK(cur);
        nxt->prev_size = 0;                       /* block is alloc'd */
        nxt->size = oldsize - realsize;           /* and fix the size */
        NEXT_SBLOCK(nxt)->prev_size = nxt->size;  /* adjust size */
        SET_CANARY(nxt);

        /* replace cur with next in free list */
        nxt->fnext = cur->fnext;
        nxt->fprev = cur->fprev;
        BLOCKAT(nxt->fnext)->fprev = OFFSET(nxt);
        BLOCKAT(nxt->fprev)->fnext = OFFSET(nxt);
#ifdef __APC_SMA_DEBUG__
        nxt->id = -1;
#endif
    }

    cur->fnext = 0;

    /* update the block header */
    header->avail -= cur->size;
#if ALLOC_DISTRIBUTION
    header->adist[(int)(log(size)/log(2))]++;
#endif

    SET_CANARY(cur);
#ifdef __APC_SMA_DEBUG__
    cur->id = ++block_id;
    fprintf(stderr, "allocate(realsize=%d,size=%d,id=%d)\n", (int)(size), (int)(cur->size), cur->id);
#endif

    return OFFSET(cur) + block_size;
}
/* }}} */
```