
 * os.Stdin, os.Args
   * http://qiita.com/ikawaha/items/28186d965780fab5533d
 * syscall 
   * http://stackoverflow.com/questions/24222999/linux-network-namespaces-unexpected-behavior

```go
func die(args ...string) {
	fmt.Fprintf(os.Stderr, args[0], args[1:])
	os.Exit(1)
}
```

## defer で exit

```go
	var st int
	defer func() { os.Exit(st) }()
```

### 文字列の配列の配列

```go
	whacky := [][]string{
		{"~", "2", "Space"},
		{"a"},
		{"b"},
```

### clang: error: no such file or directory: 'libgcc.a'

 * https://code.google.com/p/go/issues/detail?id=5926
 * CC=clang

### chomp する

   * http://qiita.com/kenjiskywalker/items/c328e39a0029e76e1fc3

### NULL を置換する
   
```go
   strings.Replace(line, string(0), " ", -1)
```   

### リフレクション

 * https://github.com/imdario/mergo/blob/master/mergo.go#L34

