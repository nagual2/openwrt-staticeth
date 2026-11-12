# openwrt-staticeth

**English** | [Русский](README.ru.md) | [Deutsch](README.de.md)

Persistent Ethernet interface naming by MAC address for OpenWrt: the name a network adapter gets no longer depends on the order in which USB adapters are enumerated at boot.

The problem this solves: single-board routers (Raspberry Pi and friends) have one built-in NIC, so extra interfaces come as USB Ethernet dongles. On every reboot the kernel may enumerate them in a different order — `eth0`, `eth1`, `eth2` change places, and the UCI network configuration suddenly describes the wrong devices. `staticeth` pins each adapter to a fixed interface name by its MAC address.

The method is taken from the official OpenWrt wiki page [Persistent Ethernet Interface Naming by MAC Address](https://openwrt.org/docs/guide-user/base-system/persistent-ethernet-interface-naming-by-mac-address), which grew out of [this forum thread](https://forum.openwrt.org/t/stable-network-interface-names-for-usb-ethernet-dongles/98539). This repo packages it with a hotplug companion, an installer and documentation. License: CC BY-SA 4.0 (see [NOTICE](NOTICE)).

## Components

| № | File in repo | Path on router | Purpose |
|---|--------------|----------------|---------|
| 1 | `files/etc/init.d/staticeth` | `/etc/init.d/staticeth` | Init script (`START=11`, before `network`): renames interfaces at boot |
| 2 | `files/etc/hotplug.d/net/90-staticeth` | `/etc/hotplug.d/net/90-staticeth` | Hotplug companion: renames adapters plugged in while the system is running |
| 3 | `files/etc/config/mac-static-interfaces.example` | `/etc/config/mac-static-interfaces` | MAC → name mapping (UCI syntax) |
| 4 | `install.sh` | — | Installer / uninstaller, run on the router |

## How it works

### Boot (init script)

- `START=11` puts it before the `network` service.
- Only physical interfaces are touched: they are enumerated via `/sys/class/net/*/device/uevent`, so bridges and virtual interfaces are excluded automatically.
- Pass 1: every interface whose current name appears in the mapping is brought down and parked as `old<name>` — this frees all target names, so no swap races are possible.
- Pass 2: each interface's MAC (`/sys/class/net/<i>/address`) is looked up in the mapping and the interface gets its target name.

### Live hotplug (companion)

- Runs on `add` events only, and only for physical devices.
- Renames only when the target name is currently free; occupied names are never swapped at runtime.
- Reads the same mapping file as the init script.

## Install

Copy the repo to the router and run the installer:

```sh
scp -r openwrt-staticeth root@192.168.1.1:/tmp/
ssh root@192.168.1.1
cd /tmp/openwrt-staticeth
./install.sh
```

(With OpenSSH 9.x against dropbear, use `scp -O -r ...`.)

Then:

1. Put the real MAC addresses into `/etc/config/mac-static-interfaces`.
   List current ones: `grep -H . /sys/class/net/*/address`
2. Make sure `/etc/config/network` references the **new** interface names (device sections, ports) — see [Configuration](#configuration).
3. Reboot and verify: `ip link`.

### Uninstall

```sh
./install.sh -u
reboot
```

## Configuration

`/etc/config/mac-static-interfaces`:

```sh
config mac-static-interfaces
	option wan0 "02:11:22:33:44:01"
	option lan0 "02:11:22:33:44:02"
```

- Left side — the target interface name, right side — the adapter MAC (case-insensitive).
- Prefer names that are **not** the stock `eth*`: distinct names like `wan0`/`lan0` prevent collisions on live hotplug (the stock names are still handled fine at boot thanks to the two-pass rename).
- Target names must be at most 15 characters (kernel limit for interface names).
- Then reference the new names in `/etc/config/network`, e.g.:

```sh
config interface 'wan'
	option device 'wan0'
	option proto 'dhcp'
```

## Caveats

- The MAC must be **stable**. Dongles that randomize their MAC (some Realtek chips are known for this) cannot be mapped; ASIX adapters keep their MAC (a finding from the origin thread).
- After enabling the service, `/etc/config/network` **must** reference the new names, otherwise the LAN may break after the first reboot. Keep serial console or recovery access ready.
- Renaming requires bringing the link down; on live hotplug the renamed link drops for a moment and netifd re-attaches it on the next event.
- Interfaces with no mapping entry are never touched.

## Compatibility

- Any OpenWrt release with busybox `ash` — no extra packages required.
- Written for the Raspberry Pi + USB dongle scenario, but works on any hardware where physical NICs expose `/sys/class/net/<i>/device/uevent`.

## Credits and license

- Method: [Persistent Ethernet Interface Naming by MAC Address](https://openwrt.org/docs/guide-user/base-system/persistent-ethernet-interface-naming-by-mac-address) — OpenWrt Wiki, CC BY-SA 4.0.
- Origin: [Stable network interface names for USB Ethernet Dongles](https://forum.openwrt.org/t/stable-network-interface-names-for-usb-ethernet-dongles/98539) — OpenWrt Forum, accepted solution by bobafetthotmail.
- Hotplug example basis: [Hotplug](https://openwrt.org/docs/guide-user/base-system/hotplug) — OpenWrt Wiki.
- This repository: [CC BY-SA 4.0](LICENSE) — see [NOTICE](NOTICE) for the exact breakdown.
