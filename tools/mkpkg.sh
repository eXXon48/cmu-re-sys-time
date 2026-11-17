#!/bin/sh
# usage: mkpkg.sh <version> <rvp-pack> <out.rvp>
# needs build/libcmure-timefix.so (sh tools/build-timefix.sh)
set -eu
[ $# -eq 3 ] || { echo "usage: $0 <version> <rvp-pack> <out.rvp>" >&2; exit 2; }
ver=$1
case $ver in ''|*[!0-9A-Za-z.+~-]*) echo "bad version: $ver" >&2; exit 2;; esac
case $2 in /*) pack=$2;; *) pack=$PWD/$2;; esac
case $3 in /*) out=$3;; *) out=$PWD/$3;; esac
cd "$(dirname "$0")/.."
[ -f build/libcmure-timefix.so ] || { echo "build/libcmure-timefix.so missing: run tools/build-timefix.sh" >&2; exit 1; }
rm -rf build-pkg
cp -r pkg build-pkg
cp build/libcmure-timefix.so build-pkg/payload/libcmure-timefix.so
sed "s/\"version\": \"0.0.0\"/\"version\": \"$ver\"/" pkg/manifest.json > build-pkg/manifest.json
grep -qF "\"version\": \"$ver\"" build-pkg/manifest.json || { echo "version rewrite failed" >&2; exit 1; }
"$pack" build-pkg "$out"
