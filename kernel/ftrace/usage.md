# ftrace

## 特定のプロセスの `sys_open` 以下の関数グラフを出したい場合

```
/usr/bin/trace-cmd record -P <PID> -p function_graph -g sys_open
```

割り込みハンドラのグラフが混ざるので、解析が大変。割り込みコンテキストを無視する方法はないか?

```
version = 6
CPU 0 is empty
cpus=2
            ruby-2564  [001] 107227.460641: funcgraph_entry:        7.076 us   |  __math_state_restore();
            ruby-2564  [001] 107227.460779: funcgraph_entry:                   |  sys_open() {
            ruby-2564  [001] 107227.460783: funcgraph_entry:                   |    do_sys_open() {
            ruby-2564  [001] 107227.460786: funcgraph_entry:                   |      getname() {
            ruby-2564  [001] 107227.460790: funcgraph_entry:                   |        kmem_cache_alloc() {
            ruby-2564  [001] 107227.460794: funcgraph_entry:        3.518 us   |          _cond_resched();
            ruby-2564  [001] 107227.460801: funcgraph_exit:       + 11.065 us  |        }
            ruby-2564  [001] 107227.460805: funcgraph_entry:                   |        strncpy_from_user() {
            ruby-2564  [001] 107227.460808: funcgraph_entry:        3.475 us   |          _cond_resched();
            ruby-2564  [001] 107227.460815: funcgraph_exit:       + 10.427 us  |        }
            ruby-2564  [001] 107227.460818: funcgraph_exit:       + 32.205 us  |      }
            ruby-2564  [001] 107227.460822: funcgraph_entry:                   |      alloc_fd() {
            ruby-2564  [001] 107227.460826: funcgraph_entry:        3.579 us   |        _spin_lock();
            ruby-2564  [001] 107227.460833: funcgraph_entry:        3.837 us   |        expand_files();
            ruby-2564  [001] 107227.460849: funcgraph_exit:       + 26.352 us  |      }
            ruby-2564  [001] 107227.460852: funcgraph_entry:                   |      do_filp_open() {
            ruby-2564  [001] 107227.460856: funcgraph_entry:                   |        path_init() {
            ruby-2564  [001] 107227.460859: funcgraph_entry:        3.773 us   |          _read_lock();
            ruby-2564  [001] 107227.460867: funcgraph_exit:       + 11.066 us  |        }
            ruby-2564  [001] 107227.460870: funcgraph_entry:                   |        path_walk() {
            ruby-2564  [001] 107227.460874: funcgraph_entry:                   |          __link_path_walk() {
            ruby-2564  [001] 107227.460878: funcgraph_entry:                   |            acl_permission_check() {
            ruby-2564  [001] 107227.460882: funcgraph_entry:                   |              ext4_check_acl() {
            ruby-2564  [001] 107227.460885: funcgraph_entry:        3.714 us   |                ext4_get_acl();
            ruby-2564  [001] 107227.460892: funcgraph_exit:       + 10.805 us  |              }
            ruby-2564  [001] 107227.460896: funcgraph_entry:                   |              in_group_p() {
            ruby-2564  [001] 107227.460900: funcgraph_entry:        3.661 us   |                groups_search();
            ruby-2564  [001] 107227.460907: funcgraph_exit:       + 10.770 us  |              }
            ruby-2564  [001] 107227.460910: funcgraph_exit:       + 32.474 us  |            }
            ruby-2564  [001] 107227.460914: funcgraph_entry:                   |            security_inode_permission() {
            ruby-2564  [001] 107227.460918: funcgraph_entry:        3.712 us   |              cap_inode_permission();
            ruby-2564  [001] 107227.460925: funcgraph_exit:       + 11.082 us  |            }
            ruby-2564  [001] 107227.460929: funcgraph_entry:                   |            do_lookup() {
            ruby-2564  [001] 107227.460933: funcgraph_entry:                   |              __d_lookup() {
            ruby-2564  [001] 107227.460937: funcgraph_entry:        3.473 us   |                _spin_lock();
            ruby-2564  [001] 107227.460944: funcgraph_exit:       + 11.167 us  |              }
            ruby-2564  [001] 107227.460947: funcgraph_entry:        3.482 us   |              follow_managed();
            ruby-2564  [001] 107227.460954: funcgraph_exit:       + 25.570 us  |            }
            ruby-2564  [001] 107227.460958: funcgraph_entry:        3.536 us   |            dput();
            -------------------------------------------------------------------------------------------------------------- # ここからタイマ割り込み
            ruby-2564  [001] 107227.460970: funcgraph_entry:                   |              smp_apic_timer_interrupt() {
            ruby-2564  [001] 107227.460973: funcgraph_entry:      + 10.453 us  |                native_apic_mem_write();
            ruby-2564  [001] 107227.460987: funcgraph_entry:        3.486 us   |                exit_idle();
            ruby-2564  [001] 107227.460994: funcgraph_entry:                   |                irq_enter() {
            ruby-2564  [001] 107227.460998: funcgraph_entry:        3.483 us   |                  rcu_irq_enter();
            ruby-2564  [001] 107227.461005: funcgraph_entry:        3.490 us   |                  idle_cpu();
            ruby-2564  [001] 107227.461012: funcgraph_exit:       + 17.409 us  |                }
            -------------------------------------------------------------------------------------------------------------- # ここから locall APIC のタイマ割り込み
            ruby-2564  [001] 107227.461015: funcgraph_entry:                   |                local_apic_timer_interrupt() {
            ruby-2564  [001] 107227.461019: funcgraph_entry:                   |                  hrtimer_interrupt() {
            ruby-2564  [001] 107227.461022: funcgraph_entry:        3.494 us   |                    _spin_lock();
            ruby-2564  [001] 107227.461029: funcgraph_entry:                   |                    ktime_get_update_offsets() {
            ruby-2564  [001] 107227.461033: funcgraph_entry:        5.373 us   |                      acpi_pm_read();
            ruby-2564  [001] 107227.461041: funcgraph_exit:       + 12.334 us  |                    }
            ....
```