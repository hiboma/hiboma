# cgroup

## tasks で ENOSPC

```
Warning: cannot write tid 4185 to /cgroup/cpuset/hetemluser/sandbag//tasks:No space left on device
Warning: cgroup_attach_task_pid failed: 50016
Warning: failed to apply the rule. Error was: 50016
Cgroup change for PID: 4185, UID: 1025, GID: 1000, PROCNAME: /usr/bin/curl FAILED! (Error Code: 50016)
Warning: cannot write tid 4187 to /cgroup/cpuset/hetemluser/sandbag//tasks:No space left on device
```

tasks のエントリポイント

```c
/*
 * for the common functions, 'private' gives the type of file
 */
/* for hysterical raisins, we can't put this on the older files */
#define CGROUP_FILE_GENERIC_PREFIX "cgroup."
static struct cftype files[] = {
	{
		.name = "tasks",
		.open = cgroup_tasks_open,
		.write_u64 = cgroup_tasks_write,
		.release = cgroup_pidlist_release,
		.mode = S_IRUGO | S_IWUSR,
	},
```

cgroup_procs_write で pid を追加する

```c
static int cgroup_procs_write(struct cgroup *cgrp, struct cftype *cft, u64 tgid)
{
	int ret;
	do {
		/*
		 * attach_proc fails with -EAGAIN if threadgroup leadership
		 * changes in the middle of the operation, in which case we need
		 * to find the task_struct for the new leader and start over.
		 */
		ret = attach_task_by_pid(cgrp, tgid, true);
	} while (ret == -EAGAIN);
	return ret;
}
```

attach_task_by_pid

 * vpid
   * Virtual PID ?
   * pid namespace を挟んでいるので PID が実PID かどうか分からない場合に使う

```c
/*
 * Find the task_struct of the task to attach by vpid and pass it along to the
 * function to attach either it or all tasks in its threadgroup. Will take
 * cgroup_mutex; may take task_lock of task.
 */
static int attach_task_by_pid(struct cgroup *cgrp, u64 pid, bool threadgroup)
{
	struct task_struct *tsk;
	const struct cred *cred = current_cred(), *tcred;
	int ret;

	if (!cgroup_lock_live_group(cgrp))
		return -ENODEV;

	if (pid) {
		rcu_read_lock();
		tsk = find_task_by_vpid(pid);
		if (!tsk) {
			rcu_read_unlock();
			cgroup_unlock();
			return -ESRCH;
		}
		if (threadgroup) {
			/*
			 * RCU protects this access, since tsk was found in the
			 * tid map. a race with de_thread may cause group_leader
			 * to stop being the leader, but cgroup_attach_proc will
			 * detect it later.
			 */
			tsk = tsk->group_leader;
		} else if (tsk->flags & PF_EXITING) {
			/* optimization for the single-task-only case */
			rcu_read_unlock();
			cgroup_unlock();
			return -ESRCH;
		}

		/*
		 * even if we're attaching all tasks in the thread group, we
		 * only need to check permissions on one of them.
		 */
		tcred = __task_cred(tsk);
		if (cred->euid &&
		    cred->euid != tcred->uid &&
		    cred->euid != tcred->suid) {
			rcu_read_unlock();
			cgroup_unlock();
			return -EACCES;
		}
		get_task_struct(tsk);
		rcu_read_unlock();
	} else {
		if (threadgroup)
			tsk = current->group_leader;
		else
			tsk = current;
		get_task_struct(tsk);
	}

	if (threadgroup) {
		threadgroup_fork_write_lock(tsk);
		ret = cgroup_attach_proc(cgrp, tsk);
		threadgroup_fork_write_unlock(tsk);
	} else {
		ret = cgroup_attach_task(cgrp, tsk);
	}
	put_task_struct(tsk);
	cgroup_unlock();
	return ret;
}
```

cgroup_attach_proc がごっつい

