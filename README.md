# Alpine Packages

Custom Alpine Linux APK repository built with [melange](https://github.com/chainguard-dev/melange).

## Usage

Add this repository to your Alpine system:

```sh
# Add the signing key
wget -qO /etc/apk/keys/packages@elohmeier.rsa.pub \
  https://elohmeier.github.io/alpine-packages/keys/packages@elohmeier.rsa.pub

# Add the repository (APK appends the architecture automatically)
echo "https://elohmeier.github.io/alpine-packages" >> /etc/apk/repositories

apk update
```

## Available Packages

### Smart Home

| Package                      | Description                                                                               | Architectures   |
| ---------------------------- | ----------------------------------------------------------------------------------------- | --------------- |
| **adaptive-lighting**        | Home Assistant custom integration for adaptive lighting                                   | x86_64, aarch64 |
| **home-assistant-container** | Home Assistant Core - Podman container                                                    | x86_64, aarch64 |
| **matter-server**            | Open Home Foundation Matter Server - WebSocket-based Matter controller for Home Assistant | x86_64, aarch64 |
| **chip-sdk**                 | Matter/CHIP SDK Python bindings                                                           | x86_64, aarch64 |
| **otbr**                     | OpenThread Border Router for Thread/Matter networks                                       | x86_64, aarch64 |
| **openccu-container**        | OpenCCU - HomeMatic CCU running in Podman container                                       | x86_64, aarch64 |
| **pivccu**                   | piVCCU pre-built kernel modules for linux-rpi (includes pivccu-detect subpackage)         | aarch64         |
| **pivccu-akms**              | piVCCU kernel modules source for AKMS (includes pivccu-detect subpackage)                 | aarch64         |
| **zwave-js-ui**              | Z-Wave JS UI - Z-Wave Control Panel and MQTT Gateway                                      | x86_64, aarch64 |
| **universal-silabs-flasher** | Flash Silicon Labs radios (EmberZNet, CPC, Gecko Bootloader)                              | x86_64, aarch64 |

### Build Tools

| Package     | Description                                       | Architectures   |
| ----------- | ------------------------------------------------- | --------------- |
| **zap-cli** | ZCL Advanced Platform - code generator for Matter | x86_64, aarch64 |

### 3D Printing

| Package       | Description                     | Architectures          |
| ------------- | ------------------------------- | ---------------------- |
| **prusalink** | PrusaLink for Prusa 3D printers | x86_64, aarch64, armhf |

### Languages

| Package       | Description                                                            | Architectures   |
| ------------- | ---------------------------------------------------------------------- | --------------- |
| **python314** | Python 3.14 - High-level scripting language with PGO/LTO optimizations | x86_64, aarch64 |

### Document Management

| Package                  | Description                                                      | Architectures   |
| ------------------------ | ---------------------------------------------------------------- | --------------- |
| **ftp-paperless-bridge** | FTP server bridge for network document scanners to paperless-ngx | x86_64, aarch64 |

### Utilities

| Package        | Description                          | Architectures   |
| -------------- | ------------------------------------ | --------------- |
| **ssh-to-age** | Convert SSH Ed25519 keys to age keys | x86_64, aarch64 |

### Observability

| Package    | Description                                                                | Architectures   |
| ---------- | -------------------------------------------------------------------------- | --------------- |
| **vector** | High-performance observability data pipeline for logs, metrics, and traces | x86_64, aarch64 |

## Package Details

### adaptive-lighting

Home Assistant custom integration that automatically adjusts light brightness and color temperature throughout the day.

```sh
apk add adaptive-lighting
rc-service home-assistant-container restart
```

- **Location:** `/var/lib/homeassistant/custom_components/adaptive_lighting/`
- **Requires:** home-assistant-container

After installing, configure via Home Assistant Settings → Devices & Services → Add Integration → Adaptive Lighting.

### home-assistant-container

Home Assistant Core running in a Podman container.

```sh
apk add home-assistant-container
rc-service home-assistant-container start
rc-update add home-assistant-container default
```

- **Port:** 8123 (Web UI)
- **Config:** `/etc/conf.d/home-assistant-container`
- **Data:** `/var/lib/homeassistant`
- **Image:** `ghcr.io/home-assistant/home-assistant:<version>` (configurable via `CONTAINER_IMAGE`)

**What's automated on install:**

- Creates `homeassistant` user with hardware access (dialout, gpio groups)
- Enables dbus and bluetooth services
- Sets up udev rules for Zigbee/Z-Wave USB devices (creates `/dev/zigbee`, `/dev/zwave` symlinks)
- On diskless systems: automatically creates squashfs image on SD card

**USB devices:** Zigbee and Z-Wave adapters are auto-detected. Common devices get symlinks:

- `/dev/zigbee` - Silicon Labs, ConBee, TI CC2531, SMLIGHT adapters
- `/dev/zwave` - Aeotec Z-Stick, Zooz ZST10

**Container management:**

```sh
podman logs -f home-assistant      # View logs
podman exec -it home-assistant bash # Shell access
```

**Diskless systems (Alpine running from RAM):**

Diskless setup is fully automated. On install, the package detects SD card mount points and:

1. Pulls the container image to a tmpfs
2. Creates a compressed squashfs on the SD card (~400MB)
3. Enables the `home-assistant-rostore` service to mount it on boot

Requirements: ~3GB free RAM during initial setup, network access, SD card with ~500MB free.

After install on diskless, just persist and start:

```sh
lbu commit
rc-service home-assistant-container start
rc-update add home-assistant-container default
```

Package upgrades on diskless systems automatically rebuild the squashfs image.

### matter-server

WebSocket-based Matter controller that integrates with Home Assistant.

```sh
apk add matter-server
rc-service matter-server start
rc-update add matter-server default
```

- **Port:** 5580 (WebSocket API)
- **Config:** `/etc/conf.d/matter-server`
- **Data:** `/var/lib/matter-server`

### otbr

OpenThread Border Router for Thread/Matter mesh networks.

```sh
apk add otbr
rc-service otbr-agent start
rc-update add otbr-agent default
```

- **Port:** 8081 (REST API)
- **Config:** `/etc/conf.d/otbr-agent`
- **Hardware:** Requires Thread RCP firmware (SkyConnect, Yellow, etc.)

### openccu-container

OpenCCU (HomeMatic CCU) running in a Podman container.

```sh
apk add openccu-container
rc-service openccu-container start
rc-update add openccu-container default
```

- **Port:** 80 (Web UI, configurable via `CONTAINER_PORT`)
- **Config:** `/etc/conf.d/openccu-container`
- **Data:** `/var/lib/openccu`
- **Image:** `ghcr.io/openccu/openccu:<version>` (configurable via `CONTAINER_IMAGE`)
- **Hardware:** Requires HomeMatic kernel modules (pivccu) for RPI-RF-MOD, HmIP-RFUSB

### pivccu / pivccu-akms

HomeMatic RF hardware detection and kernel module support. Two variants available:

**pivccu** - Pre-built kernel modules for linux-rpi (diskless compatible)

- **pivccu** - Pre-built kernel modules (main package)
- **pivccu-detect** - RF hardware detection utility (`detect_radio_module`)

**pivccu-akms** - Kernel module sources for AKMS (builds on install)

- **pivccu-akms** - Kernel module sources (main package)
- **pivccu-detect** - RF hardware detection utility (`detect_radio_module`)

**For diskless Alpine on RPi5 (recommended):**

```sh
apk add pivccu
rc-update add pivccu-modules boot
```

**For standard Alpine with AKMS:**

```sh
apk add pivccu-akms
# AKMS will automatically build modules for your kernel
```

- **Modules:** `generic_raw_uart`, `eq3_char_loop`, `pl011_raw_uart`, `rpi_rf_mod_led`
- **Devices:** `/dev/raw-uart`, `/dev/eq3loop`
- **Device tree overlay:** `pivccu-raspberrypi` (add to `usercfg.txt`)

**Setup for RPI-RF-MOD:**

1. Install the package
2. Add `dtoverlay=pivccu-raspberrypi` to `/media/mmcblk0p1/usercfg.txt` (or `/boot/usercfg.txt`)
3. Reboot
4. Verify with `ls /dev/raw-uart /dev/eq3loop`

### zwave-js-ui

Z-Wave JS UI - Full-featured Z-Wave Control Panel and MQTT Gateway.

```sh
apk add zwave-js-ui
rc-service zwave-js-ui start
rc-update add zwave-js-ui default
```

- **Port:** 8091 (Web UI), 3000 (Z-Wave JS WebSocket)
- **Config:** `/etc/conf.d/zwave-js-ui`
- **Data:** `/var/lib/zwave-js-ui`
- **Hardware:** Z-Wave USB sticks (Aeotec, Zooz, etc.)

Configure Home Assistant Z-Wave JS integration to connect to `ws://HOST:3000`.

### python314

Python 3.14 with PGO (Profile-Guided Optimization) and LTO (Link-Time Optimization). Built for musl libc with zstd compression support.

```sh
apk add python314
```

- **Binary:** `/usr/bin/python3.14`
- **Features:** PGO, LTO, zstd compression (stdlib), shared library
- **Note:** Available for projects requiring Python 3.14

### ftp-paperless-bridge

FTP server that accepts scanned documents from network-enabled scanners and forwards them to paperless-ngx.

```sh
apk add ftp-paperless-bridge
# Edit configuration first:
vi /etc/conf.d/ftp-paperless-bridge
rc-service ftp-paperless-bridge start
rc-update add ftp-paperless-bridge default
```

- **Ports:** 2121 (FTP), 2122-2124 (passive mode)
- **Config:** `/etc/conf.d/ftp-paperless-bridge`
- **Required settings:** `FTP_PAPERLESS_BRIDGE_PAPERLESS_URL`, `FTP_PAPERLESS_BRIDGE_PAPERLESS_API_TOKEN`, change default `FTP_PAPERLESS_BRIDGE_PASSWORD`

Point your scanner's FTP upload to `<host>:2121` with the configured credentials.

### vector

High-performance observability data pipeline for collecting, transforming, and routing logs, metrics, and traces.

```sh
apk add vector
rc-service vector start
rc-update add vector default
```

- **Config:** `/etc/vector/vector.yaml`
- **Data:** `/var/lib/vector`
- **Service config:** `/etc/conf.d/vector`

## Building Locally

```sh
melange keygen
melange build <package>.yaml --signing-key melange.rsa
```

## CI Setup

The GitHub Actions workflow requires:

1. `ABUILD_PRIVKEY` secret - the private signing key
2. GitHub Pages enabled for the repository

## License

MIT
