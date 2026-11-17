# cmu-re-sys-time

**Real Linux time on the Mazda CMU150.** The head unit keeps correct UTC in its hardware RTC
(`/dev/rtc0`), but stock firmware never copies it into the Linux clock, so every boot starts
at 1970. Anything that checks wall time (TLS certificate validity, file times, logs) breaks.

This package adds one short-lived service to the system manager (`/jci/sm/sm.conf` and
`sm_WCP.conf`) that runs `bin/set-clock.sh` (in the package folder) once per boot. The script
waits until the system manager reports that all services are up (`SM_SERVER_CMD_RUNNING` in
`/tmp/smevents.txt`, about 60 s after power-on), then runs `hwclock -s -u` (busybox, already
on the unit). Setting the clock earlier breaks the boot: the system manager's start timeouts
follow the wall clock, and a jump of decades expires them all. The jump must also land inside
the tripwire's window so a boot it breaks is still counted: the script gives up (clock left
alone) once the tripwire has marked the boot alive (`/data_persist/cmu-re/boot_count` line 2
is `0`), or 30 s before the tripwire's `boot_timeout` (from `/etc/cmu-re/tripwire.cnf`,
default 120), whichever comes first.

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

## Install

From the Revised Store (or the USB stick, which installs it together with the store). The
change takes effect after the next restart; the store offers a SafeReboot.

## Revert

Uninstall it in the Store: the service entry is removed from both SM configs, the library
and `/etc/ld.so.preload` are removed, and the next boot is back to the stock 1970 clock.

## Known limits

- The RTC is only as right as the head unit's clock: Settings lets the user change the time
  of day (and that rewrites the RTC), so the clock can be off by up to a day.
- Time changes made later (Settings, GPS time sync) go to the RTC only; the Linux clock
  follows them at the next boot.
- Until about a minute after power-on the clock still reads 1970.

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
