#!/bin/sh
# staticeth installer for OpenWrt.
# Copies the init script, the hotplug companion and the example mapping to the
# router filesystem, then enables the init service. Run this ON the router.
#
# Usage:
#   ./install.sh      install (or update) and enable
#   ./install.sh -u   uninstall (mapping file /etc/config/mac-static-interfaces is kept)

set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="/etc/config/mac-static-interfaces"

if [ "$1" = "-u" ]; then
	/etc/init.d/staticeth disable 2>/dev/null || true
	rm -f /etc/init.d/staticeth /etc/hotplug.d/net/90-staticeth
	echo "staticeth removed."
	echo "/etc/config/mac-static-interfaces kept — delete manually if not needed."
	echo "Reboot to return to stock interface naming."
	exit 0
fi

[ -f /etc/openwrt_release ] || echo "WARNING: this does not look like OpenWrt; continuing anyway."
[ -d "$SRC_DIR/files/etc/init.d" ] || { echo "ERROR: run this script from the repository root (files/ not found)." >&2; exit 1; }

cp "$SRC_DIR/files/etc/init.d/staticeth" /etc/init.d/staticeth
chmod +x /etc/init.d/staticeth
cp "$SRC_DIR/files/etc/hotplug.d/net/90-staticeth" /etc/hotplug.d/net/90-staticeth
chmod +x /etc/hotplug.d/net/90-staticeth

if [ -f "$CONFIG" ]; then
	echo "Config $CONFIG already exists — left untouched."
else
	cp "$SRC_DIR/files/etc/config/mac-static-interfaces.example" "$CONFIG"
	echo "Created $CONFIG from the example — EDIT IT before rebooting."
fi

/etc/init.d/staticeth enable

echo
echo "Installed."
echo "IMPORTANT — do not skip:"
echo "  1. Put the REAL MAC addresses into $CONFIG."
echo "     List current MACs: grep -H . /sys/class/net/*/address"
echo "  2. Make sure /etc/config/network references the NEW interface names"
echo "     (device sections, ports) BEFORE rebooting."
echo "  3. Keep serial console or recovery access ready: after the reboot the"
echo "     interfaces carry the new names and the old ones stop existing."
echo "  4. Reboot, then verify: ip link"
