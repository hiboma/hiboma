# pam_mount

## pam_mount の問題

 * mountポイントは /etc/mtab に書き込まれている
 * symlink は解決され実体パスに書き変わって /etc/mtab に書き込まれている
 * **already_mounted** は /etc/mtab の実体パスと symlink が未解決なパスを比較するので不一致になる

## mount の重複を防ぐコードの実装を追う

 * do_mount で mount をごにょる
 * pmt_already_mounted で既にマウント済みかどうかを見て、重複を防ぐ

```c
/**
 * do_mount -
 * @config:	current config
 * @vpt:	volume descriptor
 * @vinfo:
 * @password:	login password (may be %NULL)
 *
 * Returns zero on error, positive non-zero for success.
 */
int do_mount(const struct config *config, struct vol *vpt,
    struct HXformat_map *vinfo, const char *password)
{
	const struct HXdeque_node *n;
	struct HXdeque *argv;
	struct HXproc proc;
	const char *mount_user;
	hxmc_t *ll_password = NULL;
	int ret;

	assert(vinfo != NULL);

	ret = pmt_already_mounted(config, vpt, vinfo);
	if (ret < 0) {
		l0g("could not determine if %s is already mounted, "
		    "failing\n", vpt->volume);
		return 0;
	} else if (ret > 0) {
		w4rn("%s already seems to be mounted at %s, "
		     "skipping\n", vpt->volume, vpt->mountpoint);
		return 1;
	}
```

already_mounted

 * /etc/mtab からマウント済みのエントリを探している
 * mnt_table_next_fs でエントリをイテレート、 pmt_utabent_matches で一致するマウントポイトが無いかを探す


```c
/**
 * already_mounted -
 * @config:	current config
 * @vpt:	volume descriptor
 * @vinfo:
 *
 * Checks if @config->volume[@vol] is already mounted, and returns 1 if this
 * the case, 0 if not and -1 on error.
 */
int pmt_already_mounted(const struct config *const config,
    const struct vol *vpt, struct HXformat_map *vinfo)
{
	struct libmnt_context *ctx;
	struct libmnt_table *table;
	struct libmnt_iter *iter;
	struct libmnt_fs *fs;
	int ret = 0;

	ctx = mnt_new_context();
	if (ctx == NULL)
		return -1;
	if (mnt_context_get_mtab(ctx, &table) != 0)
		goto out;
	iter = mnt_new_iter(MNT_ITER_BACKWARD);
	if (iter == NULL)
		goto out;

	while (mnt_table_next_fs(table, iter, &fs) == 0)
		if (pmt_utabent_matches(vpt, fs)) {
			ret = 1;
			break;
		}
 out:
	mnt_free_context(ctx);
	return ret;
}
```

pmt_utabent_matches

 * strcmp で比較

```c
/**
 * Compares a given utab entry to the volume. crypt-type volumes will always
 * be compared case-sensitive since they always use an existing file.
 */
static bool pmt_utabent_matches(const struct vol *vpt, struct libmnt_fs *fs)
{
	int (*xcmp)(const char *, const char *);
	const char *source = mnt_fs_get_source(fs);
	const char *target = mnt_fs_get_target(fs);
	bool result = false;

	xcmp = fstype2_icase(vpt->type) ? strcasecmp : strcmp;
	if (source != NULL)
		result = xcmp(vpt->volume, source) == 0;
	if (target != NULL)
		result &= strcmp(vpt->mountpoint, target) == 0;
	return result;
}
```