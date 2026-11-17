#!/bin/sh
# set-clock.sh - set the Linux clock from the hardware RTC once SM has finished starting.
#
# Started by SM as a one-shot service (sm.conf). The jump from 1970 to the real time must not
# happen while SM still waits on services: its start timeouts follow CLOCK_REALTIME. So wait
# until /tmp/smevents.txt shows SM_SERVER_CMD_RUNNING and no service is still starting.
# Gives up (clock untouched) when SM does not get there within SC_GIVEUP seconds of uptime.
# Env overrides are for tests only.

EVENTS=${SC_EVENTS:-/tmp/smevents.txt}
GIVEUP=${SC_GIVEUP:-300}       # seconds of uptime
SETTLE=${SC_SETTLE:-5}         # extra seconds after "all started"
POLL=${SC_POLL:-1}
HWCLOCK=${SC_HWCLOCK:-/sbin/hwclock -s -u}
UPTIME=${SC_UPTIME:-/proc/uptime}

log() { echo "cmu-re-sys-time: $*"; logger -t cmu-re-sys-time "$*" 2>/dev/null; }

# already set (by anyone): nothing to do
[ "${SC_YEAR:-$(date +%Y)}" -ge 2000 ] && { log "clock already set ($(date)); nothing to do"; exit 0; }

# sm_settled: RUNNING seen and every service's last event is STARTED or STOPPED
sm_settled() {
    awk -F, 'NR > 1 {
                 if ($3 == "SM_SERVER_CMD_RUNNING") run = 1
                 else if ($3 ~ /^SM_SVC_/) last[$2] = $3
             }
             END {
                 if (!run) exit 1
                 for (s in last) if (last[s] != "SM_SVC_CMD_STARTED" && last[s] != "SM_SVC_CMD_STOPPED") exit 1
             }' "$EVENTS" 2>/dev/null
}

# settled, then still settled SETTLE seconds later (a late start restarts the wait)
until sm_settled && sleep "$SETTLE" && sm_settled; do
    up=$(cut -d. -f1 "$UPTIME")
    [ "$up" -lt "$GIVEUP" ] || { log "SM not settled after ${GIVEUP}s uptime; clock left unset"; exit 0; }
    sleep "$POLL"
done
$HWCLOCK && log "clock set from RTC: $(date)" || log "hwclock failed; clock left unset"
exit 0
