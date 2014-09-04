# ftrace

## 特定のプロセスの `sys_open` 以下の関数グラフを出したい場合

```
/usr/bin/trace-cmd record -P <PID> -p function_graph -g sys_open
```

割り込みハンドラが混ざるので、解析が大変