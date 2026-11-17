#!/bin/sh
# set-clock.sh - set the Linux clock from the hardware RTC at boot, before SM starts.
#
# Run from the boot hook (/jci/scripts/start_normal_mode.sh, after the tripwire line) before
# system manager starts any JCI service: those services see a real clock from their first
# instruction and no clock jump while they run. This needs the package's preloaded timed-wait
# fix (/lib/libcmure-timefix.so): without it the time service BLM_TIME cannot initialise on a
# real clock and the board resets.
# rtc0 can register just after the hook runs: wait for it up to 3 s.
# An RTC older than MIN_EPOCH (flat battery, never set) is not copied.
# Env overrides are for tests only.

HWCLOCK=${SC_HWCLOCK:-/sbin/hwclock -s -u}
RTC_EPOCH=${SC_RTC_EPOCH:-/sys/class/rtc/rtc0/since_epoch}
MIN_EPOCH=1704067200           # 2024-01-01
SLEEP=${SC_SLEEP:-usleep 200000}   # 15 x 0.2 s = at most 3 s for rtc0 (registered ~6 s, hook runs ~6-7 s)

log() { echo "cmu-re-sys-time: $*"; logger -t cmu-re-sys-time "$*" 2>/dev/null; }

# already set (by anyone): nothing to do
[ "${SC_YEAR:-$(date +%Y)}" -ge 2000 ] && { log "clock already set ($(date)); nothing to do"; exit 0; }
i=0
while [ ! -e "$RTC_EPOCH" ] && [ "$i" -lt 15 ]; do $SLEEP; i=$((i + 1)); done
e=$(cat "$RTC_EPOCH" 2>/dev/null)
case "$e" in ''|*[!0-9]*) log "RTC unreadable; clock left unset"; exit 0 ;; esac
[ "$e" -ge "$MIN_EPOCH" ] || { log "RTC epoch $e implausible; clock left unset"; exit 0; }
$HWCLOCK && log "clock set from RTC: $(date)" || log "hwclock failed; clock left unset"
exit 0
