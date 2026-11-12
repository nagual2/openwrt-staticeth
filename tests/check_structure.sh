#!/usr/bin/env bash
# Structure and syntax test for the staticeth package tree (used by CI).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

test -f "$ROOT/files/etc/init.d/staticeth"
test -f "$ROOT/files/etc/hotplug.d/net/90-staticeth"
test -f "$ROOT/files/etc/config/mac-static-interfaces.example"
test -f "$ROOT/install.sh"
test -f "$ROOT/scripts/build-apk-mkpkg.sh"
test -f "$ROOT/NOTICE"
test -f "$ROOT/LICENSE"

sh -n "$ROOT/files/etc/init.d/staticeth"
sh -n "$ROOT/files/etc/hotplug.d/net/90-staticeth"
sh -n "$ROOT/install.sh"
sh -n "$ROOT/scripts/build-apk-mkpkg.sh"

echo "structure OK"
