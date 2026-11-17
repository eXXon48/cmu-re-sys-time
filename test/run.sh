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
run "bench boot (RUNNING, all started)" smevents.bench.txt 400 set

printf '%s\n' $H "1,a,SM_SVC_CMD_START,1" "1,a,SM_SVC_CMD_STARTED,2" > "$T/norun"
run "no RUNNING yet -> gives up past GIVEUP" "$T/norun" 400 unset

printf '%s\n' $H "1,a,SM_SVC_CMD_STARTED,1" "x,ServiceManager,SM_SERVER_CMD_RUNNING,3" "2,b,SM_SVC_CMD_START,4" > "$T/pending"
run "RUNNING but a service still starting" "$T/pending" 400 unset

printf '%s\n' $H "1,a,SM_SVC_CMD_STARTED,1" "0,b,SM_SVC_CMD_STOPPED,2" "x,ServiceManager,SM_SERVER_CMD_RUNNING,3" > "$T/stopped"
run "STOPPED counts as settled" "$T/stopped" 400 set

run "events file missing" "$T/none" 400 unset

run "clock already set -> no-op" smevents.bench.txt 400 unset SC_YEAR=2026

# waits while uptime < GIVEUP: settles on a later poll
printf '%s\n' $H "1,a,SM_SVC_CMD_START,1" > "$T/late"
( sleep 1; echo "1,a,SM_SVC_CMD_STARTED,2" >> "$T/late"; echo "x,ServiceManager,SM_SERVER_CMD_RUNNING,3" >> "$T/late" ) &
run "waits, then sets once settled" "$T/late" 10 set SC_POLL=0.2
wait

exit $fail
