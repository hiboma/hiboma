# Handler_read_rnd_next

 * handler::ha_rnd_init
 * handler::ha_rnd_next
 * handler::ha_rnd_end

を見ていって数値の意味を探ります

## handler 層

handler::ha_rnd_init によって inited が RND か INDEX かが決定される。

```c 
 /**
  Initialize table for random read or scan.

  @param scan  if true: Initialize for random scans through rnd_next()
               if false: Initialize for random reads through rnd_pos()

  @return Operation status
    @retval 0     Success
    @retval != 0  Error (error code returned)
*/

int handler::ha_rnd_init(bool scan)
{
  DBUG_EXECUTE_IF("ha_rnd_init_fail", return HA_ERR_TABLE_DEF_CHANGED;);
  int result;
  DBUG_ENTER("ha_rnd_init");
  DBUG_ASSERT(table_share->tmp_table != NO_TMP_TABLE ||
              m_lock_type != F_UNLCK);
  DBUG_ASSERT(inited == NONE || (inited == RND && scan));
  inited= (result= rnd_init(scan)) ? NONE : RND;
  end_range= NULL;
  DBUG_RETURN(result);
}
```

ha_rnd_nextには次の行をランダムスキャンする、とあるがストレージエンジンによって特性が変わるので これだけじゃ分からない

```c
/**
  Read next row via random scan.

  @param buf  Buffer to read the row into

  @return Operation status
    @retval 0     Success
    @retval != 0  Error (error code returned)
*/

int handler::ha_rnd_next(uchar *buf)
{
  int result;
  DBUG_ENTER("handler::ha_rnd_next");
  DBUG_ASSERT(table_share->tmp_table != NO_TMP_TABLE ||
              m_lock_type != F_UNLCK);
  DBUG_ASSERT(inited == RND);

  MYSQL_TABLE_IO_WAIT(m_psi, PSI_TABLE_FETCH_ROW, MAX_KEY, 0,
    { result= rnd_next(buf); })
  DBUG_RETURN(result);
}
```

```c
/**
  End use of random access.

  @return Operation status
    @retval 0     Success
    @retval != 0  Error (error code returned)
*/

int handler::ha_rnd_end()
{
  DBUG_ENTER("ha_rnd_end");
  /* SQL HANDLER function can call this without having it locked. */
  DBUG_ASSERT(table->open_by_handler ||
              table_share->tmp_table != NO_TMP_TABLE ||
              m_lock_type != F_UNLCK);
  DBUG_ASSERT(inited == RND);
  inited= NONE;
  end_range= NULL;
  DBUG_RETURN(rnd_end());
}
```

## InnoDB の場合

 * テーブルスキャンが開始されていない場合は index_first でインデックスを使って最初の行を探す
 * テーブルスキャン開始済みであれば `general_fetch(buf, ROW_SEL_NEXT, 0);` で次の行を取る
   * ha_innobase::index_next でも `general_fetch(buf, ROW_SEL_NEXT, 0)` 使っている
   * 「InnoDB primary キーのインデックススキャン == テーブルスキャン」だよね?

```c
/*****************************************************************//**
Reads the next row in a table scan (also used to read the FIRST row
in a table scan).
@return	0, HA_ERR_END_OF_FILE, or error number */
UNIV_INTERN
int
ha_innobase::rnd_next(
/*==================*/
	uchar*	buf)	/*!< in/out: returns the row in this buffer,
			in MySQL format */
{
	int	error;

	DBUG_ENTER("rnd_next");
	ha_statistic_increment(&SSV::ha_read_rnd_next_count);

	if (start_of_scan) {
		error = index_first(buf);

		if (error == HA_ERR_KEY_NOT_FOUND) {
			error = HA_ERR_END_OF_FILE;
		}

		start_of_scan = 0;
	} else {
		error = general_fetch(buf, ROW_SEL_NEXT, 0);
	}

	DBUG_RETURN(error);
}
```

合わせて　general_fetch のインタフェースを確認しておく

 * direction が ROW_SEL_NEXT なので、昇順に探すはず
 * match_mode = 0 な場合( !ROW_SEL_NEXT, !ROW_SEL_EXACT_PREFIX) はテーブル総なめにすることを意味する?

```c
/***********************************************************************//**
Reads the next or previous row from a cursor, which must have previously been
positioned using index_read.
@return	0, HA_ERR_END_OF_FILE, or error number */
UNIV_INTERN
int
ha_innobase::general_fetch(
/*=======================*/
	uchar*	buf,		/*!< in/out: buffer for next row in MySQL format */
	uint	direction,	/*!< in: ROW_SEL_NEXT or ROW_SEL_PREV */
	uint	match_mode)	/*!< in: 0, ROW_SEL_EXACT, or
				ROW_SEL_EXACT_PREFIX */
```

ha_innobase::rnd_init も見てみる

 * クラスタインデックスを使うように change_active_index する
 * start_of_scan = 1 を立てる

```c
/****************************************************************//**
Initialize a table scan.
@return	0 or error number */
UNIV_INTERN
int
ha_innobase::rnd_init(
/*==================*/
	bool	scan)	/*!< in: TRUE if table/index scan FALSE otherwise */
{
	int	err;

	/* Store the active index value so that we can restore the original
	value after a scan */

	if (prebuilt->clust_index_was_generated) {
		err = change_active_index(MAX_KEY);
	} else {
		err = change_active_index(primary_key);
	}

	/* Don't use semi-consistent read in random row reads (by position).
	This means we must disable semi_consistent_read if scan is false */

	if (!scan) {
		try_semi_consistent_read(0);
	}

	start_of_scan = 1;

	return(err);
}
```

## MyISAM の場合

```c
int ha_myisam::rnd_next(uchar *buf)
{
  MYSQL_READ_ROW_START(table_share->db.str, table_share->table_name.str,
                       TRUE);
  ha_statistic_increment(&SSV::ha_read_rnd_next_count);
  int error=mi_scan(file, buf);
  table->status=error ? STATUS_NOT_FOUND: 0;
  MYSQL_READ_ROW_DONE(error);
  return error;
}
```

mi_scan で MI_INFO の info->nextpos で次の行のポジション(ファイル無いでのオフセット、seek(2) する位置) を決定している

```c
/*
	   Read a row based on position.
	   If filepos= HA_OFFSET_ERROR then read next row
	   Return values
	   Returns one of following values:
	   0 = Ok.
	   HA_ERR_END_OF_FILE = EOF.
*/

int mi_scan(MI_INFO *info, uchar *buf)
{
  int result;
  DBUG_ENTER("mi_scan");
  /* Init all but update-flag */
  info->update&= (HA_STATE_CHANGED | HA_STATE_ROW_CHANGED);
  result= (*info->s->read_rnd)(info, buf, info->nextpos, 1);
  DBUG_RETURN(result);
}
```