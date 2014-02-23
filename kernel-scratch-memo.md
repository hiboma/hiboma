

 * struct file からファイル名だす

```
filp->f_dentry->d_name.name
```

 * 文字列の長さ strlen