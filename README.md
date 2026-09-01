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
| **homematicip-local**        | Local Homematic and Homematic IP integration for Home Assistant                           | x86_64, aarch64 |
| **home-assistant-container** | Home Assistant Core - Podman container                                                    | x86_64, aarch64 |
| **home-assistant-watch**     | Watchdog: restart Home Assistant if its recorder stops writing                            | x86_64, aarch64 |
| **certificate-sync**         | Synchronize cert-manager certificates to multiple infrastructure appliances               | x86_64, aarch64 |
| **opnsense-cert-sync**       | Synchronize a cert-manager certificate to the OPNsense Web GUI                            | x86_64, aarch64 |
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

### Document Management

| Package                  | Description                                                      | Architectures   |
| ------------------------ | ---------------------------------------------------------------- | --------------- |
| **ftp-paperless-bridge** | FTP server bridge for network document scanners to paperless-ngx | x86_64, aarch64 |

### Utilities

| Package                | Description                                              | Architectures   |
| ---------------------- | -------------------------------------------------------- | --------------- |
| **acarsdec**           | ACARS decoder with RTL-SDR, libacars, JSON, and MQTT     | x86_64, aarch64 |
| **ais-catcher**        | AIS receiver with RTL-SDR support                        | x86_64, aarch64 |
| **dumpvdl2**           | VDL Mode 2 decoder with RTL-SDR, SQLite, and ZeroMQ      | x86_64, aarch64 |
| **hf40-restic-backup** | Root restic backup runtime and six-hour scheduler        | x86_64, aarch64 |
| **libacars**           | ACARS message decoding library                           | x86_64, aarch64 |
| **libacars-dev**       | Development headers and pkg-config metadata for libacars | x86_64, aarch64 |
| **liquid-dsp**         | Digital signal processing library for SDR applications   | x86_64, aarch64 |
| **liquid-dsp-dev**     | Development headers and build metadata for liquid-dsp    | x86_64, aarch64 |
| **multimon-ng**        | Digital radio transmission decoder                       | x86_64, aarch64 |
| **multimon-ng-tools**  | Signal generators for multimon-ng                        | x86_64, aarch64 |
| **redsea**             | FM-RDS decoder with newline-delimited JSON output        | x86_64, aarch64 |
| **ssh-to-age**         | Convert SSH Ed25519 keys to age keys                     | x86_64, aarch64 |
| **welle-cli**          | Command-line DAB/DAB+ receiver using bundled Kiss FFT    | x86_64, aarch64 |

### AI / Developer Tools

| Package   | Description                                      | Architectures   |
| --------- | ------------------------------------------------ | --------------- |
| **codex** | OpenAI Codex CLI - coding agent for the terminal | x86_64, aarch64 |

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

### homematicip-local

Actively maintained local integration for Homematic and Homematic IP devices connected to a CCU.

```sh
apk add homematicip-local
rc-service home-assistant-container restart
```

- **Location:** `/var/lib/homeassistant/custom_components/homematicip_local/`
- **Requires:** Home Assistant 2026.7.0 or newer

After installing, configure via Home Assistant Settings → Devices & Services → Add Integration → Homematic(IP) Local for OpenCCU.

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

### home-assistant-watch

Watchdog that polls Home Assistant's REST API for a recently-updating entity. If the entity is updating in `/api/states` (HA is alive in-memory) but its `/api/history/period` response is empty (recorder DB is silent), the recorder integration is dead and the watchdog calls `rc-service home-assistant-container restart`.

This guards against a specific HA failure mode: when the recorder integration fails its one-shot setup at boot (e.g., the Postgres backend was briefly unreachable), HA keeps running but never retries, silently dropping history forever until the next manual restart.

```sh
apk add home-assistant-watch
$EDITOR /etc/conf.d/home-assistant-watch  # set HASS_WATCH_TOKEN, HASS_WATCH_ENTITY
rc-service home-assistant-watch start
rc-update add home-assistant-watch default
```

- **Service:** `home-assistant-watch`
- **Config:** `/etc/conf.d/home-assistant-watch`
- **Log:** `/var/log/home-assistant-watch.log`
- **Required vars:** `HASS_WATCH_TOKEN` (LLA token), `HASS_WATCH_ENTITY` (frequently-updating sensor)
- **Defaults:** probe every 60s, restart after 5 consecutive failures, 5-min grace period, 30-min minimum between restarts

Generate `HASS_WATCH_TOKEN` via HA UI → Profile → Security → Long-lived Access Tokens. Pick `HASS_WATCH_ENTITY` carefully — it must update at least every couple of minutes, otherwise the probe falsely concludes the recorder is dead. Power meters, ESPHome BME280s, and similar high-rate sensors work well.

### certificate-sync

Reusable certificate delivery for appliances that cannot consume cert-manager
Secrets directly. Each `/etc/certificate-sync.d/<target>.conf` selects one TLS
Secret and one adapter. Included adapters support the OPNsense certificate API
and a forced-command SSH installer for OpenCCU.

```sh
apk add certificate-sync
$EDITOR /etc/conf.d/certificate-sync
$EDITOR /etc/certificate-sync.d/gateway.conf
certificate-sync --check-config
certificate-sync --all
```

- **Schedule:** `/etc/periodic/hourly/certificate-sync`
- **Targets:** `/etc/certificate-sync.d/*.conf`
- **State:** `/var/lib/certificate-sync/<target>/state` (non-secret)
- **Metrics:** `certificate-sync --metrics` emits `target` and `hostname` tags
- **Safety:** adapters validate before delivery, verify the live fingerprint
  and strict TLS afterward, and roll back their appliance independently

### opnsense-cert-sync

Hourly, fingerprint-driven synchronization of a cert-manager TLS Secret to the
certificate entry selected by the OPNsense Web GUI. Certificate and private-key
matching is checked before import, and the served certificate is verified after
the Web GUI restart. Kubernetes and OPNsense credentials are read from root-only
files provisioned separately.

```sh
apk add opnsense-cert-sync
$EDITOR /etc/conf.d/opnsense-cert-sync
opnsense-cert-sync --check-config
opnsense-cert-sync
```

- **Schedule:** `/etc/periodic/hourly/opnsense-cert-sync`
- **Config:** `/etc/conf.d/opnsense-cert-sync`
- **State:** `/var/lib/opnsense-cert-sync/state` (fingerprints and timestamps only)
- **Recovery:** an expired currently served certificate is trusted only when its
  SPKI matches the last successfully installed pin

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
