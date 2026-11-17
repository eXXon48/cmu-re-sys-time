#!/bin/sh
# usage: build-timefix.sh   (needs cc, readelf and zig 0.14: ZIG=<zig command>, default /opt/zig/zig
#        as in the rvp-build container; CI: ZIG="python3 -m ziglang" from the ziglang wheel)
# Host unit test of the deadline rule, then the ARM shim for the unit (armel, glibc 2.11.1).
# Only the wrapped waits are exported (version script): zig links compiler_rt, whose weak
# memcpy/memset/libm symbols would otherwise interpose libc in every preloaded process.
# -z lazy: dlsym/syscall bind on the first wrapped call, not at every exec (zig defaults to
# BIND_NOW), so a process that never calls a wrapped wait (the boot shell) binds nothing.
set -eu
ZIG=${ZIG:-/opt/zig/zig}
cd "$(dirname "$0")/.."
mkdir -p build
cc -Wall -Wextra -DTIMEFIX_TEST -o build/timefix_test test/timefix_test.c src/timefix.c
build/timefix_test
$ZIG cc -target arm-linux-gnueabi.2.11 -mcpu=cortex_a9 -O2 -Wall -fPIC -shared \
    -fvisibility=hidden -ffunction-sections -Wl,--gc-sections -Wl,-z,lazy \
    -Wl,--version-script=src/timefix.map -Wl,-soname,libcmure-timefix.so -s \
    -o build/libcmure-timefix.so src/timefix.c -ldl
$ZIG cc -target arm-linux-gnueabi.2.11 -mcpu=cortex_a9 -O2 \
    -o build/timefix_qemu test/timefix_qemu.c -lpthread -lrt
exports=$(readelf --dyn-syms -W build/libcmure-timefix.so | awk '$7 != "UND" && $5 != "LOCAL" && NR > 3 {print $8}' | sort | tr '\n' ' ')
[ "$exports" = "pthread_mutex_timedlock pthread_timedjoin_np sem_timedwait " ] \
    || { echo "unexpected exports: $exports" >&2; exit 1; }
! readelf -d build/libcmure-timefix.so | grep -qE 'BIND_NOW|FLAGS_1.*NOW' \
    || { echo "BIND_NOW set: build must be lazy" >&2; exit 1; }
echo "built build/libcmure-timefix.so (exports: $exports)"
# ARM check (optional, needs qemu-arm-static and a sysroot with the stock /lib):
#   qemu-arm-static -L <sysroot> ./build/timefix_qemu                       -> monotonic: waited=0 ms
#   qemu-arm-static -L <sysroot> -E LD_PRELOAD=$PWD/build/libcmure-timefix.so ./build/timefix_qemu
#                                                                            -> monotonic: waited=1000 ms
