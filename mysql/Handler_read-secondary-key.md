# Handler_read_* を理解する (2)

非UNIQUE なセカンダリキーの場合を整理します

## テーブルのスキーマとデータセット

```sql
mysql> show create table bar \G;
*************************** 1. row ***************************
       Table: bar
Create Table: CREATE TABLE `bar` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `title` varchar(255) DEFAULT NULL,
  `user_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `user_id` (`user_id`)  
) ENGINE=InnoDB AUTO_INCREMENT=27 DEFAULT CHARSET=latin1
1 row in set (0.00 sec)
```

 * `id` が primary キー
 * `user_id` がセカンダリキー (非 UNIQUE)
   * 図では **key** と書いています。読み替えてください ...

```sql
mysql> select * from bar;                                                                                                                                                            +----+--------+---------+
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

UNIQUE制約の無いセカンダリインデックス

 * **Handler_read_key** で `WHERE user_id = 1` にマッチするレコードを探す
 * UNIQUEインデックスでない => 走査しないと実際の件数が分からないので **Handler_read_key_next** で隣のレコードを見る

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

`SELECT` するカラムを `id` (もしくは user_id) にすると Covering Index になる。 primary キーの走査が無くなる (Extra に `Using index` が表示される)

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
SELECT id FROM bar WHERE user_id in (1,3);
```

![2014-08-26 17 32 32](https://cloud.githubusercontent.com/assets/172456/4042029/c76505f8-2cfe-11e4-89a9-ac31e16d604d.png)

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

```
create table bar ( id int primary key auto_increment, title varchar(255), user_id int, key(user_id));
insert into bar (title, user_id) values ("aaa", 1);
insert into bar (title, user_id) values ("aaaaaa", 1);
insert into bar (title, user_id) values ("bbb", 2);
insert into bar (title, user_id) values ("bbbbbb", 2);
insert into bar (title, user_id) values ("ccc", 3);
insert into bar (title, user_id) values ("cccccc", 3);
insert into bar (title, user_id) values ("ddd", 4);
insert into bar (title, user_id) values ("dddddd", 4); 
```