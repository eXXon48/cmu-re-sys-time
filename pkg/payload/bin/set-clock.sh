#!/bin/sh
# set-clock.sh - set the Linux clock from the hardware RTC once SM has finished starting.
#
# Started by SM as a one-shot service (sm.conf). The jump from 1970 to the real time must not
# happen while SM still waits on services: its start timeouts follow CLOCK_REALTIME. So wait
# until /tmp/smevents.txt shows SM_SERVER_CMD_RUNNING and no service is still starting.
#
# The jump must also land inside the tripwire's window, so that a boot it breaks is still
# counted: the tripwire marks the boot alive (counter line 2 = 0) boot_timeout seconds after
# it starts. Give up (clock untouched) once the boot is marked alive, or MARGIN seconds before
# boot_timeout, whichever comes first.
# Env overrides are for tests only.

EVENTS=${SC_EVENTS:-/tmp/smevents.txt}
TWCNF=${SC_TWCNF:-/etc/cmu-re/tripwire.cnf}
TWCOUNT=${SC_TWCOUNT:-/data_persist/cmu-re/boot_count}
MARGIN=${SC_MARGIN:-30}        # seconds left for a broken boot to reboot before the alive mark
SETTLE=${SC_SETTLE:-5}         # extra seconds after "all started"
POLL=${SC_POLL:-1}
HWCLOCK=${SC_HWCLOCK:-/sbin/hwclock -s -u}
UPTIME=${SC_UPTIME:-/proc/uptime}

log() { echo "cmu-re-sys-time: $*"; logger -t cmu-re-sys-time "$*" 2>/dev/null; }

# already set (by anyone): nothing to do
[ "${SC_YEAR:-$(date +%Y)}" -ge 2000 ] && { log "clock already set ($(date)); nothing to do"; exit 0; }

# window = tripwire boot_timeout (same default as the tripwire) minus MARGIN
bt=$(sed -n 's/^boot_timeout=\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$TWCNF" 2>/dev/null | tail -n 1)
[ -n "$bt" ] || bt=120
GIVEUP=${SC_GIVEUP:-$((bt - MARGIN))}

# the tripwire has marked this boot alive: a later jump would not be counted
alive() { [ "$(sed -n 2p "$TWCOUNT" 2>/dev/null)" = 0 ]; }
# still inside the window
open() {
    alive && { log "tripwire marked the boot alive; clock left unset"; return 1; }
    [ "$(cut -d. -f1 "$UPTIME")" -lt "$GIVEUP" ] || { log "SM not settled by ${GIVEUP}s uptime; clock left unset"; return 1; }
}

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
    open || exit 0
    sleep "$POLL"
done
open || exit 0
$HWCLOCK && log "clock set from RTC: $(date)" || log "hwclock failed; clock left unset"
exit 0
