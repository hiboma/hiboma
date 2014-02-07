# page allocation failure

物理ページ確保にコケた場合に出る warning

 * http://ossmpedia.org/messages/linux/2.6.32-279.EL6/2001379.ja

## /proc/buddyinfo

 * buddyシステムの物理ページのフラグメント状況を確認できる
 * 2の0乗、2の1乗, .... と利用できる連続した物理ページサイズが並ぶ
   * 数値上メモリの空きに余裕があっても連続した物理ページフレームを確保できない場合にコケるケースがある

```
# cat /proc/buddyinfo 
Node 0, zone      DMA      3      2      1      0      2      1      0      0      1      1      3 
Node 0, zone    DMA32    411    424    413    284    161     96     32     14      4      1      0 
Node 0, zone   Normal    150    260    362    209    181    119     30      1      0      0      0 
```

## /proc/sys/vm/min_free_kbytes

 * GFP_ATOMIC なページ割り当てでコケてる場合は、ここのサイズを大きくしておく
   * Ethernetカードからの割り込みコンテキストのドライバ
     * netdev_alloc_skb, __GFP_NOWARN がついてると dump_stack() が出ない?
     * http://mkosaki.blog46.fc2.com/blog-entry-510.html
       * パケットのドロップ
   * http://opensuse-man-ja.berlios.de/opensuse-html/cha.tuning.memory.html

```
rsync: page allocation failure. order:4, mode:0x20
kernel: <IRQ>  [<ffffffff8112c207>] ? __alloc_pages_nodemask+0x757/0x8d0    # ここ
kernel: [<ffffffff81166ab2>] ? kmem_getpages+0x62/0x170
kernel: [<ffffffff811676ca>] ? fallback_alloc+0x1ba/0x270
kernel: [<ffffffff8116711f>] ? cache_grow+0x2cf/0x320
kernel: [<ffffffff81167449>] ? ____cache_alloc_node+0x99/0x160
kernel: [<ffffffff81168610>] ? kmem_cache_alloc_node_trace+0x90/0x200
kernel: [<ffffffff8116882d>] ? __kmalloc_node+0x4d/0x60
kernel: [<ffffffff8143d8cd>] ? __alloc_skb+0x6d/0x190
kernel: [<ffffffff8143e9e6>] ? skb_copy+0x36/0xa0                           # socket buffer のコピー
kernel: [<ffffffffa014127c>] ? tg3_start_xmit+0xa8c/0xd50 [tg3]
kernel: [<ffffffff81448ec8>] ? dev_hard_start_xmit+0x308/0x530
kernel: [<ffffffff8146724a>] ? sch_direct_xmit+0x15a/0x1c0
kernel: [<ffffffff8144cbd0>] ? dev_queue_xmit+0x3b0/0x550
kernel: [<ffffffff814851c0>] ? ip_finish_output+0x0/0x310
kernel: [<ffffffff814852fc>] ? ip_finish_output+0x13c/0x310
kernel: [<ffffffff81485588>] ? ip_output+0xb8/0xc0
kernel: [<ffffffff8148484f>] ? __ip_local_out+0x9f/0xb0
kernel: [<ffffffff81484885>] ? ip_local_out+0x25/0x30
kernel: [<ffffffff81484d60>] ? ip_queue_xmit+0x190/0x420
kernel: [<ffffffff81499a4e>] ? tcp_transmit_skb+0x3fe/0x7b0
kernel: [<ffffffff8149be0b>] ? tcp_write_xmit+0x1fb/0xa20
kernel: [<ffffffff8149c7c0>] ? __tcp_push_pending_frames+0x30/0xe0
kernel: [<ffffffff814942f3>] ? tcp_data_snd_check+0x33/0x100
kernel: [<ffffffff81497efd>] ? tcp_rcv_established+0x3ed/0x800
kernel: [<ffffffff8149fe93>] ? tcp_v4_do_rcv+0x2e3/0x430
kernel: [<ffffffffa01b2557>] ? ipv4_confirm+0x87/0x1d0 [nf_conntrack_ipv4]
kernel: [<ffffffff814a171e>] ? tcp_v4_rcv+0x4fe/0x8d0
kernel: [<ffffffff8147f430>] ? ip_local_deliver_finish+0x0/0x2d0
kernel: [<ffffffff8147f50d>] ? ip_local_deliver_finish+0xdd/0x2d0
kernel: [<ffffffff8147f798>] ? ip_local_deliver+0x98/0xa0
kernel: [<ffffffff8147ec5d>] ? ip_rcv_finish+0x12d/0x440
kernel: [<ffffffff8147f1e5>] ? ip_rcv+0x275/0x350
kernel: [<ffffffff814483bb>] ? __netif_receive_skb+0x4ab/0x750
kernel: [<ffffffff8149ea3a>] ? tcp4_gro_receive+0x5a/0xd0
kernel: [<ffffffff8144a798>] ? netif_receive_skb+0x58/0x60
kernel: [<ffffffff8144a8a0>] ? napi_skb_finish+0x50/0x70
kernel: [<ffffffff8144ce49>] ? napi_gro_receive+0x39/0x50
kernel: [<ffffffffa013dc18>] ? tg3_poll_work+0x788/0xe50 [tg3]
kernel: [<ffffffffa013e32c>] ? tg3_poll_msix+0x4c/0x150 [tg3]                 # tg3
kernel: [<ffffffff8144cf63>] ? net_rx_action+0x103/0x2f0
kernel: [<ffffffff81076fb1>] ? __do_softirq+0xc1/0x1e0
kernel: [<ffffffff810e1720>] ? handle_IRQ_event+0x60/0x170
kernel: [<ffffffff8107700f>] ? __do_softirq+0x11f/0x1e0
kernel: [<ffffffff8100c1cc>] ? call_softirq+0x1c/0x30
kernel: [<ffffffff8100de05>] ? do_softirq+0x65/0xa0
kernel: [<ffffffff81076d95>] ? irq_exit+0x85/0x90
kernel: [<ffffffff81516f15>] ? do_IRQ+0x75/0xf0
kernel: [<ffffffff8100b9d3>] ? ret_from_intr+0x0/0x11
kernel: <EOI>  [<ffffffff8100b00a>] ? system_call_after_swapgs+0x1a/0x6c
```   
   
