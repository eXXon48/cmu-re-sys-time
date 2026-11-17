/* timefix.c - preloaded fix for absolute waits whose deadline was taken on the wrong clock.
 *
 * Some stock services compute a sem_timedwait() / pthread_mutex_timedlock() /
 * pthread_timedjoin_np() deadline as clock_gettime(CLOCK_MONOTONIC) + timeout. Those calls
 * measure against CLOCK_REALTIME. While the Linux clock sits at
 * 1970 the two clocks are close and the wait works; once the clock holds real time the
 * deadline lies decades in the past and every wait fails at once with ETIMEDOUT.
 *
 * Rule: a deadline before 2000 while the realtime clock is past 2000 cannot be a real
 * realtime deadline, so it is read as a monotonic one and moved onto the realtime clock
 * (deadline + realtime_now - monotonic_now). Every other call passes through unchanged:
 * with the clock at 1970 nothing is ever touched.
 *
 * Own types and no libc headers: the unit runs glibc 2.11.1 on 32-bit ARM (32-bit time_t).
 */
typedef struct { long tv_sec; long tv_nsec; } ts_t;

#define EPOCH_2000 946684800L
#define NSEC 1000000000L
#define CLK_REALTIME 0
#define CLK_MONOTONIC 1
#define RTLD_NEXT ((void *)-1L)

/* pure part, unit-tested on the host: returns 1 and fills *out when abs must be moved */
int timefix_adjust(const ts_t *abs, const ts_t *rt, const ts_t *mono, ts_t *out)
{
    long s, ns;
    if (abs->tv_sec < 0 || abs->tv_sec >= EPOCH_2000) return 0;
    if (abs->tv_nsec < 0 || abs->tv_nsec >= NSEC) return 0;   /* leave EINVAL to the real call */
    if (rt->tv_sec < EPOCH_2000) return 0;                     /* clock still at 1970: stock case */
    s = abs->tv_sec + (rt->tv_sec - mono->tv_sec);
    ns = abs->tv_nsec + (rt->tv_nsec - mono->tv_nsec);
    if (ns < 0) { ns += NSEC; s--; }
    else if (ns >= NSEC) { ns -= NSEC; s++; }
    out->tv_sec = s;
    out->tv_nsec = ns;
    return 1;
}

#ifndef TIMEFIX_TEST
extern void *dlsym(void *, const char *);
extern long syscall(long, ...);
#define NR_clock_gettime 263   /* ARM EABI; glibc 2.11 has clock_gettime in librt only */

/* returns abs, or *buf holding abs moved onto the realtime clock */
static const ts_t *fix(const ts_t *abs, ts_t *buf)
{
    ts_t rt, mono;
    if (abs && abs->tv_sec < EPOCH_2000
        && syscall(NR_clock_gettime, CLK_REALTIME, &rt) == 0
        && syscall(NR_clock_gettime, CLK_MONOTONIC, &mono) == 0
        && timefix_adjust(abs, &rt, &mono, buf))
        return buf;
    return abs;
}

/* Each takes a realtime-only absolute deadline in glibc 2.11; the stock misuses found are
 * listed per wrapper. Lookup is lazy (benign race: every thread stores the same pointer). */
#define WRAP(name, T)                                                             \
    static int (*real_##name)(T, const ts_t *);                                   \
    __attribute__((visibility("default"))) int name(T obj, const ts_t *abs)       \
    {                                                                             \
        ts_t buf;                                                                 \
        if (!real_##name) real_##name = (int (*)(T, const ts_t *))dlsym(RTLD_NEXT, #name); \
        return real_##name(obj, fix(abs, &buf));                                  \
    }

WRAP(sem_timedwait, void *)            /* svcjciblmtime.so, libbttr.so */
WRAP(pthread_mutex_timedlock, void *)  /* svcjcisxms.so */

static int (*real_pthread_timedjoin_np)(unsigned long, void **, const ts_t *);
__attribute__((visibility("default")))
int pthread_timedjoin_np(unsigned long th, void **ret, const ts_t *abs)   /* svcjcipb.so */
{
    ts_t buf;
    if (!real_pthread_timedjoin_np)
        real_pthread_timedjoin_np = (int (*)(unsigned long, void **, const ts_t *))
            dlsym(RTLD_NEXT, "pthread_timedjoin_np");
    return real_pthread_timedjoin_np(th, ret, fix(abs, &buf));
}
#endif
