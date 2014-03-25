## setuid(2) return -EAGAIN

```c
/*
 * setuid() is implemented like SysV with SAVED_IDS 
 * 
 * Note that SAVED_ID's is deficient in that a setuid root program
 * like sendmail, for example, cannot set its uid to be a normal 
 * user and then switch back, because if you're root, setuid() sets
 * the saved uid too.  If you don't like this, blame the bright people
 * in the POSIX committee and/or USG.  Note that the BSD-style setreuid()
 * will allow a root program to temporarily drop privileges and be able to
 * regain them by swapping the real and effective uid.  
 */
asmlinkage long sys_setuid(uid_t uid)
{
	int old_euid = current->euid;
	int old_ruid, old_suid, new_ruid, new_suid;
	int retval;

	retval = security_task_setuid(uid, (uid_t)-1, (uid_t)-1, LSM_SETID_ID);
	if (retval)
		return retval;

	old_ruid = new_ruid = current->uid;
	old_suid = current->suid;
	new_suid = old_suid;
	
	if (capable(CAP_SETUID)) {
		if (uid != old_ruid && set_user(uid, old_euid != uid) < 0)
			return -EAGAIN;
		new_suid = uid;
	} else if ((uid != current->uid) && (uid != new_suid))
		return -EPERM;

	if (old_euid != uid)
	{
		current->mm->dumpable = 0;
		wmb();
	}
	current->fsuid = current->euid = uid;
	current->suid = new_suid;

	return security_task_post_setuid(old_ruid, old_euid, old_suid, LSM_SETID_ID);
}
```

```c
static int set_user(uid_t new_ruid, int dumpclear)
{
	struct user_struct *new_user;

	new_user = alloc_uid(new_ruid);
	if (!new_user)
		return -EAGAIN;

	if (atomic_read(&new_user->processes) >=
				current->rlim[RLIMIT_NPROC].rlim_cur &&
			new_user != &root_user) {
		free_uid(new_user);
		return -EAGAIN;
	}

	switch_uid(new_user);

	if(dumpclear)
	{
		current->mm->dumpable = 0;
		wmb();
	}
	current->uid = new_ruid;
	return 0;
}
```

```c
		if (uid != old_ruid && set_user(uid, old_euid != uid) < 0)
			return -EAGAIN;
```

```c
    //
    //	new = kmem_cache_alloc(uid_cachep, SLAB_KERNEL);
    //		if (!new)
	new_user = alloc_uid(new_ruid);
	if (!new_user)
		return -EAGAIN;
```

```c
	if (atomic_read(&new_user->processes) >=
				current->rlim[RLIMIT_NPROC].rlim_cur &&
			new_user != &root_user) {
		free_uid(new_user);
		return -EAGAIN;
	}
```
