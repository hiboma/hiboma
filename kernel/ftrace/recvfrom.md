## recvfrom を ftrace で追う

とある VM + VPN を経由する mysql クライアントの recvfrom(2) が遅い。で `SELECT 1` なクエリを ftrace して取ってみよう

#### 手順

```
cd /sys/kernel/debug/tracing
reecho <mysql の pid> > set_ftrace_pid
echo function_graph > current_tracer

# 別のセッションで `mysql > SELECT 1;` を実行 する

cat trace
```

今回ブロックしている時間が長いのは recvfrom(2) なので、 SYS_recvfrom の部分だけ抜き出す

 * schedule_timeout でコンテキストスイッチした後に、パケットが届いている
   * パケットが届くまでの経過時間が 6ms ほど ( VM + VPN のオーバーヘッド ) 

```
 1)               |  SyS_recvfrom() {
 1)               |    sockfd_lookup_light() {
 1)   0.235 us    |      fget_light();
 1)   0.672 us    |    }
 1)               |    sock_recvmsg() {
 1)               |      security_socket_recvmsg() {
 1)   0.058 us    |        cap_socket_recvmsg();
 1)   0.540 us    |      }
 1)               |      inet_recvmsg() {
 1)               |        tcp_recvmsg() {
 1)               |          lock_sock_nested() {
 1)   0.057 us    |            _cond_resched();
 1)               |            _raw_spin_lock_bh() {
 1)   0.062 us    |              local_bh_disable();
 1)   0.480 us    |            }
 1)   0.058 us    |            _raw_spin_unlock();
 1)   0.088 us    |            local_bh_enable();
 1)   2.450 us    |          }
 1)   0.082 us    |          tcp_cleanup_rbuf();
 1)               |          sk_wait_data() {
 1)               |            prepare_to_wait() {
 1)   0.277 us    |              _raw_spin_lock_irqsave();
 1)   0.073 us    |              _raw_spin_unlock_irqrestore();
 1)   1.166 us    |            }
 1)               |            release_sock() {
 1)               |              _raw_spin_lock_bh() {
 1)   0.062 us    |                local_bh_disable();
 1)   0.490 us    |              }
 1)   0.060 us    |              tcp_release_cb();
 1)               |              _raw_spin_unlock_bh() {
 1)   0.089 us    |                local_bh_enable_ip();
 1)   0.500 us    |              }
 1)   2.262 us    |            }
 1)               |            schedule_timeout() {
 1)               |              schedule() {
 1)               |                __schedule() {
 1)   0.060 us    |                  rcu_note_context_switch();
 1)   0.066 us    |                  _raw_spin_lock_irq();
 1)               |                  deactivate_task() {
 1)               |                    dequeue_task() {
 1)               |                      update_rq_clock.part.74() {
 1)   0.078 us    |                        kvm_steal_clock();
 1)   0.707 us    |                      }
 1)               |                      dequeue_task_fair() {
 1)               |                        dequeue_entity() {
 1)               |                          update_curr() {
 1)   0.106 us    |                            update_min_vruntime();
 1)   0.153 us    |                            cpuacct_charge();
 1)   1.493 us    |                          }
 1)   0.099 us    |                          update_cfs_rq_blocked_load();
 1)   0.073 us    |                          clear_buddies();
 1)   0.141 us    |                          account_entity_dequeue();
 1)   0.095 us    |                          update_min_vruntime();
 1)   0.144 us    |                          update_cfs_shares();
 1)   5.238 us    |                        }
 1)   0.072 us    |                        hrtick_update();
 1)   6.470 us    |                      }
 1)   8.201 us    |                    }
 1)   8.647 us    |                  }
 1)   0.132 us    |                  put_prev_task_fair();
 1)               |                  pick_next_task_fair() {
 1)   0.087 us    |                    clear_buddies();
 1)   0.297 us    |                    __dequeue_entity();
 1)   2.000 us    |                  }
 1)   0.120 us    |                  finish_task_switch();                # ここでコンテキストスイッチしている
                                                                          # パケットが到着するまで待つ
                                                                          # パケットが届くまでで 6025.261 us = 6ms ほど経過している
 1) ! 6025.261 us |                }
 1) ! 6025.865 us |              }
 1) ! 6026.480 us |            }
 1)               |            lock_sock_nested() {
 1)   0.059 us    |              _cond_resched();
 1)               |              _raw_spin_lock_bh() {
 1)   0.058 us    |                local_bh_disable();
 1)   0.507 us    |              }
 1)   0.058 us    |              _raw_spin_unlock();
 1)   0.083 us    |              local_bh_enable();
 1)   2.823 us    |            }
 1)   0.081 us    |            finish_wait();
 1) ! 6035.833 us |          }
 1)               |          tcp_prequeue_process() {
 1)   0.058 us    |            local_bh_disable();
 1)               |            tcp_v4_do_rcv() {
 1)   0.087 us    |              ipv4_dst_check();
 1)               |              tcp_rcv_established() {
 1)   0.060 us    |                tcp_parse_aligned_timestamp.part.38();
 1)   0.069 us    |                local_bh_enable();
 1)               |                skb_copy_datagram_iovec() {
 1)   0.062 us    |                  _cond_resched();
 1)   0.945 us    |                }
 1)   0.200 us    |                tcp_rcv_space_adjust();
 1)   0.060 us    |                local_bh_disable();
 1)   0.060 us    |                get_seconds();
 1)   0.267 us    |                tcp_event_data_recv();
 1)               |                tcp_ack() {
 1)               |                  __kfree_skb() {
 1)               |                    skb_release_all() {
 1)   0.085 us    |                      skb_release_head_state();
 1)               |                      skb_release_data() {
 1)               |                        skb_free_head() {
 1)   0.255 us    |                          kfree();
 1)   0.786 us    |                        }
 1)   1.253 us    |                      }
 1)   2.133 us    |                    }
 1)               |                    kfree_skbmem() {
 1)   0.135 us    |                      kmem_cache_free();
 1)   0.600 us    |                    }
 1)   3.753 us    |                  }
 1)   0.059 us    |                  jiffies_to_usecs();
 1)   0.067 us    |                  usecs_to_jiffies();
 1)   0.070 us    |                  tcp_rearm_rto();
 1)   0.070 us    |                  tcp_check_reno_reordering();
 1)   0.083 us    |                  bictcp_acked();
 1)   0.082 us    |                  bictcp_cong_avoid();
 1)   7.876 us    |                }
 1)   0.085 us    |                tcp_check_space();
 1)               |                __tcp_ack_snd_check() {
 1)               |                  tcp_send_ack() {
 1)               |                    __alloc_skb() {
 1)   0.122 us    |                      kmem_cache_alloc_node();
 1)               |                      __kmalloc_reserve.isra.30() {
 1)               |                        __kmalloc_node_track_caller() {
 1)   0.069 us    |                          kmalloc_slab();
 1)   0.836 us    |                        }
 1)   1.269 us    |                      }
 1)   0.270 us    |                      ksize();
 1)   2.907 us    |                    }
 1)               |                    tcp_transmit_skb() {
 1)               |                      tcp_established_options() {
 1)               |                        tcp_v4_md5_lookup() {
 1)   0.058 us    |                          tcp_md5_do_lookup();
 1)   0.485 us    |                        }
 1)   0.932 us    |                      }
 1)   0.060 us    |                      skb_push();
 1)   0.064 us    |                      __tcp_select_window();
 1)   0.060 us    |                      tcp_options_write();
 1)               |                      tcp_v4_send_check() {
 1)   0.090 us    |                        __tcp_v4_send_check();
 1)   0.520 us    |                      }
 1)               |                      ip_queue_xmit() {
 1)               |                        __sk_dst_check() {
 1)   0.061 us    |                          ipv4_dst_check();
 1)   0.488 us    |                        }
 1)   0.060 us    |                        skb_push();
 1)               |                        ip_local_out_sk() {
 1)               |                          __ip_local_out_sk() {
 1)               |                            nf_hook_slow() {
 1)               |                              nf_iterate() {
 1)               |                                iptable_filter_hook [iptable_filter]() {
 1)               |                                  ipt_do_table [ip_tables]() {
 1)   0.060 us    |                                    local_bh_disable();
 1)   0.080 us    |                                    local_bh_enable();
 1)   1.220 us    |                                  }
 1)   1.690 us    |                                }
 1)   2.190 us    |                              }
 1)   2.616 us    |                            }
 1)   3.058 us    |                          }
 1)               |                          ip_output() {
 1)               |                            ip_finish_output() {
 1)   0.076 us    |                              ipv4_mtu();
 1)   0.060 us    |                              local_bh_disable();
 1)   0.060 us    |                              skb_push();
 1)               |                              dev_queue_xmit() {
 1)   0.058 us    |                                local_bh_disable();
 1)   0.092 us    |                                netdev_pick_tx();
 1)   0.061 us    |                                _raw_spin_lock();
 1)               |                                validate_xmit_skb.part.86() {
 1)               |                                  netif_skb_features() {
 1)   0.065 us    |                                    skb_network_protocol();
 1)   0.620 us    |                                  }
 1)   1.098 us    |                                }
 1)               |                                sch_direct_xmit() {
 1)   0.060 us    |                                  _raw_spin_unlock();
 1)   0.062 us    |                                  _raw_spin_lock();
 1)               |                                  dev_hard_start_xmit() {
 1)               |                                    start_xmit [virtio_net]() {
 1)               |                                      free_old_xmit_skbs.isra.31 [virtio_net]() {
 1)               |                                        virtqueue_get_buf [virtio_ring]() {
 1)               |                                          detach_buf [virtio_ring]() {
 1)   0.177 us    |                                            kfree();
 1)   0.710 us    |                                          }
 1)   1.173 us    |                                        }
 1)               |                                        __dev_kfree_skb_any() {
 1)               |                                          consume_skb() {
 1)               |                                            skb_release_all() {
 1)   0.099 us    |                                              skb_release_head_state();
 1)               |                                              skb_release_data() {
 1)               |                                                skb_free_head() {
 1)   0.105 us    |                                                  kfree();
 1)   0.586 us    |                                                }
 1)   1.156 us    |                                              }
 1)   2.016 us    |                                            }
 1)               |                                            kfree_skbmem() {
 1)               |                                        __dev_kfree_skb_any() {
 1)               |                                          consume_skb() {
 1)               |                                            skb_release_all() {
 1)   0.099 us    |                                              skb_release_head_state();
 1)               |                                              skb_release_data() {
 1)               |                                                skb_free_head() {
 1)   0.105 us    |                                                  kfree();
 1)   0.586 us    |                                                }
 1)   1.156 us    |                                              }
 1)   2.016 us    |                                            }
 1)               |                                            kfree_skbmem() {
 1)   0.101 us    |                                              kmem_cache_free();
 1)   0.543 us    |                                            }
 1)   3.318 us    |                                          }
 1)   3.757 us    |                                        }
 1)   0.077 us    |                                        virtqueue_get_buf [virtio_ring]();
 1)   6.173 us    |                                      }
 1)               |                                      skb_to_sgvec() {
 1)   0.070 us    |                                        __skb_to_sgvec();
 1)   0.520 us    |                                      }
 1)               |                                      virtqueue_add_outbuf [virtio_ring]() {
 1)               |                                        alloc_indirect.isra.4 [virtio_ring]() {
 1)               |                                          __kmalloc() {
 1)   0.097 us    |                                            kmalloc_slab();
 1)   0.585 us    |                                          }
 1)   1.030 us    |                                        }
 1)   1.570 us    |                                      }
 1)   0.065 us    |                                      sock_wfree();
 1)               |                                      virtqueue_kick [virtio_ring]() {
 1)   0.093 us    |                                        virtqueue_kick_prepare [virtio_ring]();
 1)   5.866 us    |                                        vp_notify [virtio_pci]();
 1)   6.904 us    |                                      }
 1) + 17.381 us   |                                    }
 1) + 17.880 us   |                                  }
 1)   0.060 us    |                                  _raw_spin_unlock();
 1)   0.060 us    |                                  _raw_spin_lock();
 1) + 20.085 us   |                                }
 1)   0.058 us    |                                _raw_spin_unlock();
 1)   0.068 us    |                                local_bh_enable();
 1) + 25.151 us   |                              }
 1)   0.090 us    |                              local_bh_enable();
 1) + 27.734 us   |                            }
 1) + 28.301 us   |                          }
 1) + 32.289 us   |                        }
 1) + 35.114 us   |                      }
 1) + 39.282 us   |                    }
 1) + 43.063 us   |                  }
 1) + 43.640 us   |                }
               |                kfree_skb_partial() {
 1)               |                  skb_release_all() {
 1)   0.063 us    |                    skb_release_head_state();
 1)               |                    skb_release_data() {
 1)               |                      put_page() {
 1)               |                        __put_single_page() {
 1)               |                          free_hot_cold_page() {
 1)   0.090 us    |                            free_pages_prepare();
 1)   0.132 us    |                            get_pageblock_flags_group();
 1)   1.131 us    |                          }
 1)   1.580 us    |                        }
 1)   2.103 us    |                      }
 1)               |                      skb_free_head() {
 1)               |                        put_page() {
 1)   0.064 us    |                          put_compound_page();
 1)   0.495 us    |                        }
 1)   1.012 us    |                      }
 1)   3.971 us    |                    }
 1)   4.793 us    |                  }
 1)               |                  kfree_skbmem() {
 1)   0.085 us    |                    kmem_cache_free();
 1)   0.510 us    |                  }
 1)   6.064 us    |                }
 1)   0.111 us    |                sock_def_readable();
 1) + 64.584 us   |              }
 1) + 65.568 us   |            }
 1)   0.079 us    |            local_bh_enable();
 1) + 66.997 us   |          }
 1)   0.100 us    |          tcp_cleanup_rbuf();
 1)               |          release_sock() {
 1)               |            _raw_spin_lock_bh() {
 1)   0.058 us    |              local_bh_disable();
 1)   0.482 us    |            }
 1)   0.066 us    |            tcp_release_cb();
 1)               |            _raw_spin_unlock_bh() {
 1)   0.105 us    |              local_bh_enable_ip();
 1)   0.562 us    |            }
 1)   2.347 us    |          }
 1) ! 6110.776 us |        }
 1) ! 6111.307 us |      }
 1) ! 6113.054 us |    }
 1) ! 6114.798 us |  }
```
