## wait_writable

Socket#wait_writable

```java
    /**
     * waits until input available or timed out and returns self, or nil when EOF reached.
     */
    @JRubyMethod(optional = 1)
    public static IRubyObject wait_writable(ThreadContext context, IRubyObject _io, IRubyObject[] argv) {
        RubyIO io = (RubyIO)_io;
        Ruby runtime = context.runtime;
        OpenFile fptr;
        IRubyObject timeout;
        long tv;

        fptr = io.getOpenFileChecked();
        fptr.checkWritable(context);

        switch (argv.length) {
            case 1:
                timeout = argv[0];
                break;
            default:
                timeout = context.nil;
        }
        if (timeout.isNil()) {
            tv = -1;
        }
        else {
            tv = timeout.convertToInteger().getLongValue() * 1000;
            if (tv < 0) throw runtime.newArgumentError("time interval must be positive");
        }

        boolean ready = fptr.ready(runtime, context.getThread(), SelectionKey.OP_WRITE, tv);
        fptr.checkClosed();
        if (ready)
            return io;
        return context.nil;
    }
```

OpenFile#ready

```java
    /**
     * Wait until the channel is available for the given operations or the timeout expires.
     *
     * @see org.jruby.RubyThread#select(java.nio.channels.Channel, OpenFile, int, long)
     *
     * @param runtime
     * @param ops
     * @param timeout
     * @return
     */
    public boolean ready(Ruby runtime, RubyThread thread, int ops, long timeout) {
        boolean locked = lock();
        try {
            if (fd.chSelect != null) {
                return thread.select(fd.chSelect, this, ops & fd.chSelect.validOps(), timeout);

            } else if (fd.chSeek != null) {
                return fd.chSeek.position() != -1
                        && fd.chSeek.size() != -1
                        && fd.chSeek.position() < fd.chSeek.size();
            }

            return false;
        } catch (IOException ioe) {
            throw runtime.newIOErrorFromException(ioe);
        } finally {
            if (locked) unlock();
        }
    }
```