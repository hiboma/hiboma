# irqbalance

## CentOS on VirtualBox + OS X + Macbook Pro 強制的に one shot モードになる

下記のコードが原因

```
	/* On dual core/hyperthreading shared cache systems just do a one shot setup */
	if (cache_domain_count==1)
		one_shot_mode = 1;
```

理由は下記の通り

> The purpose of irqbalance is to distribute interrupts accross cpus in an smp system such that cache-domain affinity is maximized for each irq. In other words, irqbalance tries to assign irqs to cpu cores such that each irq stands a greater chance of having its interrupt handler be in cache when the irq is asserted to the cpu. This raises a few interesting cases in which the behavior of irqbalance may be non-intuitive. Most notably, cases in which a system has only one cache domain. Nominally these systems are only single cpu environments, but can also be found in multi-core environments in which the cores share an L2 cache. In these situations irqbalance will exit immediately, since there is no work that irqbalance can do which will improve interrupt handling performance. This is normal and not cause for concern. For more information regarding irqbalance, please visit http://irqbalance.org/ 
 * **Cache Domain**
   * L2キャッシュを共有しているコア群?

CPU を cache domain に追加するコード

 * cache->mask の違い = cache domain の違い

```c
static struct topo_obj* add_cpu_to_cache_domain(struct topo_obj *cpu,
						    cpumask_t cache_mask)
{
	GList *entry;
	struct topo_obj *cache;
	struct topo_obj *lcpu;

	entry = g_list_first(cache_domains);

	while (entry) {
		cache = entry->data;
        /* キャッシュマスクが違う = cache domain が違う */
		if (cpus_equal(cache_mask, cache->mask))
			break;
		entry = g_list_next(entry);
	}

	if (!entry) {
		cache = calloc(sizeof(struct topo_obj), 1);
		if (!cache)
			return NULL;
		cache->obj_type = OBJ_TYPE_CACHE;
		cache->mask = cache_mask;
		cache->number = cache_domain_count;
		cache->obj_type_list = &cache_domains;
		cache_domains = g_list_append(cache_domains, cache);
		cache_domain_count++;
	}
```

## core_siblings, thread_siblings

```
/sys/devices/system/cpu/cpu0/topology
/sys/devices/system/cpu/cpu0/topology/physical_package_id
/sys/devices/system/cpu/cpu0/topology/core_id
/sys/devices/system/cpu/cpu0/topology/thread_siblings
/sys/devices/system/cpu/cpu0/topology/thread_siblings_list
/sys/devices/system/cpu/cpu0/topology/core_siblings
/sys/devices/system/cpu/cpu0/topology/core_siblings_list
/sys/devices/system/cpu/cpu1/topology
/sys/devices/system/cpu/cpu1/topology/physical_package_id
/sys/devices/system/cpu/cpu1/topology/core_id
/sys/devices/system/cpu/cpu1/topology/thread_siblings
/sys/devices/system/cpu/cpu1/topology/thread_siblings_list
/sys/devices/system/cpu/cpu1/topology/core_siblings
/sys/devices/system/cpu/cpu1/topology/core_siblings_list
```

https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-devices-system-cpu

```
		core_siblings: internal kernel map of cpu#'s hardware threads
		within the same physical_package_id.

		core_siblings_list: human-readable list of the logical CPU
		numbers within the same physical_package_id as cpu#.

//...        

		thread_siblings: internel kernel map of cpu#'s hardware
		threads within the same core as cpu#

		thread_siblings_list: human-readable list of cpu#'s hardware
		threads within the same core as cpu#
```

とあるホストの irqbalance 見ると、 Cache domain と thread_siblings が一致している様子

```
# cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list
0,12
1,13
10,22
11,23
0,12
1,13
2,14
3,15
4,16
5,17
6,18
7,19
2,14
8,20
9,21
10,22
11,23
3,15
4,16
5,17
6,18
7,19
8,20
9,21

# IRQBALANCE_DEBUG=true irqbalance 
Package 0:  cpu mask is 0003f03f (workload 0)
        Cache domain 0: cpu mask is 00001001  (workload 0) 
                CPU number 0  (workload 0)
                CPU number 12  (workload 0)
        Cache domain 1: cpu mask is 00002002  (workload 0) 
                CPU number 1  (workload 0)
                CPU number 13  (workload 0)
        Cache domain 2: cpu mask is 00004004  (workload 0) 
                CPU number 2  (workload 0)
                CPU number 14  (workload 0)
        Cache domain 3: cpu mask is 00008008  (workload 0) 
                CPU number 3  (workload 0)
                CPU number 15  (workload 0)
        Cache domain 4: cpu mask is 00010010  (workload 0) 
                CPU number 4  (workload 0)
                CPU number 16  (workload 0)
        Cache domain 5: cpu mask is 00020020  (workload 0) 
                CPU number 5  (workload 0)
                CPU number 17  (workload 0)
Package 6:  cpu mask is 00fc0fc0 (workload 0)
        Cache domain 6: cpu mask is 00040040  (workload 0) 
                CPU number 6  (workload 0)
                CPU number 18  (workload 0)
        Cache domain 7: cpu mask is 00080080  (workload 0) 
                CPU number 7  (workload 0)
                CPU number 19  (workload 0)
        Cache domain 8: cpu mask is 00100100  (workload 0) 
                CPU number 8  (workload 0)
                CPU number 20  (workload 0)
        Cache domain 9: cpu mask is 00200200  (workload 0) 
                CPU number 9  (workload 0)
                CPU number 21  (workload 0)
        Cache domain 10: cpu mask is 00400400  (workload 0) 
                CPU number 10  (workload 0)
                CPU number 22  (workload 0)
        Cache domain 11: cpu mask is 00800800  (workload 0) 
                CPU number 11  (workload 0)
                CPU number 23  (workload 0)
```

