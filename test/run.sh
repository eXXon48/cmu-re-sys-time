#!/bin/sh
# Tests for pkg/payload/bin/set-clock.sh (host: any POSIX sh). Usage: sh test/run.sh
set -u
cd "$(dirname "$0")"
S=../pkg/payload/bin/set-clock.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0

# run <name> <rtc epoch | -> <expect: set|unset> [extra env...]   (- = no RTC file)
run() {
    name=$1 rtc=$2 want=$3; shift 3
    rm -f "$T/hw" "$T/rtc"
    [ "$rtc" = - ] || echo "$rtc" > "$T/rtc"
    env SC_RTC_EPOCH="$T/rtc" SC_SLEEP="touch $T/slept" SC_YEAR=1970 SC_HWCLOCK="touch $T/hw" "$@" sh "$S" > "$T/out" 2>&1
    got=unset; [ -e "$T/hw" ] && got=set
    if [ "$got" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name: want $want, got $got"; cat "$T/out"; fail=1; fi
}

run "1970 clock, good RTC -> sets" 1794950955 set
run "clock already set -> no-op" 1794950955 unset SC_YEAR=2026
run "RTC before 2024 -> leaves the clock" 1600000000 unset
run "RTC file missing -> leaves the clock" - unset
run "RTC garbage -> leaves the clock" "12x" unset
run "RTC boundary 2024-01-01 -> sets" 1704067200 set
echo "echo 1794950955 > $T/rtc" > "$T/appear.sh"
run "RTC appears while waiting -> sets" - set SC_SLEEP="sh $T/appear.sh"
rm -f "$T/slept"; run "RTC present -> no wait" 1794950955 set
[ -e "$T/slept" ] && { echo "FAIL waited although the RTC was there"; fail=1; }

exit $fail
