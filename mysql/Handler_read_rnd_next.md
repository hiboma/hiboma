# Handler_read_rnd_next

## InnoDB の場合

 * index_first でインデックスを使って最初の行を探す

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