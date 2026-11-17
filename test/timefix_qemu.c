/* ARM probe: the stock bug pattern (monotonic deadline into a realtime-only absolute wait) on a
 * real clock. Prints rc and how long each wait took. Expected: monotonic cases ~0 ms without
 * the shim, ~1000 ms with it; realtime cases ~1000 ms both ways. All rc must be 110 (ETIMEDOUT). */
#define _GNU_SOURCE   /* pthread_timedjoin_np */
#include <pthread.h>
#include <semaphore.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

static struct timespec t0;

static struct timespec deadline(clockid_t clk)
{
    struct timespec d;
    clock_gettime(clk, &d);
    d.tv_sec += 1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    return d;
}

static void report(const char *name, int rc)
{
    struct timespec b;
    clock_gettime(CLOCK_MONOTONIC, &b);
    printf("%-28s rc=%d waited=%ld ms\n", name, rc,
           (b.tv_sec - t0.tv_sec) * 1000 + (b.tv_nsec - t0.tv_nsec) / 1000000);
}

static void *sleeper(void *a) { (void)a; sleep(3); return 0; }

static void run(const char *tag, clockid_t clk)
{
    char n[64];
    sem_t s;
    pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
    pthread_t th;
    struct timespec d;
    int rc;

    sem_init(&s, 0, 0);
    d = deadline(clk);
    rc = sem_timedwait(&s, &d) ? 110 : 0;
    snprintf(n, sizeof n, "sem_timedwait %s", tag); report(n, rc);

    pthread_mutex_lock(&m);   /* default mutex, same thread: timedlock blocks until deadline */
    d = deadline(clk);
    rc = pthread_mutex_timedlock(&m, &d);
    snprintf(n, sizeof n, "mutex_timedlock %s", tag); report(n, rc);

    pthread_create(&th, 0, sleeper, 0);
    d = deadline(clk);
    rc = pthread_timedjoin_np(th, 0, &d);
    snprintf(n, sizeof n, "timedjoin_np %s", tag); report(n, rc);
    pthread_join(th, 0);
}

int main(void)
{
    run("mono", CLOCK_MONOTONIC);
    run("real", CLOCK_REALTIME);
    return 0;
}
