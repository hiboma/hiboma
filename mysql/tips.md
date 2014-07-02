# mysql の tips

## rpmbuild

テストすっ飛ばすやつ

```sh
rpmbuild -bb --define='runselftest 0' rpmbuild/SPECS/mysql.spec
```

テストすっ飛ばす代償は言わずもがななので、RPM作る際の試行錯誤する際にかなー
