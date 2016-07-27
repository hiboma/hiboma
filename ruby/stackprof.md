# stackprof

Q. Which method/fucntion raises signal?

## stackprof_start

 take options `:mode` `:interval`  `:out`

 * sigaction(2) + SIGALRM (`model: wall`) or SIGPROF (`mode: cpu`)
 * setitimer(2) + ITIMER_REAL (`model: wall`) or ITIMER_PROF (`mode: cpu`)

```c
static VALUE
stackprof_start(int argc, VALUE *argv, VALUE self)
{
    struct sigaction sa;
    struct itimerval timer;
    VALUE opts = Qnil, mode = Qnil, interval = Qnil, out = Qfalse;
    int raw = 0, aggregate = 1;

    if (_stackprof.running)
	return Qfalse;

    rb_scan_args(argc, argv, "0:", &opts);

    if (RTEST(opts)) {
	mode = rb_hash_aref(opts, sym_mode);
	interval = rb_hash_aref(opts, sym_interval);
	out = rb_hash_aref(opts, sym_out);

	if (RTEST(rb_hash_aref(opts, sym_raw)))
	    raw = 1;
	if (rb_hash_lookup2(opts, sym_aggregate, Qundef) == Qfalse)
	    aggregate = 0;
    }
    if (!RTEST(mode)) mode = sym_wall;

    if (!_stackprof.frames) {
	_stackprof.frames = st_init_numtable();
	_stackprof.overall_signals = 0;
	_stackprof.overall_samples = 0;
	_stackprof.during_gc = 0;
    }

    if (mode == sym_object) {
	if (!RTEST(interval)) interval = INT2FIX(1);

	objtracer = rb_tracepoint_new(Qnil, RUBY_INTERNAL_EVENT_NEWOBJ, stackprof_newobj_handler, 0);
	rb_tracepoint_enable(objtracer);
    } else if (mode == sym_wall || mode == sym_cpu) {
	if (!RTEST(interval)) interval = INT2FIX(1000);

	sa.sa_sigaction = stackprof_signal_handler;
	sa.sa_flags = SA_RESTART | SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	sigaction(mode == sym_wall ? SIGALRM : SIGPROF, &sa, NULL);

	timer.it_interval.tv_sec = 0;
	timer.it_interval.tv_usec = NUM2LONG(interval);
	timer.it_value = timer.it_interval;
	setitimer(mode == sym_wall ? ITIMER_REAL : ITIMER_PROF, &timer, 0);
    } else if (mode == sym_custom) {
	/* sampled manually */
	interval = Qnil;
    } else {
	rb_raise(rb_eArgError, "unknown profiler mode");
    }

    _stackprof.running = 1;
    _stackprof.raw = raw;
    _stackprof.aggregate = aggregate;
    _stackprof.mode = mode;
    _stackprof.interval = interval;
    _stackprof.out = out;

    return Qtrue;
}
``

## Where is a signal-handler function?

When SIGALRM or SIGPROF is raised, `stackprof_signal_handler` catches the signal.

 If `rb_during_gc()` returns true, GC is running !

```c
static void
stackprof_signal_handler(int sig, siginfo_t *sinfo, void *ucontext)
{
    _stackprof.overall_signals++;
    if (rb_during_gc())
	_stackprof.during_gc++, _stackprof.overall_samples++;
    else
	rb_postponed_job_register_one(0, stackprof_job_handler, 0);
}
```

```c
static void
stackprof_job_handler(void *data)
{
    static int in_signal_handler = 0;
    if (in_signal_handler) return;
    if (!_stackprof.running) return;

    in_signal_handler++;
    stackprof_record_sample();
    in_signal_handler--;
}
```

`stackprof_record_sample` collects samples

```c
void
stackprof_record_sample()
{
    int num, i, n;
    VALUE prev_frame = Qnil;

    _stackprof.overall_samples++;
    num = rb_profile_frames(0, sizeof(_stackprof.frames_buffer) / sizeof(VALUE), _stackprof.frames_buffer, _stackprof.lines_buffer);

    if (_stackprof.raw) {
	int found = 0;

	if (!_stackprof.raw_samples) {
	    _stackprof.raw_samples_capa = num * 100;
	    _stackprof.raw_samples = malloc(sizeof(VALUE) * _stackprof.raw_samples_capa);
	}

	if (_stackprof.raw_samples_capa <= _stackprof.raw_samples_len + num) {
	    _stackprof.raw_samples_capa *= 2;
	    _stackprof.raw_samples = realloc(_stackprof.raw_samples, sizeof(VALUE) * _stackprof.raw_samples_capa);
	}

	if (_stackprof.raw_samples_len > 0 && _stackprof.raw_samples[_stackprof.raw_sample_index] == (VALUE)num) {
	    for (i = num-1, n = 0; i >= 0; i--, n++) {
		VALUE frame = _stackprof.frames_buffer[i];
		if (_stackprof.raw_samples[_stackprof.raw_sample_index + 1 + n] != frame)
		    break;
	    }
	    if (i == -1) {
		_stackprof.raw_samples[_stackprof.raw_samples_len-1] += 1;
		found = 1;
	    }
	}

	if (!found) {
	    _stackprof.raw_sample_index = _stackprof.raw_samples_len;
	    _stackprof.raw_samples[_stackprof.raw_samples_len++] = (VALUE)num;
	    for (i = num-1; i >= 0; i--) {
		VALUE frame = _stackprof.frames_buffer[i];
		_stackprof.raw_samples[_stackprof.raw_samples_len++] = frame;
	    }
	    _stackprof.raw_samples[_stackprof.raw_samples_len++] = (VALUE)1;
	}
    }

    for (i = 0; i < num; i++) {
	int line = _stackprof.lines_buffer[i];
	VALUE frame = _stackprof.frames_buffer[i];
	frame_data_t *frame_data = sample_for(frame);

	frame_data->total_samples++;

	if (i == 0) {
	    frame_data->caller_samples++;
	} else if (_stackprof.aggregate) {
	    if (!frame_data->edges)
		frame_data->edges = st_init_numtable();
	    st_numtable_increment(frame_data->edges, (st_data_t)prev_frame, 1);
	}

	if (_stackprof.aggregate && line > 0) {
	    if (!frame_data->lines)
		frame_data->lines = st_init_numtable();
	    size_t half = (size_t)1<<(8*SIZEOF_SIZE_T/2);
	    size_t increment = i == 0 ? half + 1 : half;
	    st_numtable_increment(frame_data->lines, (st_data_t)line, increment);
	}

	prev_frame = frame;
    }
}
```