# openwrt-staticeth

[English](README.md) | [Русский](README.ru.md) | **Deutsch**

Persistente Benennung von Ethernet-Interfaces nach MAC-Adresse für OpenWrt: Der Name eines Netzwerkadapters hängt nicht mehr von der USB-Erkennungsreihenfolge beim Boot ab.

Das gelöste Problem: Single-Board-Router (Raspberry Pi & Co.) haben nur eine eingebaute NIC, zusätzliche Interfaces kommen als USB-Ethernet-Adapter. Bei jedem Boot kann der Kernel sie in anderer Reihenfolge erkennen — `eth0`, `eth1`, `eth2` wechseln die Plätze, und die UCI-Netzwerkkonfiguration beschreibt plötzlich die falschen Geräte. `staticeth` heftet jeden Adapter über seine MAC-Adresse an einen festen Interface-Namen.

Die Methode stammt von der offiziellen OpenWrt-Wiki-Seite [Persistent Ethernet Interface Naming by MAC Address](https://openwrt.org/docs/guide-user/base-system/persistent-ethernet-interface-naming-by-mac-address), die aus [diesem Foren-Thread](https://forum.openwrt.org/t/stable-network-interface-names-for-usb-ethernet-dongles/98539) hervorgegangen ist. Dieses Repo verpackt sie mit Hotplug-Begleiter, Installer und Dokumentation. Lizenz: CC BY-SA 4.0 (siehe [NOTICE](NOTICE)).

## Bestandteile

| № | Datei im Repo | Pfad auf dem Router | Zweck |
|---|---------------|---------------------|-------|
| 1 | `files/etc/init.d/staticeth` | `/etc/init.d/staticeth` | Init-Skript (`START=11`, vor `network`): Umbenennung beim Boot |
| 2 | `files/etc/hotplug.d/net/90-staticeth` | `/etc/hotplug.d/net/90-staticeth` | Hotplug-Begleiter: benennt Adapter um, die im laufenden Betrieb angesteckt werden |
| 3 | `files/etc/config/mac-static-interfaces.example` | `/etc/config/mac-static-interfaces` | MAC → Name-Zuordnung (UCI-Syntax) |
| 4 | `install.sh` | — | Installer / Deinstaller, auf dem Router ausführen |

## Funktionsweise

### Boot (Init-Skript)

- `START=11` — vor dem Dienst `network`.
- Nur physische Interfaces werden angefasst: Aufzählung über `/sys/class/net/*/device/uevent`, Bridges und virtuelle Interfaces werden automatisch ausgeschlossen.
- Durchlauf 1: jedes Interface, dessen aktueller Name in der Zuordnung vorkommt, wird heruntergefahren und als `old<name>` geparkt — dadurch werden alle Zielnamen frei, ein Swap ist unmöglich.
- Durchlauf 2: die MAC jedes Interfaces (`/sys/class/net/<i>/address`) wird in der Zuordnung nachgeschlagen, das Interface erhält seinen Zielnamen.

### Live-Hotplug (Begleiter)

- Reagiert nur auf `add`-Events und nur für physische Geräte.
- Benennt nur um, wenn der Zielname gerade frei ist; belegte Namen werden im Laufzeitbetrieb nie getauscht.
- Liest dieselbe Zuordnungsdatei wie das Init-Skript.

## Installation

### Aus einem Release (empfohlen)

`.apk` (OpenWrt 25.12+) oder `.ipk` (OpenWrt 23.x) von der [Releases](https://github.com/nagual2/openwrt-staticeth/releases)-Seite herunterladen und auf dem Router installieren:

```sh
scp -O staticeth-1.0.0-r1.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1
apk add --allow-untrusted /tmp/staticeth-1.0.0-r1.apk     # OpenWrt 25.12+
# opkg install /tmp/staticeth_1.0.0-r1_all.ipk            # OpenWrt 23.x
```

Das Paket installiert beide Skripte, erzeugt `/etc/config/mac-static-interfaces` aus dem beigefügten Beispiel (falls nicht vorhanden) und aktiviert den Dienst. Weiter mit den MAC/Netzwerk-Schritten unten.

### Aus dem Quellrepo

Repo auf den Router kopieren und Installer ausführen:

```sh
scp -r openwrt-staticeth root@192.168.1.1:/tmp/
ssh root@192.168.1.1
cd /tmp/openwrt-staticeth
./install.sh
```

(Gegen Dropbear mit OpenSSH 9.x: `scp -O -r ...`.)

Danach:

1. Die echten MAC-Adressen in `/etc/config/mac-static-interfaces` eintragen.
   Aktuelle auflisten: `grep -H . /sys/class/net/*/address`
2. Sicherstellen, dass `/etc/config/network` die **neuen** Interface-Namen verwendet (device-Abschnitte, ports) — siehe [Konfiguration](#konfiguration).
3. Neustart und Prüfung: `ip link`.

### Deinstallation

```sh
./install.sh -u
reboot
```

## Konfiguration

`/etc/config/mac-static-interfaces`:

```sh
config mac-static-interfaces
	option wan0 "02:11:22:33:44:01"
	option lan0 "02:11:22:33:44:02"
```

- Links der Ziel-Interface-Name, rechts die MAC des Adapters (Groß-/Kleinschreibung egal).
- Namen besser wählen, die **nicht** die Standard-`eth*` sind: eigene Namen wie `wan0`/`lan0` vermeiden Kollisionen beim Live-Hotplug (die Standardnamen funktionieren beim Boot dank Zwei-Durchlauf-Umbenennung trotzdem).
- Zielnamen höchstens 15 Zeichen (Kernel-Limit für Interface-Namen).
- Danach die neuen Namen in `/etc/config/network` referenzieren, z. B.:

```sh
config interface 'wan'
	option device 'wan0'
	option proto 'dhcp'
```

## Einschränkungen

- Die MAC muss **stabil** sein. Adapter mit randomisierter MAC (manche Realtek-Chips sind dafür bekannt) lassen sich nicht zuordnen; ASIX-Adapter behalten ihre MAC (Erkenntnis aus dem Ursprungs-Thread).
- Nach der Aktivierung MUSS `/etc/config/network` die neuen Namen verwenden, sonst kann das LAN nach dem ersten Neustart brechen. Serielle Konsole oder Wiederherstellungszugang bereithalten.
- Umbenennen erfordert das Abschalten des Links; beim Live-Hotplug fällt der umbenannte Link kurz aus, netifd bindet ihn beim nächsten Event wieder an.
- Interfaces ohne Eintrag in der Zuordnung werden nie angefasst.

## Kompatibilität

- Jede OpenWrt-Version mit busybox `ash` — keine zusätzlichen Pakete nötig.
- Für das Szenario Raspberry Pi + USB-Adapter geschrieben, funktioniert aber auf jeder Hardware, deren physische NICs `/sys/class/net/<i>/device/uevent` bereitstellen.

## Credits und Lizenz

- Methode: [Persistent Ethernet Interface Naming by MAC Address](https://openwrt.org/docs/guide-user/base-system/persistent-ethernet-interface-naming-by-mac-address) — OpenWrt Wiki, CC BY-SA 4.0.
- Ursprung: [Stable network interface names for USB Ethernet Dongles](https://forum.openwrt.org/t/stable-network-interface-names-for-usb-ethernet-dongles/98539) — OpenWrt Forum, akzeptierte Lösung von bobafetthotmail.
- Grundlage des Hotplug-Beispiels: [Hotplug](https://openwrt.org/docs/guide-user/base-system/hotplug) — OpenWrt Wiki.
- Dieses Repository: [CC BY-SA 4.0](LICENSE) — Details in [NOTICE](NOTICE).
