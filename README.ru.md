# openwrt-staticeth

[English](README.md) | **Русский** | [Deutsch](README.de.md)

Постоянная привязка имён Ethernet-интерфейсов к MAC-адресам для OpenWrt: имя сетевого адаптера больше не зависит от порядка опроса USB-адаптеров при загрузке.

Решаемая проблема: одноплатные роутеры (Raspberry Pi и подобные) имеют один встроенный NIC, дополнительные интерфейсы появляются как USB-Ethernet-свистки. При каждой перезагрузке ядро может опрашивать их в другом порядке — `eth0`, `eth1`, `eth2` меняются местами, и сетевая конфигурация UCI внезапно описывает не те устройства. `staticeth` закрепляет каждый адаптер за постоянным именем интерфейса по его MAC-адресу.

Метод взят с официальной страницы вики OpenWrt [Persistent Ethernet Interface Naming by MAC Address](https://openwrt.org/docs/guide-user/base-system/persistent-ethernet-interface-naming-by-mac-address), которая выросла из [этой ветки форума](https://forum.openwrt.org/t/stable-network-interface-names-for-usb-ethernet-dongles/98539). Этот репозиторий оформляет решение: hotplug-компаньон, установщик и документация. Лицензия: CC BY-SA 4.0 (см. [NOTICE](NOTICE)).

## Состав

| № | Файл в репо | Путь на роутере | Назначение |
|---|-------------|-----------------|------------|
| 1 | `files/etc/init.d/staticeth` | `/etc/init.d/staticeth` | Init-скрипт (`START=11`, раньше `network`): переименование при загрузке |
| 2 | `files/etc/hotplug.d/net/90-staticeth` | `/etc/hotplug.d/net/90-staticeth` | Hotplug-компаньон: переименование адаптеров, воткнутых в работающую систему |
| 3 | `files/etc/config/mac-static-interfaces.example` | `/etc/config/mac-static-interfaces` | Маппинг MAC → имя (синтаксис UCI) |
| 4 | `install.sh` | — | Установщик / деинсталлятор, запускать на роутере |

## Как это работает

### Загрузка (init-скрипт)

- `START=11` — раньше сервиса `network`.
- Обрабатываются только физические интерфейсы: перечисление через `/sys/class/net/*/device/uevent`, мосты и виртуалки исключаются автоматически.
- Проход 1: каждый интерфейс, чьё текущее имя встречается в маппинге, выключается и переименовывается в `old<имя>` — так освобождаются все целевые имена, свопинг невозможен.
- Проход 2: MAC каждого интерфейса (`/sys/class/net/<i>/address`) ищется в маппинге, интерфейс получает целевое имя.

### Живой hotplug (компаньон)

- Срабатывает только на события `add` и только для физических устройств.
- Переименовывает только когда целевое имя свободно; занятые имена на живую не свопятся.
- Читает тот же файл маппинга, что и init-скрипт.

## Установка

### Из релиза (рекомендуется)

Скачайте `.apk` (OpenWrt 25.12+) или `.ipk` (OpenWrt 23.x) со страницы [Releases](https://github.com/nagual2/openwrt-staticeth/releases) и установите на роутер:

```sh
scp -O staticeth-1.0.0-r1.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1
apk add --allow-untrusted /tmp/staticeth-1.0.0-r1.apk     # OpenWrt 25.12+
# opkg install /tmp/staticeth_1.0.0-r1_all.ipk            # OpenWrt 23.x
```

Пакет устанавливает оба скрипта, создаёт `/etc/config/mac-static-interfaces` из примера, если его ещё нет, и включает сервис. Дальше — шаги с MAC и сетью ниже.

### Из исходников

Скопируйте репозиторий на роутер и запустите установщик:

```sh
scp -r openwrt-staticeth root@192.168.1.1:/tmp/
ssh root@192.168.1.1
cd /tmp/openwrt-staticeth
./install.sh
```

(Против dropbear из OpenSSH 9.x используйте `scp -O -r ...`.)

Затем:

1. Впишите реальные MAC-адреса в `/etc/config/mac-static-interfaces`.
   Список текущих: `grep -H . /sys/class/net/*/address`
2. Убедитесь, что `/etc/config/network` ссылается на **новые** имена интерфейсов (device-секции, ports) — см. [Настройка](#настройка).
3. Перезагрузитесь и проверьте: `ip link`.

### Удаление

```sh
./install.sh -u
reboot
```

## Настройка

`/etc/config/mac-static-interfaces`:

```sh
config mac-static-interfaces
	option wan0 "02:11:22:33:44:01"
	option lan0 "02:11:22:33:44:02"
```

- Слева — целевое имя интерфейса, справа — MAC адаптера (регистр не важен).
- Предпочтительны имена, которые **не** являются стоковыми `eth*`: отдельные имена вроде `wan0`/`lan0` исключают коллизии при живом hotplug (стоковые имена при загрузке всё равно корректно обрабатываются двухпроходным переименованием).
- Целевые имена — не длиннее 15 символов (ограничение ядра на имена интерфейсов).
- Затем сослаться на новые имена в `/etc/config/network`, например:

```sh
config interface 'wan'
	option device 'wan0'
	option proto 'dhcp'
```

## Ограничения

- MAC должен быть **стабильным**. Свистки с рандомизацией MAC (некоторые чипы Realtek этим славятся) привязать нельзя; адаптеры ASIX свой MAC сохраняют (наблюдение из первоисточника).
- После включения сервиса `/etc/config/network` **обязан** ссылаться на новые имена, иначе LAN может сломаться после первой перезагрузки. Держите под рукой серийную консоль или доступ для восстановления.
- Переименование требует выключения линка; при живом hotplug линк на мгновение падает, netifd переподхватывает его на следующем событии.
- Интерфейсы без записи в маппинге не трогаются.

## Совместимость

- Любой релиз OpenWrt с busybox `ash` — дополнительные пакеты не нужны.
- Заточено под сценарий Raspberry Pi + USB-свистки, но работает на любом железе, где физические NIC отдают `/sys/class/net/<i>/device/uevent`.

## Благодарности и лицензия

- Метод: [Persistent Ethernet Interface Naming by MAC Address](https://openwrt.org/docs/guide-user/base-system/persistent-ethernet-interface-naming-by-mac-address) — OpenWrt Wiki, CC BY-SA 4.0.
- Первоисточник: [Stable network interface names for USB Ethernet Dongles](https://forum.openwrt.org/t/stable-network-interface-names-for-usb-ethernet-dongles/98539) — ветка форума OpenWrt, принятое решение bobafetthotmail.
- Основа hotplug-примера: [Hotplug](https://openwrt.org/docs/guide-user/base-system/hotplug) — OpenWrt Wiki.
- Этот репозиторий: [CC BY-SA 4.0](LICENSE) — разбивка в [NOTICE](NOTICE).
