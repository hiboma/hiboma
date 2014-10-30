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

## core_siblings

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
IRQBALANCE_DEBUG=true irqbalance 
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

## see also

 * http://tester7.hatenablog.com/entry/2014/05/22/IvyBridge_%26%26_ESXi_%26%26_CentOS環境でirqbalanceが起動後数秒で終了する問題 