だが、Vagrant だと違う。ので、他のパラメータもみないと駄目なのだろうか

```
[vagrant@ ~]$ cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list
0
1
2
3
[vagrant@ ~]$ IRQBALANCE_DEBUG=true irqbalance 
Package 0:  numa_node is 0 cpu mask is 0000000f (load 0)
        Cache domain 0:  numa_node is 0 cpu mask is 0000000f  (load 0) 
                CPU number 0  numa_node is 0 (load 0)
                CPU number 1  numa_node is 0 (load 0)
                CPU number 2  numa_node is 0 (load 0)
                CPU number 3  numa_node is 0 (load 0)
Adding IRQ 11 to database
Adding IRQ 19 to database
Adding IRQ 20 to database
Adding IRQ 9 to database
Adding IRQ 16 to database
NUMA NODE NUMBER: -1
LOCAL CPU MASK: ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff,ffffffff

NUMA NODE NUMBER: 0
LOCAL CPU MASK: 0000000f
```

shared_cpu_map も見ているので、こっちを見るのが正しそう

 * online
 * core_siblings (1コアにいる論理CPUの数)
 * index1/shared_cpu_map (1次キャッシュ)
 * index2/shared_cpu_map (2次キャッシュ)

```c
	/* skip offline cpus */
	snprintf(new_path, PATH_MAX, "%s/online", path);
	file = fopen(new_path, "r");
	if (file) {
		char *line = NULL;
		size_t size = 0;
		if (getline(&line, &size, file)==0)
			return;
		fclose(file);
		if (line && line[0]=='0') {
			free(line);
			return;
		}
		free(line);
	}

	cpu = calloc(sizeof(struct topo_obj), 1);
	if (!cpu)
		return;

	cpu->obj_type = OBJ_TYPE_CPU;

	cpu->number = strtoul(&path[27], NULL, 10);

	cpu_set(cpu->number, cpu_possible_map);
	
	cpu_set(cpu->number, cpu->mask);

	/*
 	 * Default the cache_domain mask to be equal to the cpu
 	 */
	cpus_clear(cache_mask);
	cpu_set(cpu->number, cache_mask);

	/* if the cpu is on the banned list, just don't add it */
	if (cpus_intersects(cpu->mask, banned_cpus)) {
		free(cpu);
		/* even though we don't use the cpu we do need to count it */
		core_count++;
		return;
	}

	/* try to read the package mask; if it doesn't exist assume solitary */
	snprintf(new_path, PATH_MAX, "%s/topology/core_siblings", path);
	file = fopen(new_path, "r");
	cpu_set(cpu->number, package_mask);
	if (file) {
		char *line = NULL;
		size_t size = 0;
		if (getline(&line, &size, file)) 
			cpumask_parse_user(line, strlen(line), package_mask);
		fclose(file);
		free(line);
	}

	/* try to read the cache mask; if it doesn't exist assume solitary */
	/* We want the deepest cache level available so try index1 first, then index2 */
	cpu_set(cpu->number, cache_mask);
	snprintf(new_path, PATH_MAX, "%s/cache/index1/shared_cpu_map", path);
	file = fopen(new_path, "r");
	if (file) {
		char *line = NULL;
		size_t size = 0;
		if (getline(&line, &size, file)) 
			cpumask_parse_user(line, strlen(line), cache_mask);
		fclose(file);
		free(line);
	}
	snprintf(new_path, PATH_MAX, "%s/cache/index2/shared_cpu_map", path);
	file = fopen(new_path, "r");
	if (file) {
		char *line = NULL;
		size_t size = 0;
		if (getline(&line, &size, file)) 
			cpumask_parse_user(line, strlen(line), cache_mask);
		fclose(file);
		free(line);
	}
```


```
[vagrant@ ~]$ cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list
0
1
2
3
[vagrant@ ~]$ cat /sys/devices/system/cpu/cpu*/cache/index1/shared_cpu_map | sort -ru
8
4
2
1
[vagrant@ ~]$ cat /sys/devices/system/cpu/cpu*/cache/index2/shared_cpu_map | sort -ru
f
```

```
# cat /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | sort -n
0,12
0,12
1,13
1,13
2,14
2,14
3,15
3,15
4,16
4,16
5,17
5,17
6,18
6,18
7,19
7,19
8,20
8,20
9,21
9,21
10,22
10,22
11,23
11,23
# cat /sys/devices/system/cpu/cpu*/cache/index1/shared_cpu_map | sort -nu
001001
002002
004004
008008
010010
020020
040040
080080
100100
200200
400400
800800
# cat /sys/devices/system/cpu/cpu*/cache/index2/shared_cpu_map | sort -nu
001001
002002
004004
008008
010010
020020
040040
080080
100100
200200
400400
800800
```

index の番号 = N次キャッシュ となる。 2次キャッシュ 

## see also

 * http://tester7.hatenablog.com/entry/2014/05/22/IvyBridge_%26%26_ESXi_%26%26_CentOS環境でirqbalanceが起動後数秒で終了する問題 