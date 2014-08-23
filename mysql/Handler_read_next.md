# Handler_read_next

Handler_read_next の数値の意味を追いかけます

## 予習

下記のエントリがすばらしく分かりやすい

 * http://bizstation.hatenablog.com/entry/2014/01/27/152739
 * http://bizstation.hatenablog.com/entry/2014/01/28/182943
 * http://bizstation.hatenablog.com/entry/2014/01/29/121949
 * http://bizstation.hatenablog.com/entry/2014/02/17/121151

## Handler_read_next の定義

```
The number of requests to read the next row in key order. This value is incremented if you are querying an index column with a range constraint or if you are doing an index scan.
```

http://dev.mysql.com/doc/refman/5.6/en/server-status-variables.html#statvar_Handler_read_next

 * インデックスで次の行を読み取ろうとした回数
   * 行があるかどうか分からないので「読み取った回数」ではない...よね?
 * カラムで range 制約のクエリ??? インデックスキャン したらインクリメントされる
   * 範囲検索 のことでいいのかな

# ソースを読んでみます

 * 5.6.20

## sql/mysqld.cc

```
  {"Handler_read_first",       (char*) offsetof(STATUS_VAR, ha_read_first_count), SHOW_LONGLONG_STATUS},
  {"Handler_read_key",         (char*) offsetof(STATUS_VAR, ha_read_key_count), SHOW_LONGLONG_STATUS},
  {"Handler_read_last",        (char*) offsetof(STATUS_VAR, ha_read_last_count), SHOW_LONGLONG_STATUS},
  {"Handler_read_next",        (char*) offsetof(STATUS_VAR, ha_read_next_count), SHOW_LONGLONG_STATUS},
  {"Handler_read_prev",        (char*) offsetof(STATUS_VAR, ha_read_prev_count), SHOW_LONGLONG_STATUS},
  {"Handler_read_rnd",         (char*) offsetof(STATUS_VAR, ha_read_rnd_count), SHOW_LONGLONG_STATUS},
  {"Handler_read_rnd_next",    (char*) offsetof(STATUS_VAR, ha_read_rnd_next_count), SHOW_LONGLONG_STATUS},
```

## ha_read_next_count が使われている箇所

```cc
sql/sql_class.h:  ulonglong ha_read_next_count;
storage/federated/ha_federated.cc:  ha_statistic_increment(&SSV::ha_read_next_count);
storage/heap/ha_heap.cc:  ha_statistic_increment(&SSV::ha_read_next_count);
storage/innobase/handler/ha_innodb.cc:	ha_statistic_increment(&SSV::ha_read_next_count);
storage/innobase/handler/ha_innodb.cc:	ha_statistic_increment(&SSV::ha_read_next_count);
storage/myisam/ha_myisam.cc:  ha_statistic_increment(&SSV::ha_read_next_count);
storage/myisam/ha_myisam.cc:  ha_statistic_increment(&SSV::ha_read_next_count);
storage/myisam/ha_myisam.cc:  thread_safe_increment(table->in_use->status_var.ha_read_next_count,
storage/myisammrg/ha_myisammrg.cc:  ha_statistic_increment(&SSV::ha_read_next_count);
storage/myisammrg/ha_myisammrg.cc:  ha_statistic_increment(&SSV::ha_read_next_count);
```

ストレージエンジンごとに呼び出されている。 InnoDB の実装だけ追いかけます

## storage/innobase/handler/ha_innodb.cc

 * ha_innobase::index_next
 * ha_innobase::index_next_same 

で統計値をインクリメントしている

#### ha_innobase::index_next, ha_innobase::index_next_same

```cc
/***********************************************************************//**
Reads the next row from a cursor, which must have previously been
positioned using index_read.
@return	0, HA_ERR_END_OF_FILE, or error number */
UNIV_INTERN
int
ha_innobase::index_next(
/*====================*/
	uchar*		buf)	/*!< in/out: buffer for next row in MySQL
				format */
{
	ha_statistic_increment(&SSV::ha_read_next_count);

	return(general_fetch(buf, ROW_SEL_NEXT, 0));
}

/*******************************************************************//**
Reads the next row matching to the key value given as the parameter.
@return	0, HA_ERR_END_OF_FILE, or error number */
UNIV_INTERN
int
ha_innobase::index_next_same(
/*=========================*/
	uchar*		buf,	/*!< in/out: buffer for the row */
	const uchar*	key,	/*!< in: key value */
	uint		keylen)	/*!< in: key value length */
{
	ha_statistic_increment(&SSV::ha_read_next_count);

	return(general_fetch(buf, ROW_SEL_NEXT, last_match_mode));
}
```