```c
/**
 * cgroup_attach_proc - attach all threads in a threadgroup to a cgroup
 * @cgrp: the cgroup to attach to
 * @leader: the threadgroup leader task_struct of the group to be attached
 *
 * Call holding cgroup_mutex and the threadgroup_fork_lock of the leader. Will
 * take task_lock of each thread in leader's threadgroup individually in turn.
 */
int cgroup_attach_proc(struct cgroup *cgrp, struct task_struct *leader)
{
	int retval, i, group_size;
	struct cgroup_subsys *ss, *failed_ss = NULL;
	bool cancel_failed_ss = false;
	/* guaranteed to be initialized later, but the compiler needs this */
	struct cgroup *oldcgrp = NULL;
	struct css_set *oldcg;
	struct cgroupfs_root *root = cgrp->root;
	/* threadgroup list cursor and array */
	struct task_struct *tsk;
	struct flex_array *group;
	/*
	 * we need to make sure we have css_sets for all the tasks we're
	 * going to move -before- we actually start moving them, so that in
	 * case we get an ENOMEM we can bail out before making any changes.
	 */
	struct list_head newcg_list;
	struct cg_list_entry *cg_entry, *temp_nobe;

	/*
	 * step 0: in order to do expensive, possibly blocking operations for
	 * every thread, we cannot iterate the thread group list, since it needs
	 * rcu or tasklist locked. instead, build an array of all threads in the
	 * group - threadgroup_fork_lock prevents new threads from appearing,
	 * and if threads exit, this will just be an over-estimate.
	 */
	group_size = get_nr_threads(leader);
	/* flex_array supports very large thread-groups better than kmalloc. */
	group = flex_array_alloc(sizeof(struct task_struct *), group_size,
				 GFP_KERNEL);
	if (!group)
		return -ENOMEM;
	/* pre-allocate to guarantee space while iterating in rcu read-side. */
	retval = flex_array_prealloc(group, 0, group_size - 1, GFP_KERNEL);
	if (retval)
		goto out_free_group_list;

	/* prevent changes to the threadgroup list while we take a snapshot. */
	read_lock(&tasklist_lock);
	if (!thread_group_leader(leader)) {
		/*
		 * a race with de_thread from another thread's exec() may strip
		 * us of our leadership, making while_each_thread unsafe to use
		 * on this task. if this happens, there is no choice but to
		 * throw this task away and try again (from cgroup_procs_write);
		 * this is "double-double-toil-and-trouble-check locking".
		 */
		read_unlock(&tasklist_lock);
		retval = -EAGAIN;
		goto out_free_group_list;
	}
	/* take a reference on each task in the group to go in the array. */
	tsk = leader;
	i = 0;
	do {
		/* as per above, nr_threads may decrease, but not increase. */
		BUG_ON(i >= group_size);
		get_task_struct(tsk);
		/*
		 * saying GFP_ATOMIC has no effect here because we did prealloc
		 * earlier, but it's good form to communicate our expectations.
		 */
		retval = flex_array_put_ptr(group, i, tsk, GFP_ATOMIC);
		BUG_ON(retval != 0);
		i++;
	} while_each_thread(leader, tsk);
	/* remember the number of threads in the array for later. */
	group_size = i;
	read_unlock(&tasklist_lock);

	/*
	 * step 1: check that we can legitimately attach to the cgroup.
	 */
	for_each_subsys(root, ss) {
		if (ss->can_attach) {
			retval = ss->can_attach(ss, cgrp, leader);
			if (retval) {
				failed_ss = ss;
				goto out_cancel_attach;
			}
		}
		/* a callback to be run on every thread in the threadgroup. */
		if (ss->can_attach_task) {
			/* run on each task in the threadgroup. */
			for (i = 0; i < group_size; i++) {
				tsk = flex_array_get_ptr(group, i);
				retval = ss->can_attach_task(cgrp, tsk);
				if (retval) {
					failed_ss = ss;
					cancel_failed_ss = true;
					goto out_cancel_attach;
				}
			}
		}
	}

	/*
	 * step 2: make sure css_sets exist for all threads to be migrated.
	 * we use find_css_set, which allocates a new one if necessary.
	 */
	INIT_LIST_HEAD(&newcg_list);
	for (i = 0; i < group_size; i++) {
		tsk = flex_array_get_ptr(group, i);
		/* nothing to do if this task is already in the cgroup */
		oldcgrp = task_cgroup_from_root(tsk, root);
		if (cgrp == oldcgrp)
			continue;
		/* get old css_set pointer */
		task_lock(tsk);
		if (tsk->flags & PF_EXITING) {
			/* ignore this task if it's going away */
			task_unlock(tsk);
			continue;
		}
		oldcg = tsk->cgroups;
		get_css_set(oldcg);
		task_unlock(tsk);
		/* see if the new one for us is already in the list? */
		if (css_set_check_fetched(cgrp, tsk, oldcg, &newcg_list)) {
			/* was already there, nothing to do. */
			put_css_set(oldcg);
		} else {
			/* we don't already have it. get new one. */
			retval = css_set_prefetch(cgrp, oldcg, &newcg_list);
			put_css_set(oldcg);
			if (retval)
				goto out_list_teardown;
		}
	}

	/*
	 * step 3: now that we're guaranteed success wrt the css_sets, proceed
	 * to move all tasks to the new cgroup, calling ss->attach_task for each
	 * one along the way. there are no failure cases after here, so this is
	 * the commit point.
	 */
	for_each_subsys(root, ss) {
		if (ss->pre_attach)
			ss->pre_attach(cgrp);
	}
	for (i = 0; i < group_size; i++) {
		tsk = flex_array_get_ptr(group, i);
		/* leave current thread as it is if it's already there */
		oldcgrp = task_cgroup_from_root(tsk, root);
		if (cgrp == oldcgrp)
			continue;
		/* if the thread is PF_EXITING, it can just get skipped. */
		retval = cgroup_task_migrate(cgrp, oldcgrp, tsk, true);
		if (retval == 0) {
			/* attach each task to each subsystem */
			for_each_subsys(root, ss) {
				if (ss->attach_task)
					ss->attach_task(cgrp, tsk);
			}
		} else {
			BUG_ON(retval != -ESRCH);
		}
	}
	/* nothing is sensitive to fork() after this point. */

	/*
	 * step 4: do expensive, non-thread-specific subsystem callbacks.
	 * TODO: if ever a subsystem needs to know the oldcgrp for each task
	 * being moved, this call will need to be reworked to communicate that.
	 */
	for_each_subsys(root, ss) {
		if (ss->attach)
			ss->attach(ss, cgrp, oldcgrp, leader);
	}

	/*
	 * step 5: success! and cleanup
	 */
	synchronize_rcu();
	cgroup_wakeup_rmdir_waiter(cgrp);
	retval = 0;
out_list_teardown:
	/* clean up the list of prefetched css_sets. */
	list_for_each_entry_safe(cg_entry, temp_nobe, &newcg_list, links) {
		list_del(&cg_entry->links);
		put_css_set(cg_entry->cg);
		kfree(cg_entry);
	}
out_cancel_attach:
	/* same deal as in cgroup_attach_task */
	if (retval) {
		for_each_subsys(root, ss) {
			if (ss == failed_ss) {
				if (cancel_failed_ss && ss->cancel_attach)
					ss->cancel_attach(ss, cgrp, leader);
				break;
			}
			if (ss->cancel_attach)
				ss->cancel_attach(ss, cgrp, leader);
		}
	}
	/* clean up the array of referenced threads in the group. */
	for (i = 0; i < group_size; i++) {
		tsk = flex_array_get_ptr(group, i);
		put_task_struct(tsk);
	}
out_free_group_list:
	flex_array_free(group);
	return retval;
}
```