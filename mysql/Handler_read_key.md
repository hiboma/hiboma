# Handler_read_key

## sql/mysqld.cc

```c
  {"Handler_read_key",         (char*) offsetof(STATUS_VAR, ha_read_key_count), SHOW_LONGLONG_STATUS},
```

ha_read_key_count が使われているコードを追いかけたらよい

## ha_read_key_count が使われている箇所

```
ha_read_key_count 7915 sql/mysqld.cc      {"Handler_read_key",         (char*) offsetof(STATUS_VAR, ha_read_key_count), SHOW_LONGLONG_STATUS},
ha_read_key_count  573 sql/sql_class.h    ulonglong ha_read_key_count;
ha_read_key_count  483 sql/sql_test.cc  	 tmp.ha_read_key_count,
ha_read_key_count 2412 storage/federated/ha_federated.cc   ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count  287 storage/heap/ha_heap.cc   ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count  299 storage/heap/ha_heap.cc   ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count  312 storage/heap/ha_heap.cc   ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count 7442 storage/innobase/handler/ha_innodb.cc 	ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count 1648 storage/myisam/ha_myisam.cc   ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count 1662 storage/myisam/ha_myisam.cc   ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count 1675 storage/myisam/ha_myisam.cc   ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count 1108 storage/myisammrg/ha_myisammrg.cc   ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count 1121 storage/myisammrg/ha_myisammrg.cc   ha_statistic_increment(&SSV::ha_read_key_count);
ha_read_key_count 1133 storage/myisammrg/ha_myisammrg.cc   ha_statistic_increment(&SSV::ha_read_key_count);
```

## handler 層で index_read を呼んでいるコード

 * 「インデックスを使って行を読む」
 * まんまな説明でーある

```c
/**
  Read one row via index.

  @param[out] buf        Row data
  @param      key        Key to search for
  @param      keylen     Length of key
  @param      find_flag  Direction/condition on key usage

  @return Operation status.
    @retval  0                   Success
    @retval  HA_ERR_END_OF_FILE  Row not found
    @retval  != 0                Error
*/

int handler::ha_index_read(uchar *buf, const uchar *key, uint key_len,
                           enum ha_rkey_function find_flag)
{
  int result;
  DBUG_ASSERT(table_share->tmp_table != NO_TMP_TABLE ||
              m_lock_type != F_UNLCK);
  DBUG_ASSERT(inited == INDEX);

  MYSQL_TABLE_IO_WAIT(m_psi, PSI_TABLE_FETCH_ROW, active_index, 0,
    { result= index_read(buf, key, key_len, find_flag); })
  return result;
}
```

## InnoDB で ha_read_key_count を扱っているコード

 * **ha_innobase::index_read** だけ
   * row_search_for_mysql を呼び出す
 * 序文のコメントが何やら有用そう

