

socket を作るカーネル内API を辿る

## sock_create

struct socket を作る

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

 * PF_INET の場合は inet_family_ops 
```c
static struct net_proto_family inet_family_ops = {
	.family = PF_INET,
	.create = inet_create,
	.owner	= THIS_MODULE,
};
```

 * INET なソケットを返す
```
static int inet_create(struct net *net, struct socket *sock, int protocol,
		       int kern)
```               



 