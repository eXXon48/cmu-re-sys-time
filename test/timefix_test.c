/* host test for timefix_adjust(): cc -DTIMEFIX_TEST test/timefix_test.c src/timefix.c */
#include <stdio.h>
typedef struct { long tv_sec; long tv_nsec; } ts_t;
int timefix_adjust(const ts_t *abs, const ts_t *rt, const ts_t *mono, ts_t *out);

static int fails;
static void check(const char *name, ts_t abs, ts_t rt, ts_t mono, int want, ts_t want_out)
{
    ts_t out = { -7, -7 };
    int got = timefix_adjust(&abs, &rt, &mono, &out);
    if (got != want || (want && (out.tv_sec != want_out.tv_sec || out.tv_nsec != want_out.tv_nsec))) {
        printf("FAIL %s: got %d {%ld,%ld}\n", name, got, out.tv_sec, out.tv_nsec);
        fails++;
    } else printf("ok   %s\n", name);
}

int main(void)
{
    ts_t z = { 0, 0 };
    /* real clock 2026-11-17 ~ 1794900000, uptime 10.2 s */
    ts_t rt = { 1794900000, 300000000 }, mono = { 10, 200000000 };
    /* monotonic deadline 15.0 s -> rt + 4.8 s */
    check("mono deadline moved", (ts_t){ 15, 0 }, rt, mono, 1, (ts_t){ 1794900005, 100000000 });
    /* nsec carry up: 0.95 + (0.3 - 0.2) = 1.05 */
    check("nsec carry up", (ts_t){ 15, 950000000 }, rt, mono, 1, (ts_t){ 1794900006, 50000000 });
    /* nsec borrow: rt nsec < mono nsec */
    check("nsec borrow", (ts_t){ 15, 0 }, (ts_t){ 1794900000, 100000000 }, mono, 1, (ts_t){ 1794900004, 900000000 });
    /* stock 1970 clock: never touched */
    check("1970 clock untouched", (ts_t){ 15, 0 }, (ts_t){ 10, 300000000 }, mono, 0, z);
    /* proper realtime deadline: untouched */
    check("realtime deadline untouched", (ts_t){ 1794900005, 0 }, rt, mono, 0, z);
    /* invalid nsec / negative sec: left to the real call (EINVAL) */
    check("bad nsec untouched", (ts_t){ 15, 1000000000 }, rt, mono, 0, z);
    check("negative sec untouched", (ts_t){ -1, 0 }, rt, mono, 0, z);
    check("boundary 2000 untouched", (ts_t){ 946684800, 0 }, rt, mono, 0, z);
    return fails != 0;
}
