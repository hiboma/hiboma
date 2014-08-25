#  Handler_read_* を理解する

MySQL の `SHOW STATUS LIKE 'handler_read%` で取れる統計値が何を意味する数値なのかまとめます

 * Handler_read_first
 * Handler_read_last
 * Handler_read_key 
 * Handler_read_next
 * Handler_read_prev
 * Handler_read_rnd
 * Handler_read_rnd_next

についてのモデル図とサンプルクエリを載せています

#### 前置き

 * 簡略化のために InnoDB の primary key (クラスタインデックス) だけ元に図にしています
   * セカンダリインデックスも考えると大変そうなので ...
 * モデル図は kazeburo さんのグレートスライド http://www.slideshare.net/kazeburo/isucon-summerclass2014action2final をまねて書いています
 * モデル図はソースとマニュアル等を「おそらくこうだろう」という推測で書いています。そのため正確さを欠いている点がある場合は了承ください

#### SEE ALSO

Handler_read_* の説明は [MySQL :: MySQL 5.6 Reference Manual :: 5.1.6 Server Status Variables](http://dev.mysql.com/doc/refman/5.6/en/server-status-variables.html#statvar_Handler_read_first) らへんを読むとよいでしょう。ただし、これ読んでも具体的な挙動が分からないってのが本音です ...

## Handler_read_first

インデックスの最初のエントリを読み取るとカウントされる

![2014-08-25 16 08 57](https://cloud.githubusercontent.com/assets/172456/4027141/d4d22210-2c28-11e4-8431-79539a60b5cf.png)

昇順で (フル)インデックススキャン する際に ***Handler_read_next*** と一緒に使われます

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

クエリの種類として最速。

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

#### SELECT id FROM foo WHERE id in (?,?,?) にするとどうなるか?

![2014-08-25 17 55 03](https://cloud.githubusercontent.com/assets/172456/4027870/ce3701ac-2c35-11e4-9326-c1e6d64903f3.png)

`in` にマッチする行をそれぞれ取りにいって、 ***Handler_read_key*** でカウントされます

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

#### SELECT * FROM foo WHERE id in (?,?,?) にするとどうなるか?

`SELECT *` にすると、 `in` を使っていても結果が異なります。フルテーブルスキャンになってしまいました

#### サンプルクエリ

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

`SELECT *` でかつ `in` に指定したレコード数が、テーブル全体のレコード数の半数に達しているので、オプティマイザがフルテーブルスキャンの方がよいと選択したか?

( ***Handler_read_rnd_next*** の説明は別に書きます )

----

## Handler_read_next

赤矢印とオレンジ矢印が ***Handler_read_next*** としてカウントされる動きです

![2014-08-25 17 39 17](https://cloud.githubusercontent.com/assets/172456/4027751/d903b06e-2c33-11e4-84a5-6fe515564ef6.png)

上記は **レンジスキャン** になっているモデルとなります

 1. インデックスで対象のレコードを見つける
   * **Handler_read_key** でカウントされます
 2. インデックスで昇順に次のレコードを探す (赤矢印)
   * **Handler_read_next** でカウントされます    
     * B+木インデックスでは隣のリーフへのポインタが用意されている (赤矢印)
     * このポインタを辿ることで **次のレコード** を探すことができる
 3. range 検索では隣のリーフ(レコード)も range に収まるかどうかの判定が必要 (オレンジ矢印)
   * **Handler_read_next** でカウントされます
   * 隣のリーフが存在しない/マッチケースでも **Handler_read_next** がカウントされるのに注意。つまり Haandler_read_next は fetch するレコード数と一致しない

#### サンプルクエリ

```sql
# 3,4,5,6 を返す
SELECT * FROM foo WHERE 2 < id and id < 7;

# BETWEEN 使っても同じ
SELECT * FROM foo WHERE id BETWEEN 3 AND 6
```

EXPLAIN では `type = rane` になっています

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
| Handler_read_next     | 4     | # <= 読み取れる行より +1 多い
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

なお `ORDER BY id DESC` にすると ***Handler_read_prev*** がカウントされます (降順にインデックスを辿るため)

----

### Handler_read_first + Handler_read_key + Handler_read_next

![2014-08-25 17 41 00](https://cloud.githubusercontent.com/assets/172456/4027750/d9013dac-2c33-11e4-8ad0-9eaa60984ba6.png)

昇順のフルインデックススキャンのモデルとなります

 1. `id` が最小のキーを見つける
  * **Handler_read_first** と **Handler_read_key** がカウントされる
 2. 範囲指定されていないのでインデックスを総なめする (赤矢印、オレンジ矢印)
   * ***Handler_read_next*** がカウントされる   

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
| Handler_read_next     | 8     | # <= 読み取れる行より +1 多い
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

#### サンプルクエリ

`SELECT id` にしてみるとどうなるか?

```sql
SELECT id FROM foo ORDER BY id ASC
```

```
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra       |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
|  1 | SIMPLE      | foo   | index | NULL          | PRIMARY | 4       | NULL |    8 | Using index |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
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

  * Handler_read_next の数値は一緒だけど **Using index** が出る。
  * セカンダリインデックスの場合は **Covering Index** となっていい感じのはず
    * primary キーの場合はどうなんだっけ? 

## 降順のフルインデックススキャン

InnoDB の primary キーの場合は `フルインデックススキャン = フルテーブルスキャン` に等しいはず

### Handler_read_last + Handler_read_key + Handler_read_prev 

![2014-08-25 17 42 34](https://cloud.githubusercontent.com/assets/172456/4027752/d914d13c-2c33-11e4-949d-807f3d485744.png)

降順のフルインデックススキャンのモデルとなります

 1. `id` が最大のキーを見つける
   * **Handler_read_last** ** と **Handler_read_key** がカウントされる
 2. インデックスを総なめする (赤矢印、オレンジ矢印)
   * **Handler_read_next** がカウントされる

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

## LIMIT + OFFSET

```
SELECT id FROM foo LIMIT 3 OFFSET 5
```

kazeburo さんのエントリにもある通り LIMIT  + OFFSET 検索は効率が良くないことが ***Handler_read_rnd_next*** の数値から読み取れる

```
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
| id | select_type | table | type  | possible_keys | key     | key_len | ref  | rows | Extra       |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
|  1 | SIMPLE      | foo   | index | NULL          | PRIMARY | 4       | NULL |    8 | Using index |
+----+-------------+-------+-------+---------------+---------+---------+------+------+-------------+
```

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 1     |
| Handler_read_key      | 1     |
| Handler_read_last     | 0     |
| Handler_read_next     | 7     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 0     |
| Handler_read_rnd_next | 0     |
+-----------------------+-------+
```

----

## Handler_read_rnd_next

インデックスを貼っていないカラムを指定した場合フルテーブルスキャンになります (*1)

この際に Handler_read_rnd_next がカウントされる様子。InnoDB の場合は primary キーがクラスタインデックスなので、インデックスフルスキャンとフルテーブルスキャンは同一視していいんだっけ?

 * 1) LIMIT で件数絞ったりする場合は例外アリ

#### サンプルクエリ

```sql
SELECT * FROM foo
```

***Handler_read_rnd_next*** しまくりなクエリ。 `ORDER BY id [ASC|DESC]` にするとインデックススキャンになる

```
+----+-------------+-------+------+---------------+------+---------+------+------+-------+
| id | select_type | table | type | possible_keys | key  | key_len | ref  | rows | Extra |
+----+-------------+-------+------+---------------+------+---------+------+------+-------+
|  1 | SIMPLE      | foo   | ALL  | NULL          | NULL | NULL    | NULL |    8 | NULL  |
+----+-------------+-------+------+---------------+------+---------+------+------+-------+
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

####  LIMIT で件数絞る場合

```
SELECT * FROM foo WHERE name = 'aaa' LIMIT 1
```

```
+----+-------------+-------+------+---------------+------+---------+------+------+-------------+
| id | select_type | table | type | possible_keys | key  | key_len | ref  | rows | Extra       |
+----+-------------+-------+------+---------------+------+---------+------+------+-------------+
|  1 | SIMPLE      | foo   | ALL  | NULL          | NULL | NULL    | NULL |    8 | Using where |
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
| Handler_read_rnd_next | 1     |
+-----------------------+-------+
```

 * LIMIT で件数を絞っていると、指定された件数を見つけた段階で探索は終了する
 * LIMIT 分にマッチする行が無ければフルテーブルスキャンになる

いずれにせよ効率は良くない 

----

# ORDER BY RAND()

## Handler_read_rnd, Handler_read_next

#### サンプルクエリ

```sql
SELECT * FROM foo ORDER BY rand()
```

```
+----+-------------+-------+------+---------------+------+---------+------+------+---------------------------------+
| id | select_type | table | type | possible_keys | key  | key_len | ref  | rows | Extra                           |
+----+-------------+-------+------+---------------+------+---------+------+------+---------------------------------+
|  1 | SIMPLE      | foo   | ALL  | NULL          | NULL | NULL    | NULL |    8 | Using temporary; Using filesort |
+----+-------------+-------+------+---------------+------+---------+------+------+---------------------------------+
```

今までの結果と比較すると圧倒的に効率悪いのが **Handler_read_rnd**, **Handler_read_rnd_next** の数値から分かる

```
+-----------------------+-------+
| Variable_name         | Value |
+-----------------------+-------+
| Handler_read_first    | 1     |
| Handler_read_key      | 1     |
| Handler_read_last     | 0     |
| Handler_read_next     | 0     |
| Handler_read_prev     | 0     |
| Handler_read_rnd      | 8     |
| Handler_read_rnd_next | 18    |
+-----------------------+-------+
```
