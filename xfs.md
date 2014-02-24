
# xfs

## TODO

 * delayed_works
   * INIT_DELAYED_WORK
   * cancel_delayed_work_sync
 * work_struct
   * INIT_WORK
   * cancel_work_sync

## xfs_flush_worker

 * カーネルスレッドのエントリポイントは以下のコード

```c
STATIC void
xfs_flush_worker(
	struct work_struct *work)
{
	struct xfs_mount *mp = container_of(work,
					struct xfs_mount, m_flush_work);

	xfs_sync_data(mp, SYNC_TRYLOCK);
	xfs_sync_data(mp, SYNC_TRYLOCK | SYNC_WAIT);
}
```

xfs_flush_worker がポインタで渡されてる箇所

```c
int
xfs_syncd_init(
	struct xfs_mount	*mp)
{
	INIT_WORK(&mp->m_flush_work, xfs_flush_worker);
```

**background inode flush** という役割

```c
	struct work_struct	m_flush_work;	/* background inode flush */
```    

## xfs_sync_data

```c
/*
 * Write out pagecache data for the whole filesystem.
 */
STATIC int
xfs_sync_data(
	struct xfs_mount	*mp,
	int			flags)
{
	int			error;

	ASSERT((flags & ~(SYNC_TRYLOCK|SYNC_WAIT)) == 0);

	error = xfs_inode_ag_iterator(mp, xfs_sync_inode_data, flags);
	if (error)
		return XFS_ERROR(error);

	xfs_log_force(mp, (flags & SYNC_WAIT) ? XFS_LOG_SYNC : 0);
	return 0;
}
```

```c
int
xfs_inode_ag_iterator(
	struct xfs_mount	*mp,
	int			(*execute)(struct xfs_inode *ip,
					   struct xfs_perag *pag, int flags),
	int			flags)
{
	struct xfs_perag	*pag;
	int			error = 0;
	int			last_error = 0;
	xfs_agnumber_t		ag;

	ag = 0;
	while ((pag = xfs_perag_get(mp, ag))) {
		ag = pag->pag_agno + 1;
		error = xfs_inode_ag_walk(mp, pag, execute, flags);
		xfs_perag_put(pag);
		if (error) {
			last_error = error;
			if (error == EFSCORRUPTED)
				break;
		}
	}
	return XFS_ERROR(last_error);
}
```

radix_tree

