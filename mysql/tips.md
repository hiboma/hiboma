# mysql の tips

## rpmbuild

#### テストすっ飛ばすやつ

```sh
rpmbuild -bb --define='runselftest 0' rpmbuild/SPECS/mysql.spec
```

```
# http://d.hatena.ne.jp/sh2/20090707
export MYSQL_RPMBUILD_TEST=no
rpmbuild -bb --define='community 1' rpmbuild/SPECS/mysql-*.*.spec
```

テストすっ飛ばす代償は言わずもがななので、RPM作る際の試行錯誤する際にかなー


#### MySQL-community ビルドするやつ

```
rpmbuild --rebuild --define 'community 1' MySQL-community-*.src.rpm
```

#### 5.0系 + CentOS6 の binlog ぶっ壊れるのを回避するやつ

```
export CFLAGS="-O2 -fno-strict-aliasing -g"
export CXXFLAGS="-O2 -fno-strict-aliasing -g"
rpmbuild --rebuild --define 'community 1' MySQL-community-*.src.rpm 
```

refs http://bugs.mysql.com/bug.php?id=48357
