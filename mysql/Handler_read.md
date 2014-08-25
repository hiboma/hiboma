# Handler_read_* のイメージをまとめる

 * 説明の簡略化のために InnoDB の primary key (クラスタインデックス) だけで図にしています
 * セカンダリインデックスも考えると大変そうだ
 * 図は kazeburo さんの http://www.slideshare.net/kazeburo/isucon-summerclass2014action2final をまねて書いています

## Handler_read_first

インデックスの最初のエントリを読み取る

![2014-08-25 16 08 57](https://cloud.githubusercontent.com/assets/172456/4027141/d4d22210-2c28-11e4-8431-79539a60b5cf.png)

昇順で (フル)インデックススキャン する際に ***Handler_read_next*** と一緒に使われる

## Handler_read_last

インデックスの最後のエントリを読み取る

![2014-08-25 16 10 03](https://cloud.githubusercontent.com/assets/172456/4027136/d4aac26a-2c28-11e4-8e16-105838f6440e.png)

降順で (フル)インデックススキャン する際に ***Handler_read_prev*** と一緒に使われるはず

## Handler_read_key

インデックスを使って対象のレコードを見つける

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

#### WHERE in (?) を使った場合

![2014-08-25 16 53 57](https://cloud.githubusercontent.com/assets/172456/4027552/ac6a6334-2c30-11e4-804e-1f027be9d0a1.png)

```sql
SELECT * FROM foo WHERE id in (2,4,6,8)
```

 * おっと予想に反した動作になってしまった
 * `in` に指定したレコード数が、テーブル全体のレコード数の半数に達しているのでオプティマイザがテーブルスキャンを選択したか?

## Handler_read_next

 1. Handler_read_key で対象のレコードを見つける
 2. インデックスで昇順に次のレコードを探そうとする
  * 赤矢印部分が ***Handler_read_next*** としてカウントされます

![2014-08-25 17 04 34](https://cloud.githubusercontent.com/assets/172456/4027542/71396b48-2c30-11e4-9d76-96a678c695a3.png)

#### サンプルクエリ

```sql
SELECT * FROM foo WHERE 2 < id and id < 7;
```

(降順方向だと ***Handler_read_prev*** になります)

## Handler_read_first + Handler_read_key + Handler_read_next

昇順のフルインデックススキャン

![2014-08-25 16 19 02](https://cloud.githubusercontent.com/assets/172456/4027137/d4aef010-2c28-11e4-8888-c26245c2faa2.png)

```sql
SELECT * FROM foo ORDER BY id ASC
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

![2014-08-25 16 21 25](https://cloud.githubusercontent.com/assets/172456/4027140/d4ba0220-2c28-11e4-8eaf-aa359d5a611b.png)

```sh
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