ROW_SEL_NEXT は探索の方向が ASC であることを差している様子

```cc
/** Search direction for the MySQL interface */
enum row_sel_direction {
	ROW_SEL_NEXT = 1,	/*!< ascending direction */
	ROW_SEL_PREV = 2	/*!< descending direction */
};
```

# handler 層に上る

ストレージエンジンに潜るのは一旦脇においておいて、呼び出し元 (handler層) の実装を見てみます

## handler::ha_index_next

 * `Reads the next row via index` とある
 * 返り値で HA_ERR_END_OF_FILE が返ってきた場合は行が無い
   * 行が無くても ha_read_next_count はインクリメントされる
   * その他エラーの場合でもインクリメントされている

```c
/**
  Reads the next row via index.

  @param[out] buf  Row data

  @return Operation status.
    @retval  0                   Success
    @retval  HA_ERR_END_OF_FILE  Row not found
    @retval  != 0                Error
*/

int handler::ha_index_next(uchar * buf)
{
  int result;
  DBUG_ENTER("handler::ha_index_next");
  DBUG_ASSERT(table_share->tmp_table != NO_TMP_TABLE ||
              m_lock_type != F_UNLCK);
  DBUG_ASSERT(inited == INDEX);

  MYSQL_TABLE_IO_WAIT(m_psi, PSI_TABLE_FETCH_ROW, active_index, 0,
    { result= index_next(buf); })
  DBUG_RETURN(result);
}
```

## handler::ha_index_next_same

`Reads the next same row via index` の意味がよく分からなかったが、UNIQUEであるかどうかに依るようだ。下の二つを読むとスッキリ理解できる!!!

 * http://bizstation.hatenablog.com/entry/2014/01/29/121949
 * http://bizstation.hatenablog.com/entry/2014/02/17/121151

UNIQUE制約が無いインデックスの場合はクエリにマッチする行数を事前に知ることができないので、後続の行を読んで確かめる必要がある

```c
/**
  Reads the next same row via index.

  @param[out] buf     Row data
  @param      key     Key to search for
  @param      keylen  Length of key

  @return Operation status.
    @retval  0                   Success
    @retval  HA_ERR_END_OF_FILE  Row not found
    @retval  != 0                Error
*/

int handler::ha_index_next_same(uchar *buf, const uchar *key, uint keylen)
{
  int result;
  DBUG_ASSERT(table_share->tmp_table != NO_TMP_TABLE ||
              m_lock_type != F_UNLCK);
  DBUG_ASSERT(inited == INDEX);

  MYSQL_TABLE_IO_WAIT(m_psi, PSI_TABLE_FETCH_ROW, active_index, 0,
    { result= index_next_same(buf, key, keylen); })
  return result;
}
```

handler 層を読むのは一旦終わり。InnoDB の実装に戻ります

## ha_innobase::general_fetch

 * 現在のカーソルから次の業を読む
 * index_read でポジションが決まっている?

```cc
/***********************************************************************//**
Reads the next or previous row from a cursor, which must have previously been
positioned using index_read.
@return	0, HA_ERR_END_OF_FILE, or error number */
UNIV_INTERN
int
ha_innobase::general_fetch(
/*=======================*/
	uchar*	buf,		/*!< in/out: buffer for next row in MySQL
				format */
	uint	direction,	/*!< in: ROW_SEL_NEXT or ROW_SEL_PREV */
	uint	match_mode)	/*!< in: 0, ROW_SEL_EXACT, or
				ROW_SEL_EXACT_PREFIX */
{
	dberr_t	ret;
	int	error;

	DBUG_ENTER("general_fetch");

	ut_a(prebuilt->trx == thd_to_trx(user_thd));

	innobase_srv_conc_enter_innodb(prebuilt->trx);

	ret = row_search_for_mysql(
		(byte*) buf, 0, prebuilt, match_mode, direction);

	innobase_srv_conc_exit_innodb(prebuilt->trx);

	switch (ret) {
	case DB_SUCCESS:
		error = 0;
		table->status = 0;
		srv_stats.n_rows_read.add((size_t) prebuilt->trx->id, 1);
		break;
	case DB_RECORD_NOT_FOUND:
		error = HA_ERR_END_OF_FILE;
		table->status = STATUS_NOT_FOUND;
		break;
	case DB_END_OF_INDEX:
		error = HA_ERR_END_OF_FILE;
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
			ER_TABLESPACE_MISSING,
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

row_search_for_mysql が強過ぎる