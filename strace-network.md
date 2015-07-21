# strace -enetwork でトレースされるシステムコールは?

man を読むと

> -e trace=network
> Trace all the network related system calls.

と説明があるが、具体的にどのシステムコールが対象となるのかについては man には書かれていない

## strace のソース

http://sourceforge.net/projects/strace/

## ソースを追う

適当に `network` で grep して出てきたマクロから追いかける

```c
// defs.h
339:#define TRACE_NETWORK    004    /* Trace network-related syscalls. */
```

TRACE_NETWORK は TN にエイリアスされている。

```c
// syscall.c
75:#define TN TRACE_NETWORK
483:        return TRACE_NETWORK;
```

さらに TN を grep して探していくと、下記のようなテーブルが見つかる。おそらくこのグループが `-enetwork` の対象

```c
// linux/subcall.h
8:[SYS_socket_subcall +  1] = { 3,    IS|TN,        sys_socket,            "socket"        },
9:[SYS_socket_subcall +  2] = { 3,    IS|TN,        sys_bind,            "bind"            },
10:[SYS_socket_subcall +  3] = { 3,    IS|TN,        sys_connect,            "connect"        },
11:[SYS_socket_subcall +  4] = { 2,    IS|TN,        sys_listen,            "listen"        },
12:[SYS_socket_subcall +  5] = { 3,    IS|TN,        sys_accept,            "accept"        },
13:[SYS_socket_subcall +  6] = { 3,    IS|TN,        sys_getsockname,        "getsockname"        },
14:[SYS_socket_subcall +  7] = { 3,    IS|TN,        sys_getpeername,        "getpeername"        },
15:[SYS_socket_subcall +  8] = { 4,    IS|TN,        sys_socketpair,            "socketpair"        },
16:[SYS_socket_subcall +  9] = { 4,    IS|TN,        sys_send,            "send"            },
17:[SYS_socket_subcall + 10] = { 4,    IS|TN,        sys_recv,            "recv"            },
18:[SYS_socket_subcall + 11] = { 6,    IS|TN,        sys_sendto,            "sendto"        },
19:[SYS_socket_subcall + 12] = { 6,    IS|TN,        sys_recvfrom,            "recvfrom"        },
20:[SYS_socket_subcall + 13] = { 2,    IS|TN,        sys_shutdown,            "shutdown"        },
21:[SYS_socket_subcall + 14] = { 5,    IS|TN,        sys_setsockopt,            "setsockopt"        },
22:[SYS_socket_subcall + 15] = { 5,    IS|TN,        sys_getsockopt,            "getsockopt"        },
23:[SYS_socket_subcall + 16] = { 3,    IS|TN,        sys_sendmsg,            "sendmsg"        },
24:[SYS_socket_subcall + 17] = { 3,    IS|TN,        sys_recvmsg,            "recvmsg"        },
25:[SYS_socket_subcall + 18] = { 4,    IS|TN,        sys_accept4,            "accept4"        },
26:[SYS_socket_subcall + 19] = { 5,    IS|TN,        sys_recvmmsg,            "recvmmsg"        },
27:[SYS_socket_subcall + 20] = { 4,    IS|TN,        sys_sendmmsg,            "sendmmsg"        },
```

アーキテクチャごとにもテーブルが用意されていて、どちらを見るのが正確なのかはちょっと分からない。