
 * syscall 
   * http://stackoverflow.com/questions/24222999/linux-network-namespaces-unexpected-behavior

```go
func die(args ...string) {
	fmt.Fprintf(os.Stderr, args[0], args[1:])
	os.Exit(1)
}
```

```go
	var st int
	defer func() { os.Exit(st) }()
```

```go
	whacky := [][]string{
		{"~", "2", "Space"},
		{"a"},
		{"b"},
```





