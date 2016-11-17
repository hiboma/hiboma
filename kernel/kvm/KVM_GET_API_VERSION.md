# KVM_GET_API_VERSION

https://kernel.org/doc/Documentation/virtual/kvm/api.txt

```
4.1 KVM_GET_API_VERSION

Capability: basic
Architectures: all
Type: system ioctl
Parameters: none
Returns: the constant KVM_API_VERSION (=12)

This identifies the API version as the stable kvm API. It is not
expected that this number will change.  However, Linux 2.6.20 and
2.6.21 report earlier versions; these are not documented and not
supported.  Applications should refuse to run if KVM_GET_API_VERSION
returns a value other than 12.  If this check passes, all ioctls
described as 'basic' will be available.
```

## 定義

```c
#define KVM_GET_API_VERSION       _IO(KVMIO,   0x00)
```

## ioctl の実装

```c
static long kvm_dev_ioctl(struct file *filp,
			  unsigned int ioctl, unsigned long arg)
{
	long r = -EINVAL;

	switch (ioctl) {
	case KVM_GET_API_VERSION:
		if (arg)
			goto out;
		r = KVM_API_VERSION;
		break;

...

out:
	return r;
}
```

**KVM_API_VERSION = 12** を返しているだけ。非常にシンプルな API 

```c
#define KVM_API_VERSION 12
```

## qemu/kvm-all.c

qemu の中では下記のような使われ方をしている

```c
static int kvm_init(MachineState *ms)
{
    MachineClass *mc = MACHINE_GET_CLASS(ms);
    static const char upgrade_note[] =
        "Please upgrade to at least kernel 2.6.29 or recent kvm-kmod\n"
        "(see http://sourceforge.net/projects/kvm).\n";
    struct {
        const char *name;
        int num;
    } num_cpus[] = {
        { "SMP",          smp_cpus },
        { "hotpluggable", max_cpus },
        { NULL, }
    }, *nc = num_cpus;
    int soft_vcpus_limit, hard_vcpus_limit;
    KVMState *s;
    const KVMCapabilityInfo *missing_cap;
    int ret;
    int type = 0;
    const char *kvm_type;

...

   s->fd = qemu_open("/dev/kvm", O_RDWR); ★
    if (s->fd == -1) {
        fprintf(stderr, "Could not access KVM kernel module: %m\n");
        ret = -errno;
        goto err;
    }

    ret = kvm_ioctl(s, KVM_GET_API_VERSION, 0); ★
    if (ret < KVM_API_VERSION) {
        if (ret >= 0) {
            ret = -EINVAL;
        }
        fprintf(stderr, "kvm version too old\n");
        goto err;
    }

    if (ret > KVM_API_VERSION) {
        ret = -EINVAL;
        fprintf(stderr, "kvm version not supported\n");
        goto err;
    }

...
```

蛇足で kvm_ioctl の中身はこの通り

```c
int kvm_ioctl(KVMState *s, int type, ...)
{
    int ret;
    void *arg;
    va_list ap;

    va_start(ap, type);
    arg = va_arg(ap, void *);
    va_end(ap);

    trace_kvm_ioctl(type, arg);
    ret = ioctl(s->fd, type, arg);
    if (ret == -1) {
        ret = -errno;
    }
    return ret;
}
```