# Handler_read_* を理解する (2)

非UNIQUE なセカンダリキーの場合を整理します

## テーブルのスキーマとデータセット

```sql
CREATE TABLE `bar` (
  `id`      int(11)      NOT NULL AUTO_INCREMENT,
  `title`   varchar(255) DEFAULT NULL,
  `user_id` int(11)      DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `user_id` (`user_id`)  
) ENGINE=InnoDB
```

`user_id` をセカンダリキー (非 UNIQUE) としています。図では **key** と書いています。読み替えてください ...)

```sql
+----+--------+---------+
| id | title  | user_id |
+----+--------+---------+
|  1 | aaa    |       1 |
|  2 | aaaaaa |       1 |
|  3 | bbb    |       2 |
|  4 | bbbbbb |       2 |
|  5 | ccc    |       3 |
|  6 | cccccc |       3 |
|  7 | ddd    |       4 |
|  8 | dddddd |       4 |
+----+--------+---------+
8 rows in set (0.00 sec)
```

## サンプルクエリ

```sql
SELECT * FROM bar WHERE user_id = 3;
```

![covering](https://cloud.githubusercontent.com/assets/172456/4042027/c74ed422-2cfe-11e4-8b86-ac8bae3819e7.png)

 * **Handler_read_key** で `WHERE user_id = 3` にマッチするレコードを探す
 * UNIQUEインデックスでないため、マッチするレコードの件数はインデックスを走査しないと分からないので **Handler_read_key_next** で隣のレコードを見る

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

## Covering Index 版

```sql
SELECT id FROM bar WHERE user_id = 2;
```

![2014-08-26 16 57 16](https://cloud.githubusercontent.com/assets/172456/4042028/c761a336-2cfe-11e4-9126-3785e8c8b00e.png)

 * `SELECT` するカラムを `id` (もしくは user_id) にすると Covering Index になる
   * Extra に `Using index` が表示される
   * primary キーの走査が無くなる
 * Handler_read_key, Handler_read_next の数値は変わらない

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

## サンプルクエリ

```sql
SELECT * FROM bar WHERE user_id in (2,3);
```

![2014-08-26 17 44 32](https://cloud.githubusercontent.com/assets/172456/4042030/c766f444-2cfe-11e4-96fd-03df121bf50c.png)

```
+----+-------------+-------+-------+---------------+---------+---------+------+------+-----------------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra                 |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-----------------------+
|  1 | SIMPLE      | bar   | range | user_id       | user_id | 5       | NULL |    4 | Using index condition |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-----------------------+
```

`Using index condition` が出ているので、図とは違う動きかもなー。うーん

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

#### Covering Index 版

```sql
SELECT id FROM bar WHERE sid in (1,3);
```

![2014-08-26 17 32 32](https://cloud.githubusercontent.com/assets/172456/4042029/c76505f8-2cfe-11e4-89a9-ac31e16d604d.png)

 * `SELECT` するカラムを `id` (もしくは user_id) にすると Covering Index になる
   * Extra に `Using index` が表示される
   * primary キーの走査が無くなる
 * Handler_read_key, Handler_read_next の数値は変わらない

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

----

```sql
create table bar ( id int primary key auto_increment, title varchar(255), sid int, key(sid));
insert into bar (title, sid) values ("aaa", 1);
insert into bar (title, sid) values ("aaaaaa", 1);
insert into bar (title, sid) values ("bbb", 2);
insert into bar (title, sid) values ("bbbbbb", 2);
insert into bar (title, sid) values ("ccc", 3);
insert into bar (title, sid) values ("cccccc", 3);
insert into bar (title, sid) values ("ddd", 4);
insert into bar (title, sid) values ("dddddd", 4); 
```