## cgrulesengd

Cgroup Rules Engine Daemon

 * シングルプロセス
   * netlink の読み取り、cgroup の書き出しも直列

## 要点   

 * cgre_create_netlink_socket_process_msg
   * socket(PF_NETLINK + SOCK_DGRAM + NETLINK_CONNECTOR)
     * プロセスの fork, exec, setuid, setgid, exit をソケットから read
     * 該当する pid をイベント cgconfig.conf に従って /cgroup に移す
   * - プロセスのイベントと完全に同期している訳ではない
   * - cgrulesengd 起動前のプロセスは対象外
 * cgroup_reload_cached_templates     
   * SIGUSR1 で /etc/cgconfig.conf のキャッシュをリロード
 