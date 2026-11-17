# cmu-re-sys-time

**Real Linux time on the Mazda CMU150.** The head unit keeps correct UTC in its hardware RTC
(`/dev/rtc0`), but stock firmware never copies it into the Linux clock, so every boot starts
at 1970. Anything that checks wall time (TLS certificate validity, file times, logs) breaks.

This package adds one short-lived service to the system manager (`/jci/sm/sm.conf` and
`sm_WCP.conf`) that runs `hwclock -s -u` (busybox, already on the unit) once at boot. No
binary is shipped; the package carries only the XML insert.

## Install

From the Revised Store (or the USB stick, which installs it together with the store). The
change takes effect after the next restart; the store offers a SafeReboot.

## Revert

Uninstall it in the Store: the service entry is removed from both SM configs and the next
boot is back to the stock 1970 clock.

## Known limits

- The RTC is only as right as the head unit's clock: Settings lets the user change the time
  of day (and that rewrites the RTC), so the clock can be off by up to a day.
- No network or GPS time sync.

## Build

```sh
sh tools/mkpkg.sh <version> <path/to/rvp-pack> cmu-re-sys-time-<version>.rvp
```

`rvp-pack` comes from the Revised Store repo. Releases: push a `vN` tag; CI packs the `.rvp`
and attaches it to the GitHub release.

## License

Not chosen yet (TBD). Until a license is added, no reuse rights are granted.
