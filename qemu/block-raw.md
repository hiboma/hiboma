# raw 形式

raw 形式のディスクがどのように実装されているのか、コードをななめ読みしていきます (複雑なところはすっとばします)

## ファイル

block/raw-posix.c というのがそれぽいです

## BlockDriver

ディスクの形式ごとに BlockDriver てな構造体が定義されて、 bdrv_register で使えるようになるようです。 BlockDriver が抽象化のインタフェースとなり raw や qcow2 などの実装を隠蔽するのですね (カーネルの VFS なんかと同じやり方 )

```c
static BlockDriver bdrv_raw = {
    .format_name = "raw",
    .instance_size = sizeof(BDRVRawState),
    .bdrv_probe = NULL, /* no probe for protocols */
    .bdrv_open = raw_open,
    .bdrv_read = raw_read,
    .bdrv_write = raw_write,
    .bdrv_close = raw_close,
    .bdrv_create = raw_create,
    .bdrv_flush = raw_flush,

    .bdrv_aio_readv = raw_aio_readv,
    .bdrv_aio_writev = raw_aio_writev,
    .bdrv_aio_flush = raw_aio_flush,

    .bdrv_truncate = raw_truncate,
    .bdrv_getlength = raw_getlength,

    .create_options = raw_create_options,
};
```

BlockDriver は下記で登録するようです。呼び出しのタイミングなどは謎

```c
static void bdrv_raw_init(void)
{
    /*
     * Register all the drivers.  Note that order is important, the driver
     * registered last will get probed first.
     */
    bdrv_register(&bdrv_raw);
    bdrv_register(&bdrv_host_device);
#ifdef __linux__
    bdrv_register(&bdrv_host_floppy);
    bdrv_register(&bdrv_host_cdrom);
#endif
#if defined(__FreeBSD__) || defined(__FreeBSD_kernel__)
    bdrv_register(&bdrv_host_cdrom);
#endif
}
```

## block/raw-posix.c raw_open

ディスク?ブロックデバイスの open ? をするようです。 raw_open_common に続きます

```
static int raw_open(BlockDriverState *bs, const char *filename, int flags)
{
    BDRVRawState *s = bs->opaque;
    int open_flags = 0;

    s->type = FTYPE_FILE;
    if (flags & BDRV_O_CREAT)
        open_flags = O_CREAT | O_TRUNC;

    return raw_open_common(bs, filename, flags, open_flags);
}
```

#### raw_open_common

 * ファイルの mode や flags を設定しています
 * 最終的に POSIX C なシステムコールで open(2) する様子
    * BlockDriverState から POSIX C に変換するアダプタ層と見ればよいか?

qemu_open に続きます    

```c
static int raw_open_common(BlockDriverState *bs, const char *filename,
                           int bdrv_flags, int open_flags)
{
    BDRVRawState *s = bs->opaque;
    int fd, ret;

    s->lseek_err_cnt = 0;

    s->open_flags = open_flags | O_BINARY;
    s->open_flags &= ~O_ACCMODE;
    if ((bdrv_flags & BDRV_O_ACCESS) == BDRV_O_RDWR) {
        s->open_flags |= O_RDWR;
    } else {
        s->open_flags |= O_RDONLY;
        bs->read_only = 1;
    }

    /* Use O_DSYNC for write-through caching, no flags for write-back caching,
     * and O_DIRECT for no caching. */
    if ((bdrv_flags & BDRV_O_NOCACHE))
        s->open_flags |= O_DIRECT;
    else if (!(bdrv_flags & BDRV_O_CACHE_WB))
        s->open_flags |= O_DSYNC;

    s->fd = -1;
    fd = qemu_open(filename, s->open_flags, 0644);
    if (fd < 0) {
        ret = -errno;
        if (ret == -EROFS)
            ret = -EACCES;
        return ret;
    }
    s->fd = fd;
    s->aligned_buf = NULL;

    if ((bdrv_flags & BDRV_O_NOCACHE)) {
        s->aligned_buf = qemu_blockalign(bs, ALIGNED_BUFFER_SIZE);
        if (s->aligned_buf == NULL) {
            goto out_close;
        }
    }

#ifdef CONFIG_LINUX_AIO
    if ((bdrv_flags & (BDRV_O_NOCACHE|BDRV_O_NATIVE_AIO)) ==
                      (BDRV_O_NOCACHE|BDRV_O_NATIVE_AIO)) {

        /* We're falling back to POSIX AIO in some cases */
        paio_init();

        s->aio_ctx = laio_init();
        if (!s->aio_ctx) {
            goto out_free_buf;
        }
        s->use_aio = 1;
    } else
#endif
    {
        if (paio_init() < 0) {
            goto out_free_buf;
        }
#ifdef CONFIG_LINUX_AIO
        s->use_aio = 0;
#endif
    }

    return 0;

out_free_buf:
    qemu_vfree(s->aligned_buf);
out_close:
    close(fd);
    return -errno;
}
```

#### qemu_open

 * open(2) をラップしただけの実装ですね。なるほど
 * QEMU のプロセスから見るとただのファイルとして open(2) されているのが分かる

