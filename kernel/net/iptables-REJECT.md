# iptables REJECT

```
iptables -A FORWARD -p TCP --dport 22 -j REJECT --reject-with tcp-reset
```
