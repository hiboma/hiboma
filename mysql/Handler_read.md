#  Handler_read_* のイメージをまとめる

`SHOW STATUS LIKE 'handler_read%` で取れる統計値が何を意味する数値なのかまとめます

 * 説明の簡略化のために InnoDB の primary key (クラスタインデックス) だけで図にしています
   * セカンダリインデックスも考えると大変そうなので
 * 図は kazeburo さんの http://www.slideshare.net/kazeburo/isucon-summerclass2014action2final をまねて書いています

### SEE ALSO

 * http://dev.mysql.com/doc/refman/5.6/en/server-status-variables.html#statvar_Handler_read_first

## Handler_read_first

インデックスの最初のエントリを読み取るとカウントされる

![2014-08-25 16 08 57](https://cloud.githubusercontent.com/assets/172456/4027141/d4d22210-2c28-11e4-8431-79539a60b5cf.png)

昇順で (フル)インデックススキャン する際に ***Handler_read_next*** と一緒に使われるます

## Handler_read_last

インデックスの最後のエントリを読み取るとカウントされる

![2014-08-25 16 10 03](https://cloud.githubusercontent.com/assets/172456/4027136/d4aac26a-2c28-11e4-8e16-105838f6440e.png)

降順で (フル)インデックススキャン する際に ***Handler_read_prev*** と一緒に使われます

## Handler_read_key

インデックスを使って対象のレコードを見つけるとカウントされる

![2014-08-25 16 11 27](https://cloud.githubusercontent.com/assets/172456/4027138/d4b38436-2c28-11e4-8547-05e975bfe499.png)

#### サンプルクエリ

```sql
SELECT * FROM foo WHERE id = 3
```

```
+----+-------------+-------+-------+---------------+---------+---------+-------+------+-------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref   | rows | Extra |
+----+-------------+-------+-------+---------------+---------+---------+-------+------+-------+
|  1 | SIMPLE      | foo   | const | PRIMARY       | PRIMARY | 4       | const |    1 | NULL  |
+----+-------------+-------+-------+---------------+---------+---------+-------+------+-------+
```

クエリの種類として最速

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 0     |
| Handler_read_key      | 1     |
| Handler_read_last     | 0     |
| Handler_read_next     | 0     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

**SELECT id FROM foo WHERE id in (?,?,?)**

![2014-08-25 17 55 03](https://cloud.githubusercontent.com/assets/172456/4027870/ce3701ac-2c35-11e4-9326-c1e6d64903f3.png)

`in` にマッチする行を取りにいって、 ***Handler_read_key*** でカウントされます

#### サンプルクエリ

```sql
SELECT * FROM foo WHERE id in (2,4,6);
```

```
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra       |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
|  1 | SIMPLE      | foo   | range | PRIMARY       | PRIMARY | 4       | NULL |    3 | Using where |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 0     |
| Handler_read_key      | 3     |
| Handler_read_last     | 0     |
| Handler_read_next     | 0     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

#### SELECT * FROM foo WHERE id in (2,4,6,8)

`SELECT *` にすると、 `in` を使っていても結果が異なるのが面白い

```sql
SELECT * FROM foo WHERE id in (2,4,6,8)
```

```
+----+-------------+-------+------+---------------+------+---------+------+------+-------------+
| id | select_type | table | type | possible_keys | key  | key_len | ref  | rows | Extra       |
+----+-------------+-------+------+---------------+------+---------+------+------+-------------+
|  1 | SIMPLE      | foo   | ALL  | PRIMARY       | NULL | NULL    | NULL |    8 | Using where |
+----+-------------+-------+------+---------------+------+---------+------+------+-------------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 1     |
| Handler_read_key      | 1     |
| Handler_read_last     | 0     |
| Handler_read_next     | 0     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 9     |
+-----------------------+-------+
```

`SELECT *` でかつ `in` に指定したレコード数が、テーブル全体のレコード数の半数に達しているのでオプティマイザがテーブルスキャンを選択したか?

## Handler_read_next

赤矢印とオレンジ矢印が ***Handler_read_next*** としてカウントされます

![2014-08-25 17 39 17](https://cloud.githubusercontent.com/assets/172456/4027751/d903b06e-2c33-11e4-84a5-6fe515564ef6.png)

 1. Handler_read_key で対象のレコードを見つける
 2. インデックスで昇順に次のレコードを探そうとするとカウントされます
   * range 検索では次のレコードをみて range に収まるかどうかの判定が必要なので オレンジ矢印も含まれます

#### サンプルクエリ

```sql
SELECT * FROM foo WHERE 2 < id and id < 7;
```

レンジ検索になっています

```
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra       |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
|  1 | SIMPLE      | foo   | range | PRIMARY       | PRIMARY | 4       | NULL |    3 | Using where |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 0     |
| Handler_read_key      | 1     |
| Handler_read_last     | 0     |
| Handler_read_next     | 4     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

(降順方向だと ***Handler_read_prev*** になります)

## Handler_read_first + Handler_read_key + Handler_read_next

昇順のフルインデックススキャン

![2014-08-25 17 41 00](https://cloud.githubusercontent.com/assets/172456/4027750/d9013dac-2c33-11e4-8ad0-9eaa60984ba6.png)

#### サンプルクエリ

```sql
SELECT * FROM foo ORDER BY id ASC
```

```
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------+
|  1 | SIMPLE      | foo   | index | NULL          | PRIMARY | 4       | NULL |    8 | NULL  |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 1     |
| Handler_read_key      | 1     |
| Handler_read_last     | 0     |
| Handler_read_next     | 8     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

## Handler_read_last + Handler_read_key + Handler_read_prev

降順のフルインデックススキャン

![2014-08-25 17 42 34](https://cloud.githubusercontent.com/assets/172456/4027752/d914d13c-2c33-11e4-949d-807f3d485744.png)

#### サンプルクエリ

```sql
SELECT * FROM foo ORDER BY id DESC
```

```
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------+
|  1 | SIMPLE      | foo   | index | NULL          | PRIMARY | 4       | NULL |    8 | NULL  |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 0     |
| Handler_read_key      | 1     |
| Handler_read_last     | 1     |
| Handler_read_next     | 0     |
| Handler_read_prev     | 8     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