```c
/*
   BACKGROUND INFO: HOW A SELECT SQL QUERY IS EXECUTED
   ---------------------------------------------------
The following does not cover all the details, but explains how we determine
the start of a new SQL statement, and what is associated with it.

For each table in the database the MySQL interpreter may have several
table handle instances in use, also in a single SQL query. For each table
handle instance there is an InnoDB  'prebuilt' struct which contains most
of the InnoDB data associated with this table handle instance.

  A) if the user has not explicitly set any MySQL table level locks:

  1) MySQL calls ::external_lock to set an 'intention' table level lock on
the table of the handle instance. There we set
prebuilt->sql_stat_start = TRUE. The flag sql_stat_start should be set
true if we are taking this table handle instance to use in a new SQL
statement issued by the user. We also increment trx->n_mysql_tables_in_use.

  2) If prebuilt->sql_stat_start == TRUE we 'pre-compile' the MySQL search
instructions to prebuilt->template of the table handle instance in
::index_read. The template is used to save CPU time in large joins.

  3) In row_search_for_mysql, if prebuilt->sql_stat_start is true, we
allocate a new consistent read view for the trx if it does not yet have one,
or in the case of a locking read, set an InnoDB 'intention' table level
lock on the table.

  4) We do the SELECT. MySQL may repeatedly call ::index_read for the
same table handle instance, if it is a join.

  5) When the SELECT ends, MySQL removes its intention table level locks
in ::external_lock. When trx->n_mysql_tables_in_use drops to zero,
 (a) we execute a COMMIT there if the autocommit is on,
 (b) we also release possible 'SQL statement level resources' InnoDB may
have for this SQL statement. The MySQL interpreter does NOT execute
autocommit for pure read transactions, though it should. That is why the
table handler in that case has to execute the COMMIT in ::external_lock.

  B) If the user has explicitly set MySQL table level locks, then MySQL
does NOT call ::external_lock at the start of the statement. To determine
when we are at the start of a new SQL statement we at the start of
::index_read also compare the query id to the latest query id where the
table handle instance was used. If it has changed, we know we are at the
start of a new SQL statement. Since the query id can theoretically
overwrap, we use this test only as a secondary way of determining the
start of a new SQL statement. */


/**********************************************************************//**
Positions an index cursor to the index specified in the handle. Fetches the
row if any.
@return	0, HA_ERR_KEY_NOT_FOUND, or error number */
UNIV_INTERN
int
ha_innobase::index_read(
/*====================*/
	uchar*		buf,		/*!< in/out: buffer for the returned
					row */
	const uchar*	key_ptr,	/*!< in: key value; if this is NULL
					we position the cursor at the
					start or end of index; this can
					also contain an InnoDB row id, in
					which case key_len is the InnoDB
					row id length; the key value can
					also be a prefix of a full key value,
					and the last column can be a prefix
					of a full column */
	uint			key_len,/*!< in: key value length */
	enum ha_rkey_function find_flag)/*!< in: search flags from my_base.h */
{
	ulint		mode;
	dict_index_t*	index;
	ulint		match_mode	= 0;
	int		error;
	dberr_t		ret;

	DBUG_ENTER("index_read");
	DEBUG_SYNC_C("ha_innobase_index_read_begin");

	ut_a(prebuilt->trx == thd_to_trx(user_thd));
	ut_ad(key_len != 0 || find_flag != HA_READ_KEY_EXACT);

    /* ここでインクリメント */
	ha_statistic_increment(&SSV::ha_read_key_count);

	index = prebuilt->index;

    /* インデックスが物故割れ系なら HA_ERR_KEY_NOT_FOUND 返す */
	if (UNIV_UNLIKELY(index == NULL) || dict_index_is_corrupted(index)) {
		prebuilt->index_usable = FALSE;
		DBUG_RETURN(HA_ERR_CRASHED);
	}

    /* インデックスが使えない => 物故割れている/定義が変わったエラー返す */
	if (UNIV_UNLIKELY(!prebuilt->index_usable)) {
		DBUG_RETURN(dict_index_is_corrupted(index)
			    ? HA_ERR_INDEX_CORRUPT
			    : HA_ERR_TABLE_DEF_CHANGED);
	}

    /* ??? キーが無い??? */
	if (index->type & DICT_FTS) {
		DBUG_RETURN(HA_ERR_KEY_NOT_FOUND);
	}

	/* Note that if the index for which the search template is built is not
	necessarily prebuilt->index, but can also be the clustered index */

	if (prebuilt->sql_stat_start) {
		build_template(false);
	}

	if (key_ptr) {
		/* Convert the search key value to InnoDB format into
		prebuilt->search_tuple */

		row_sel_convert_mysql_key_to_innobase(
			prebuilt->search_tuple,
			srch_key_val1, sizeof(srch_key_val1),
			index,
			(byte*) key_ptr,
			(ulint) key_len,
			prebuilt->trx);
		DBUG_ASSERT(prebuilt->search_tuple->n_fields > 0);
	} else {
		/* We position the cursor to the last or the first entry
		in the index */

		dtuple_set_n_fields(prebuilt->search_tuple, 0);
	}

	mode = convert_search_mode_to_innobase(find_flag);

	match_mode = 0;

    /*
     * HA_READ_KEY_EXACT
     *  - インデックスのキーが prefix (一部だけのやつ) でない
     *  - キーに完全一致するカラム値を見つけるモード
     *  - http://forums.mysql.com/read.php?94,98312,98312 
     */
	if (find_flag == HA_READ_KEY_EXACT) {

		match_mode = ROW_SEL_EXACT;

    /* col_name(length) でキーを prefix だけにしてやつでマッチさせる場合 ... かなー */
	} else if (find_flag == HA_READ_PREFIX
		   || find_flag == HA_READ_PREFIX_LAST) {

		match_mode = ROW_SEL_EXACT_PREFIX;
	}

	last_match_mode = (uint) match_mode;

	if (mode != PAGE_CUR_UNSUPP) {

		innobase_srv_conc_enter_innodb(prebuilt->trx);

        /* ここで行を探しまくる */
		ret = row_search_for_mysql((byte*) buf, mode, prebuilt,
					   match_mode, 0);

		innobase_srv_conc_exit_innodb(prebuilt->trx);
	} else {

		ret = DB_UNSUPPORTED;
	}

	switch (ret) {
	case DB_SUCCESS:
		error = 0;
		table->status = 0;
		srv_stats.n_rows_read.add((size_t) prebuilt->trx->id, 1);
		break;
	case DB_RECORD_NOT_FOUND:
		error = HA_ERR_KEY_NOT_FOUND;
		table->status = STATUS_NOT_FOUND;
		break;
	case DB_END_OF_INDEX:
		error = HA_ERR_KEY_NOT_FOUND;
		table->status = STATUS_NOT_FOUND;
		break;
	case DB_TABLESPACE_DELETED:

		ib_senderrf(
			prebuilt->trx->mysql_thd, IB_LOG_LEVEL_ERROR,
			ER_TABLESPACE_DISCARDED,
			table->s->table_name.str);

		table->status = STATUS_NOT_FOUND;
		error = HA_ERR_NO_SUCH_TABLE;
		break;
	case DB_TABLESPACE_NOT_FOUND:

		ib_senderrf(
			prebuilt->trx->mysql_thd, IB_LOG_LEVEL_ERROR,
			ER_TABLESPACE_MISSING, MYF(0),
			table->s->table_name.str);

		table->status = STATUS_NOT_FOUND;
		error = HA_ERR_NO_SUCH_TABLE;
		break;
	default:
		error = convert_error_code_to_mysql(
			ret, prebuilt->table->flags, user_thd);

		table->status = STATUS_NOT_FOUND;
		break;
	}

	DBUG_RETURN(error);
}
```

