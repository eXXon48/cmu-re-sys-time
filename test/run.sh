#!/bin/sh
# Tests for pkg/payload/bin/set-clock.sh (host: any POSIX sh + awk). Usage: sh test/run.sh
set -u
cd "$(dirname "$0")"
S=../pkg/payload/bin/set-clock.sh
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0

# run <name> <events-file> <uptime> <expect: set|unset> [extra env...]
run() {
    name=$1 ev=$2 up=$3 want=$4; shift 4
    echo "$up.00 1.00" > "$T/uptime"
    rm -f "$T/hw"
    env SC_EVENTS="$ev" SC_UPTIME="$T/uptime" SC_YEAR=1970 SC_SETTLE=0 SC_POLL=0 \
        SC_HWCLOCK="touch $T/hw" "$@" sh "$S" > "$T/out" 2>&1
    got=unset; [ -e "$T/hw" ] && got=set
    if [ "$got" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name: want $want, got $got"; cat "$T/out"; fail=1; fi
}

H=PID,Component,Event,Timestamp
run "bench boot (RUNNING, all started)" smevents.bench.txt 50 set

printf '%s\n' $H "1,a,SM_SVC_CMD_START,1" "1,a,SM_SVC_CMD_STARTED,2" > "$T/norun"
run "no RUNNING yet -> gives up past GIVEUP" "$T/norun" 90 unset

printf '%s\n' $H "1,a,SM_SVC_CMD_STARTED,1" "x,ServiceManager,SM_SERVER_CMD_RUNNING,3" "2,b,SM_SVC_CMD_START,4" > "$T/pending"
run "RUNNING but a service still starting" "$T/pending" 90 unset

printf '%s\n' $H "1,a,SM_SVC_CMD_STARTED,1" "0,b,SM_SVC_CMD_STOPPED,2" "x,ServiceManager,SM_SERVER_CMD_RUNNING,3" > "$T/stopped"
run "STOPPED counts as settled" "$T/stopped" 50 set

run "events file missing" "$T/none" 90 unset

run "clock already set -> no-op" smevents.bench.txt 50 unset SC_YEAR=2026

# waits while uptime < GIVEUP: settles on a later poll
printf '%s\n' $H "1,a,SM_SVC_CMD_START,1" > "$T/late"
( sleep 1; echo "1,a,SM_SVC_CMD_STARTED,2" >> "$T/late"; echo "x,ServiceManager,SM_SERVER_CMD_RUNNING,3" >> "$T/late" ) &
run "waits, then sets once settled" "$T/late" 10 set SC_POLL=0.2
wait

# window: tripwire boot_timeout minus 30 s; no cnf -> the tripwire default 120 -> 90
run "settled but past the default window (90 s)" smevents.bench.txt 90 unset
printf 'contract_version=2
boot_timeout=150
' > "$T/cnf"
run "boot_timeout=150: sets at 119 s" smevents.bench.txt 119 set SC_TWCNF="$T/cnf"
run "boot_timeout=150: gives up at 120 s" smevents.bench.txt 120 unset SC_TWCNF="$T/cnf"

# tripwire counter: line 2 = 0 means the boot is already marked alive
printf 'TWCOUNT1
1
' > "$T/count1"; printf 'TWCOUNT1
0
' > "$T/count0"
run "boot not yet marked alive -> sets" smevents.bench.txt 50 set SC_TWCOUNT="$T/count1"
run "boot already marked alive -> leaves the clock" smevents.bench.txt 50 unset SC_TWCOUNT="$T/count0"
printf '%s
' $H "1,a,SM_SVC_CMD_START,1" > "$T/late2"
( sleep 1; printf 'TWCOUNT1
0
' > "$T/count2" ) &
printf 'TWCOUNT1
1
' > "$T/count2"
run "marked alive while waiting -> stops" "$T/late2" 10 unset SC_TWCOUNT="$T/count2" SC_POLL=0.2
wait

exit $fail
