#!/usr/bin/env bash
# Build OpenWrt 25.12+ .apk for staticeth (noarch: shell scripts + config only).
# Uses only the host `apk` tool extracted from the OpenWrt SDK — no full SDK build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
SDK_DIR="${SDK_DIR:-$ROOT/build/sdk}"
APK_TOOL="${APK_TOOL:-$SDK_DIR/staging_dir/host/bin/apk}"

PROJECT_VERSION="${PROJECT_VERSION:-$(git -C "$ROOT" describe --tags --match 'v*' 2>/dev/null | sed 's/^v//')}"
PROJECT_VERSION="${PROJECT_VERSION:-1.0.0}"
PKG_RELEASE="${PKG_RELEASE:-1}"
PKG_VERSION="${PROJECT_VERSION}-r${PKG_RELEASE}"

log() { printf '[build-apk-mkpkg] %s\n' "$*"; }

ensure_apk_tool() {
	if [ -x "$APK_TOOL" ]; then
		return 0
	fi
	local archive url
	url="${SDK_URL:-https://downloads.openwrt.org/releases/25.12.0/targets/x86/64/openwrt-sdk-25.12.0-x86-64_gcc-14.3.0_musl.Linux-x86_64.tar.zst}"
	archive="$ROOT/build/$(basename "$url")"
	log "Extracting apk host tool from OpenWrt SDK..."
	mkdir -p "$ROOT/build"
	[ -f "$archive" ] || wget -O "$archive" "$url"
	rm -rf "$SDK_DIR"
	mkdir -p "$SDK_DIR"
	tar --zstd -xf "$archive" -C "$SDK_DIR" --strip-components=1
	APK_TOOL="$SDK_DIR/staging_dir/host/bin/apk"
	[ -x "$APK_TOOL" ] || { echo "apk tool not found: $APK_TOOL" >&2; exit 1; }
}

ensure_apk_tool

STAGE="$(mktemp -d)"
POSTINST="$(mktemp)"
trap 'rm -rf "$STAGE" "$POSTINST"' EXIT

log "Staging files in $STAGE"
install -d "$STAGE/etc/config"
cp -a "$ROOT/files/etc/init.d" "$STAGE/etc/"
cp -a "$ROOT/files/etc/hotplug.d" "$STAGE/etc/"
install -m 0644 "$ROOT/files/etc/config/mac-static-interfaces.example" "$STAGE/etc/config/"

chmod 0755 "$STAGE/etc/init.d/staticeth" "$STAGE/etc/hotplug.d/net/90-staticeth"

cat >"$POSTINST" <<'EOF'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0
[ -f /etc/config/mac-static-interfaces ] || cp /etc/config/mac-static-interfaces.example /etc/config/mac-static-interfaces
/etc/init.d/staticeth enable
exit 0
EOF
chmod 0755 "$POSTINST"

mkdir -p "$OUTPUT_DIR"
OUT_APK="$OUTPUT_DIR/staticeth-${PKG_VERSION}.apk"

log "Creating $OUT_APK"
"$APK_TOOL" mkpkg \
	--compat 3.0.0_pre1 \
	--files "$STAGE" \
	--info "name:staticeth" \
	--info "version:${PKG_VERSION}" \
	--info "arch:noarch" \
	--info "license:CC-BY-SA-4.0" \
	--info "maintainer:nagual2" \
	--info "description:Persistent Ethernet interface naming by MAC address (staticeth)" \
	--script "post-install:$POSTINST" \
	--output "$OUT_APK"

log "Built: $OUT_APK ($(wc -c <"$OUT_APK") bytes)"
