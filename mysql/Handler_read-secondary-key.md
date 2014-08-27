# Handler_read_* を理解する (2)

非UNIQUE なセカンダリキーの場合を整理します

## テーブルのスキーマとデータセット

```sql
CREATE TABLE `bar` (
  `id`      int(11)      NOT NULL AUTO_INCREMENT,
  `title`   varchar(255) DEFAULT NULL,
  `sid`     int(11)      DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY  `sid` (`sid`)
) ENGINE=InnoDB
```

`sid` をセカンダリキー (非 UNIQUE) としています

```sql
+----+--------+------+
| id | title  | sid  |
+----+--------+------+
|  1 | aaa    |    1 |
|  2 | aaaaaa |    1 |
|  3 | bbb    |    2 |
|  4 | bbbbbb |    2 |
|  5 | ccc    |    3 |
|  6 | cccccc |    3 |
|  7 | ddd    |    4 |
|  8 | dddddd |    4 |
+----+--------+---------+
8 rows in set (0.00 sec)
```

## サンプルクエリ

```sql
SELECT * FROM bar WHERE sid = 2;
```

![where 2](https://cloud.githubusercontent.com/assets/172456/4056768/538de002-2dbf-11e4-95e9-8051bdd30691.png)

 * **Handler_read_key** で `WHERE sid = 3` にマッチするレコードを探す
 * UNIQUEインデックスでないため、マッチするレコードの件数はインデックスを走査しないと分からないので **Handler_read_key_next** で隣のレコードを見る

```
+----+-------------+-------+------+---------------+------+---------+-------+------+-------+
| id | select_type | table | type | possible_keys | key  | key_len | ref   | rows | Extra |
+----+-------------+-------+------+---------------+------+---------+-------+------+-------+
|  1 | SIMPLE      | bar   | ref  | sid           | sid  | 5       | const |    2 | NULL  |
+----+-------------+-------+------+---------------+------+---------+-------+------+-------+
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
SELECT id FROM bar WHERE sid = 2;
```

![where 2 covering index](https://cloud.githubusercontent.com/assets/172456/4056770/539ff904-2dbf-11e4-8d6b-d1861050b180.png)

 * `SELECT` するカラムを `id` (もしくは sid) にすると Covering Index になる
 * Extra に `Using index` が表示される
 * Handler_read_key, Handler_read_next の数値は変わらない

Covering Index なので primary キーの走査が無くなる 

```
+----+-------------+-------+------+---------------+------+---------+-------+------+-------+
| id | select_type | table | type | possible_keys | key  | key_len | ref   | rows | Extra |
+----+-------------+-------+------+---------------+------+---------+-------+------+-------+
|  1 | SIMPLE      | bar   | ref  | sid           | sid  | 5       | const |    2 | NULL  |
+----+-------------+-------+------+---------------+------+---------+-------+------+-------+
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
SELECT * FROM bar WHERE sid in (2,3);
```

![where in 1 3](https://cloud.githubusercontent.com/assets/172456/4056771/53a83182-2dbf-11e4-85bb-9850f70ce4f9.png)

```
+----+-------------+-------+-------+---------------+------+---------+------+------+-----------------------+
| id | select_type | table | type  | possible_keys | key  | key_len | ref  | rows | Extra                 |
+----+-------------+-------+-------+---------------+------+---------+------+------+-----------------------+
|  1 | SIMPLE      | bar   | range | sid           | sid  | 5       | NULL |    4 | Using index condition |
+----+-------------+-------+-------+---------------+------+---------+------+------+-----------------------+
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

![where in 1 3 covering index](https://cloud.githubusercontent.com/assets/172456/4056769/5399c08e-2dbf-11e4-8810-967bcffe6266.png)

 * `SELECT` するカラムを `id` (もしくは `sid` ) にするとセカンダリインデックスだけで対象行のカラムを取れるので **Covering Index** になる
 * Extra に `Using index` が表示される
 * primary キーの走査が無くなる
 * Handler_read_key, Handler_read_next の数値は変わらない

```
+----+-------------+-------+-------+---------------+------+---------+------+------+--------------------------+
| id | select_type | table | type  | possible_keys | key  | key_len | ref  | rows | Extra                    |
+----+-------------+-------+-------+---------------+------+---------+------+------+--------------------------+
|  1 | SIMPLE      | bar   | range | sid           | sid  | 5       | NULL |    4 | Using where; Using index |
+----+-------------+-------+-------+---------------+------+---------+------+------+--------------------------+
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