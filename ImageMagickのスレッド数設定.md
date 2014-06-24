# ImageMagick のスレッド数設定

## MAGICK_THREAD_LIMIT

http://qiita.com/trapple/items/b36c49229b6077fffd74 で紹介されている奴

magick/resource.c を見ると下記の通りの実装になっている

```c
  limit=GetEnvironmentValue("MAGICK_THREAD_LIMIT");
  if (limit != (char *) NULL)
    {
      (void) SetMagickResourceLimit(ThreadResource,StringToSizeType(limit,
        100.0));
      limit=DestroyString(limit);
    }
```

**ThreadResource** がスレッドの並列度の指定らしい

### CentOS6.5

/usr/lib64/ImageMagick-6.5.4/config/policy.xml でスレッド数を指定できる
