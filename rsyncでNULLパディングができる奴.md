# rsync でファイルの先頭に NULL の padding ができる

 * --partial
 * --append
 * --link-dest

を併用すると意図しない破損が起こる 。もじゃもじゃの人が見つけた

## 再現手順

```sh
rm -rfv /tmp/{src,backup1,backup2}
mkdir /tmp/{src,backup1,backup2}

# 10bytes のファイル作成
echo -n 1234567890 > /tmp/src/aaa.txt

# バックアップ
rsync -av --partial --append /tmp/src/ /tmp/backup1/

# 10bytes 足す
echo -n abcdefghij >> /tmp/src/aaa.txt

# 
rsync -a --partial --append --link-dest /tmp/backup1/ /tmp/src/ /tmp/backup2/

cat -A /tmp/backup2/aaa.txt
