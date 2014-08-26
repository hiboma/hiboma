# Handler_read_* を理解する (2)

セカンダリキーの場合を整理します

![covering](https://cloud.githubusercontent.com/assets/172456/4042027/c74ed422-2cfe-11e4-8b86-ac8bae3819e7.png)


UNIQUE制約の無いセカンダリインデックスなので `WHERE user_id = 1` とした場合にインデックスを走査してマッチするレコードを探す必要がある (UNIQUEでない => 走査しないと件数が分からない)。 `type = ref` がそれを示しています

#### サンプルクエリ

```sql
SELECT * FROM bar WHERE user_id = 3;
```

```
+----+-------------+-------+------+---------------+---------+---------+-------+------+-------+
| id | select_type | table | type | possible_keys | key     | key_len | ref   | rows | Extra |
+----+-------------+-------+------+---------------+---------+---------+-------+------+-------+
|  1 | SIMPLE      | bar   | ref  | user_id       | user_id | 5       | const |    2 | NULL  |
+----+-------------+-------+------+---------------+---------+---------+-------+------+-------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 0     |
| Handler_read_key      | 1     |
| Handler_read_last     | 0     |
| Handler_read_next     | 2     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

#### Covering Index

![2014-08-26 16 57 16](https://cloud.githubusercontent.com/assets/172456/4042028/c761a336-2cfe-11e4-9126-3785e8c8b00e.png)

`SELECT` するカラムを `id` (もしくは user_id) にすると Covering Index になる。 primary キーの走査が無くなる

```
SELECT id FROM bar WHERE user_id = 2;
```

```
+----+-------------+-------+------+---------------+---------+---------+-------+------+-------------+
| id | select_type | table | type | possible_keys | key     | key_len | ref   | rows | Extra       |
+----+-------------+-------+------+---------------+---------+---------+-------+------+-------------+
|  1 | SIMPLE      | bar   | ref  | user_id       | user_id | 5       | const |    2 | Using index |
+----+-------------+-------+------+---------------+---------+---------+-------+------+-------------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 0     |
| Handler_read_key      | 1     |
| Handler_read_last     | 0     |
| Handler_read_next     | 2     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

## WHERE in (?,?)

![2014-08-26 17 44 32](https://cloud.githubusercontent.com/assets/172456/4042030/c766f444-2cfe-11e4-96fd-03df121bf50c.png)

```sql
SELECT * FROM bar WHERE user_id in (2,3);
```

```
+----+-------------+-------+-------+---------------+---------+---------+------+------+-----------------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra                 |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-----------------------+
|  1 | SIMPLE      | bar   | range | user_id       | user_id | 5       | NULL |    4 | Using index condition |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-----------------------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 0     |
| Handler_read_key      | 2     |
| Handler_read_last     | 0     |
| Handler_read_next     | 4     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

#### Covering Index にした場合

![2014-08-26 17 32 32](https://cloud.githubusercontent.com/assets/172456/4042029/c76505f8-2cfe-11e4-89a9-ac31e16d604d.png)

#### サンプルクエリ

```sql
SELECT user_id FROM bar WHERE user_id in (1,3);
```

```
+----+-------------+-------+-------+---------------+---------+---------+------+------+--------------------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra                    |
+----+-------------+-------+-------+---------------+---------+---------+------+------+--------------------------+
|  1 | SIMPLE      | bar   | range | user_id       | user_id | 5       | NULL |    4 | Using where; Using index |
+----+-------------+-------+-------+---------------+---------+---------+------+------+--------------------------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 0     |
| Handler_read_key      | 2     |
| Handler_read_last     | 0     |
| Handler_read_next     | 4     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```


