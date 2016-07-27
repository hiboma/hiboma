## --enable-dtrace

#### version

2.3.1

#### configure

```sh
$ ./configure --help | grep -A10 dtrace
  --enable-dtrace         enable DTrace for tracing inside ruby. enabled by
                          default on systems having dtrace
```

#### configure.in

```sh
AC_DEFUN([RUBY_DTRACE_AVAILABLE],
[AC_CACHE_CHECK(whether dtrace USDT is available, rb_cv_dtrace_available,
[
    echo "provider conftest{ probe fire(); };" > conftest_provider.d
    if $DTRACE -h -o conftest_provider.h -s conftest_provider.d >/dev/null 2>/dev/null; then
      AC_TRY_COMPILE([@%:@include "conftest_provider.h"], [CONFTEST_FIRE();], [
        # DTrace is available on the system
        rb_cv_dtrace_available=yes
      ], [rb_cv_dtrace_available=no])
    else
      # DTrace is not available while dtrace command exists
      # for example FreeBSD 8 or FreeBSD 9 without DTrace build option
      rb_cv_dtrace_available=no
    fi
    rm -f conftest.[co] conftest_provider.[dho]
])
])

AC_DEFUN([RUBY_DTRACE_POSTPROCESS],
[AC_CACHE_CHECK(whether $DTRACE needs post processing, rb_cv_prog_dtrace_g,
[
  rb_cv_prog_dtrace_g=no
  if {
    cat >conftest_provider.d <<_PROBES &&
    provider conftest {
      probe fire();
    };
_PROBES
    $DTRACE -h -o conftest_provider.h -s conftest_provider.d >/dev/null 2>/dev/null &&
    :
  }; then
    AC_TRY_COMPILE([@%:@include "conftest_provider.h"], [CONFTEST_FIRE();], [
        if {
            cp -p conftest.${ac_objext} conftest.${ac_objext}.save &&
            $DTRACE -G -s conftest_provider.d conftest.${ac_objext} 2>/dev/null &&
            :
        }; then
            if cmp -s conftest.o conftest.${ac_objext}.save; then
                rb_cv_prog_dtrace_g=yes
            else
                rb_cv_prog_dtrace_g=rebuild
            fi
        fi])
  fi
  rm -f conftest.[co] conftest_provider.[dho]
])
])

AC_CHECK_PROG([DTRACE], [${ac_tool_prefix}dtrace], [${ac_tool_prefix}dtrace])
if test "$cross_compiling:$ac_cv_prog_DTRACE" = no: -a -n "$ac_tool_prefix"; then
    AC_CHECK_PROG([DTRACE], [dtrace], [dtrace])
fi
```

## ruby-2.3.1/probes_helper.h

```c
#ifndef RUBY_PROBES_HELPER_H
#define RUBY_PROBES_HELPER_H

#include "ruby/ruby.h"
#include "probes.h"

struct ruby_dtrace_method_hook_args {
    const char *classname;
    const char *methodname;
    const char *filename;
    int line_no;
    volatile VALUE klass;
    volatile VALUE name;
};

NOINLINE(int ruby_th_dtrace_setup(rb_thread_t *, VALUE, ID, struct ruby_dtrace_method_hook_args *));
```

```c
#define RUBY_DTRACE_METHOD_HOOK(name, th, klazz, id) \
do { \
    if (UNLIKELY(RUBY_DTRACE_##name##_ENABLED())) { \
	struct ruby_dtrace_method_hook_args args; \
	if (ruby_th_dtrace_setup(th, klazz, id, &args)) { \
	    RUBY_DTRACE_##name(args.classname, \
			       args.methodname, \
			       args.filename, \
			       args.line_no); \
	} \
    } \
} while (0)

#define RUBY_DTRACE_METHOD_ENTRY_HOOK(th, klass, id) \
    RUBY_DTRACE_METHOD_HOOK(METHOD_ENTRY, th, klass, id)

#define RUBY_DTRACE_METHOD_RETURN_HOOK(th, klass, id) \
    RUBY_DTRACE_METHOD_HOOK(METHOD_RETURN, th, klass, id)

#define RUBY_DTRACE_CMETHOD_ENTRY_HOOK(th, klass, id) \
    RUBY_DTRACE_METHOD_HOOK(CMETHOD_ENTRY, th, klass, id)

#define RUBY_DTRACE_CMETHOD_RETURN_HOOK(th, klass, id) \
    RUBY_DTRACE_METHOD_HOOK(CMETHOD_RETURN, th, klass, id)

#endif /* RUBY_PROBES_HELPER_H */
```

```c
#define RUBY_DTRACE_GC_HOOK(name) \
    do {if (RUBY_DTRACE_GC_##name##_ENABLED()) RUBY_DTRACE_GC_##name();} while (0)
static inline void
gc_prof_mark_timer_start(rb_objspace_t *objspace)
{
    RUBY_DTRACE_GC_HOOK(MARK_BEGIN);
#if GC_PROFILE_MORE_DETAIL
    if (gc_prof_enabled(objspace)) {
	gc_prof_record(objspace)->gc_mark_time = getrusage_time();
    }
#endif
}
```

```c
#define RUBY_DTRACE_CREATE_HOOK(name, arg) \
    RUBY_DTRACE_HOOK(name##_CREATE, arg)
#define RUBY_DTRACE_HOOK(name, arg) \
do { \
    if (UNLIKELY(RUBY_DTRACE_##name##_ENABLED())) { \
	int dtrace_line; \
	const char *dtrace_file = rb_source_loc(&dtrace_line); \
	if (!dtrace_file) dtrace_file = ""; \
	RUBY_DTRACE_##name(arg, dtrace_file, dtrace_line); \
    } \
} while (0)
```