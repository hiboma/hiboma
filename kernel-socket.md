
## sock_create

```c
sock_create(int family, int type, int protocol, struct socket **res)
```

 * net_proto_family の .create に繋がる
 * net_families[(int)] として確保された静的な配列

``` 
struct net_proto_family {
	int		family;
	int		(*create)(struct net *net, struct socket *sock,
				  int protocol, int kern);
	struct module	*owner;
};
```


 