```c
/*
 * Opens a file with FD_CLOEXEC set
 */
int qemu_open(const char *name, int flags, ...)
{
    int ret;
    int mode = 0;

    if (flags & O_CREAT) {
        va_list ap;

        va_start(ap, flags);
        mode = va_arg(ap, int);
        va_end(ap);
    }

#ifdef O_CLOEXEC
    ret = open(name, flags | O_CLOEXEC, mode);
#else
    ret = open(name, flags, mode);
    if (ret >= 0) {
        qemu_set_cloexec(ret);
    }
#endif

    return ret;
}
```

## raw_write

以下の様なパラメータを扱うようです

 * BlockDriverState
 * セクタの番号 (セクタのオフセット)
 * セクタの数
 * 書き込みするデータのバッファ

これらをどう扱うが raw 形式や、qcow2 形式で異なってくるのでしょう。 raw だと単純な実装で扱ってるのだろうと何となく推測できます。 raw_pwrite に続きます

```
static int raw_write(BlockDriverState *bs, int64_t sector_num,
                     const uint8_t *buf, int nb_sectors)
{
    int ret;
    ret = raw_pwrite(bs, sector_num * 512, buf, nb_sectors * 512);
    if (ret == (nb_sectors * 512))
        ret = 0;
    return ret;
}
```

#### raw_pwrite

 * ブロックサイズでアラインする処理をして raw_pwrite_aligned に続くようです

```c
/*
 * offset and count are in bytes and possibly not aligned. For files opened
 * with O_DIRECT, necessary alignments are ensured before calling
 * raw_pwrite_aligned to do the actual write.
 */
static int raw_pwrite(BlockDriverState *bs, int64_t offset,
                      const uint8_t *buf, int count)
{
    BDRVRawState *s = bs->opaque;
    int size, ret, shift, sum;

    sum = 0;

    if (s->aligned_buf != NULL) {

        if (offset & 0x1ff) {
            /* align offset on a 512 bytes boundary */
            shift = offset & 0x1ff;
            ret = raw_pread_aligned(bs, offset - shift, s->aligned_buf, 512);
            if (ret < 0)
                return ret;

            size = 512 - shift;
            if (size > count)
                size = count;
            memcpy(s->aligned_buf + shift, buf, size);

            ret = raw_pwrite_aligned(bs, offset - shift, s->aligned_buf, 512);
            if (ret < 0)
                return ret;

            buf += size;
            offset += size;
            count -= size;
            sum += size;

            if (count == 0)
                return sum;
        }
        if (count & 0x1ff || (uintptr_t) buf & 0x1ff) {

            while ((size = (count & ~0x1ff)) != 0) {

                if (size > ALIGNED_BUFFER_SIZE)
                    size = ALIGNED_BUFFER_SIZE;

                memcpy(s->aligned_buf, buf, size);

                ret = raw_pwrite_aligned(bs, offset, s->aligned_buf, size);
                if (ret < 0)
                    return ret;

                buf += ret;
                offset += ret;
                count -= ret;
                sum += ret;
            }
            /* here, count < 512 because (count & ~0x1ff) == 0 */
            if (count) {
                ret = raw_pread_aligned(bs, offset, s->aligned_buf, 512);
                if (ret < 0)
                    return ret;
                 memcpy(s->aligned_buf, buf, count);

                 ret = raw_pwrite_aligned(bs, offset, s->aligned_buf, 512);
                 if (ret < 0)
                     return ret;
                 if (count < ret)
                     ret = count;

                 sum += ret;
            }
            return sum;
        }
    }
    return raw_pwrite_aligned(bs, offset, buf, count) + sum;
}
```

#### raw_pwrite_aligned

細かいところをすっ飛ばして読むと

 * lseek でオフセットまで進む
 * write(2) を呼んでデータを書き込む

で、非常にシンプルな実装です。 

```c
/*
 * offset and count are in bytes, but must be multiples of 512 for files
 * opened with O_DIRECT. buf must be aligned to 512 bytes then.
 *
 * This function may be called without alignment if the caller ensures
 * that O_DIRECT is not in effect.
 */
static int raw_pwrite_aligned(BlockDriverState *bs, int64_t offset,
                      const uint8_t *buf, int count)
{
    BDRVRawState *s = bs->opaque;
    int ret;

    ret = fd_open(bs);
    if (ret < 0)
        return -errno;

    if (offset >= 0 && lseek(s->fd, offset, SEEK_SET) == (off_t)-1) {
        ++(s->lseek_err_cnt);
        if(s->lseek_err_cnt) {
            DEBUG_BLOCK_PRINT("raw_pwrite(%d:%s, %" PRId64 ", %p, %d) [%"
                              PRId64 "] lseek failed : %d = %s\n",
                              s->fd, bs->filename, offset, buf, count,
                              bs->total_sectors, errno, strerror(errno));
        }
        return -EIO;
    }
    s->lseek_err_cnt = 0;

    ret = write(s->fd, buf, count);
    if (ret == count)
        goto label__raw_write__success;

    DEBUG_BLOCK_PRINT("raw_pwrite(%d:%s, %" PRId64 ", %p, %d) [%" PRId64
                      "] write failed %d : %d = %s\n",
                      s->fd, bs->filename, offset, buf, count,
                      bs->total_sectors, ret, errno, strerror(errno));

label__raw_write__success:

    return  (ret < 0) ? -errno : ret;
}
```