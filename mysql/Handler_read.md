# Handler_read_* のイメージをまとめる

 * 説明の簡略化のために InnoDB の primary key (クラスタインデックス) だけで図にしています
 * セカンダリインデックスも考えると大変そうだ
 * 図は kazeburo さんの http://www.slideshare.net/kazeburo/isucon-summerclass2014action2final をまねて書いています

## Handler_read_first

インデックスの最初のエントリを読み取る

![2014-08-25 16 08 57](https://cloud.githubusercontent.com/assets/172456/4027141/d4d22210-2c28-11e4-8431-79539a60b5cf.png)

## Handler_read_last

インデックスの最後のエントリを読み取る

![2014-08-25 16 10 03](https://cloud.githubusercontent.com/assets/172456/4027136/d4aac26a-2c28-11e4-8e16-105838f6440e.png)

## Handler_read_key

インデックスを使って対象のレコードを見つける

![2014-08-25 16 11 27](https://cloud.githubusercontent.com/assets/172456/4027138/d4b38436-2c28-11e4-8547-05e975bfe499.png)

#### サンプルクエリ

```sql
SELECT * FROM foo WHERE 2 < id and id < 7;
```

## Handler_read_next

 1. Handler_read_key で対象のレコードを見つける
 2. インデックスで昇順に次のレコードを探そうとする
  * 赤矢印部分が ***Handler_read_next*** としてカウントされます
 
![2014-08-25 16 14 29](https://cloud.githubusercontent.com/assets/172456/4027139/d4b7e6a2-2c28-11e4-9a2b-6be5f3674df3.png)

(降順方向だと ***Handler_read_prev*** になります)

## Handler_read_first + Handler_read_next

昇順のフルインデックススキャン

![2014-08-25 16 19 02](https://cloud.githubusercontent.com/assets/172456/4027137/d4aef010-2c28-11e4-8888-c26245c2faa2.png)

```
SELECT * FROM foo ORDER BY id ASC
```

## Handler_read_last + Handler_read_prev

降順のフルインデックススキャン

![2014-08-25 16 21 25](https://cloud.githubusercontent.com/assets/172456/4027140/d4ba0220-2c28-11e4-8eaf-aa359d5a611b.png)

```
SELECT * FROM foo ORDER BY id DESC
```