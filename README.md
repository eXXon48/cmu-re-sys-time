# cmu-re-sys-time

<p align="center"><img src="docs/meme.png" alt="You do not mess with time" width="640"></p>

**Real Linux time on the Mazda CMU150.** The head unit keeps correct UTC in its hardware RTC
(`/dev/rtc0`), but stock firmware never copies it into the Linux clock, so every boot starts
at 1970. Anything that checks wall time (TLS certificate validity, file times, logs) breaks.

This package adds one line to the boot hook `/jci/scripts/start_normal_mode.sh`, right after
the tripwire line, that runs `bin/set-clock.sh` (in the package folder) once per boot. The line
ships as a unified diff against the hook's vanilla base (stock + the tripwire line, registered
by the tripwire install). The script runs `hwclock -s -u` (busybox, already on the unit) before
the system manager starts: services see a real clock from their start and no clock jump while
they run (a jump while the system manager waits on services expires its start timeouts). An RTC
older than 2024-01-01 (flat battery, never set) is not copied, and a clock already past 2000 is
left alone. A boot the early clock breaks is counted by the tripwire, which runs first.

A real clock exposes a stock bug: several services (the time service BLM_TIME, phonebook,
SiriusXM, the Bluetooth library) take the deadline of an absolute wait from the monotonic
clock and pass it to calls that measure against the wall clock (`sem_timedwait`,
`pthread_mutex_timedlock`, `pthread_timedjoin_np`). At 1970 the two clocks are close and it
works; on a real clock every such wait expires at once, and time, timezone and GPS time
changes in Settings are dropped. The package installs a small library,
`/lib/libcmure-timefix.so`, preloaded into every process via `/etc/ld.so.preload`. It wraps
those three calls and moves a deadline earlier than 2000 onto the wall clock (deadline +
wall now - monotonic now) when the wall clock is past 2000; any other call is passed through
unchanged. It exports only those three symbols and binds lazily.

## How stock firmware handles time (74.00.324A)

- **The right time is there, nobody uses it.** The RTC holds real UTC, and busybox `hwclock`
  is on the unit, but no init script calls it. Every boot the Linux clock starts at
  1 Jan 1970.
- **The time service never sets the system clock.** BLM_TIME keeps time from the RTC, the
  timezone/DST settings and GPS, and pushes it only to the HMI status bar, at minute
  granularity (seconds always `:00`). Everything else on the unit lives in 1970.
- **The 1970 clock is load-bearing.** BLM_TIME, the phonebook, SiriusXM and the Bluetooth
  library compute wait deadlines from the monotonic clock and pass them to calls that
  measure against the wall clock. This only works because, at 1970, the two clocks read
  almost the same. Fix the clock and every such wait times out at once.
- **Set the clock early and the board resets itself.** If the clock is real while BLM_TIME
  starts, its init times out, its error path crashes (`SIGSEGV` in `[SM]SvcStateChH`), the
  system manager restarts it every ~10 s, and after six crashes the board resets (about
  75 s after power-on). This repeats every boot.
- **Set it late and Settings silently stops working.** If the clock is set after BLM_TIME
  is up, time, timezone, DST and GPS time changes all time out three times, are logged as
  `max number of retry reached - operation will not be performed`, and are dropped. Nothing
  tells the user.
- **The clock setting can't set the date.** Settings → Clock changes the time of day only;
  the date comes from GPS. A manual change rewrites the RTC directly, so the RTC can be off
  by up to a day.
- **The shipped CRL was valid for eight days.** `/jci/certificates/certcrl.pem` is valid
  12–20 Apr 2013: not yet valid at 1970, expired on a real clock.

## Install

From the Revised Store (or the USB stick, which installs it together with the store). The
change takes effect after the next restart; the store offers a SafeReboot.

## Revert

Uninstall it in the Store: the boot hook line is removed (the hook goes back to its vanilla
base), the library and `/etc/ld.so.preload` are removed, and the next boot is back to the
stock 1970 clock. The root filesystem stays read-write until that reboot, because running
processes still map the removed library.

## Known limits

- The RTC is only as right as the head unit's clock: Settings lets the user change the time
  of day (and that rewrites the RTC), so the clock can be off by up to a day.
- Time changes made later (Settings, GPS time sync) go to the RTC only; the Linux clock
  follows them at the next boot.
- For the first ~6–7 s after power-on (before the boot hook runs) the clock still reads 1970.

## Build

Tests (any POSIX sh): `sh test/run.sh`

Timed-wait fix (needs cc, readelf, zig 0.14; `ZIG=<zig command>`): `sh tools/build-timefix.sh`

```sh
sh tools/mkpkg.sh <version> <path/to/rvp-pack> cmu-re-sys-time-<version>.rvp
```

`rvp-pack` comes from the Revised Store repo. Releases: push a `vN` tag; CI packs the `.rvp`
and attaches it to the GitHub release.

## License

Not chosen yet (TBD). Until a license is added, no reuse rights are granted.
