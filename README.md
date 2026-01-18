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

| Package | Description | Architectures |
|---------|-------------|---------------|
| **home-assistant-container** | Home Assistant Core - Podman container | x86_64, aarch64 |
| **matter-server** | Open Home Foundation Matter Server - WebSocket-based Matter controller for Home Assistant | x86_64, aarch64 |
| **chip-sdk** | Matter/CHIP SDK Python bindings | x86_64, aarch64 |
| **otbr** | OpenThread Border Router for Thread/Matter networks | x86_64, aarch64 |
| **occu** | eQ-3 OCCU - HomeMatic CCU core components | x86_64, aarch64 |
| **occu-java** | eQ-3 OCCU - HomeMatic IP Server (Java) | x86_64, aarch64 |
| **zwave-js-ui** | Z-Wave JS UI - Z-Wave Control Panel and MQTT Gateway | x86_64, aarch64 |

### Build Tools

| Package | Description | Architectures |
|---------|-------------|---------------|
| **zap-cli** | ZCL Advanced Platform - code generator for Matter | x86_64, aarch64 |

### 3D Printing

| Package | Description | Architectures |
|---------|-------------|---------------|
| **prusalink** | PrusaLink for Prusa 3D printers | x86_64, aarch64, armhf |

### Languages

| Package | Description | Architectures |
|---------|-------------|---------------|
| **python314** | Python 3.14 - High-level scripting language with PGO/LTO optimizations | x86_64, aarch64 |

### Utilities

| Package | Description | Architectures |
|---------|-------------|---------------|
| **ssh-to-age** | Convert SSH Ed25519 keys to age keys | x86_64, aarch64 |

### Libraries

| Package | Description | Architectures |
|---------|-------------|---------------|
| **gcompat-custom** | glibc compatibility layer (custom build) | x86_64, aarch64 |
| **detect-radio-module** | HomeMatic RF module detection tool | x86_64, aarch64 |

## Package Details

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
- **Image:** `ghcr.io/home-assistant/home-assistant:stable` (configurable)

**USB device passthrough** (Zigbee/Z-Wave): Edit `/etc/conf.d/home-assistant-container`:
```sh
HASS_EXTRA_OPTS="--device /dev/ttyUSB0:/dev/ttyUSB0"
```

**Container management:**
```sh
podman logs -f home-assistant      # View logs
podman exec -it home-assistant bash # Shell access
```

**Diskless setup (Alpine running from RAM):**

For diskless Alpine systems, the setup script pulls the container image and creates a squashfs on the SD card:

```sh
# 1. Install the package
apk add home-assistant-container

# 2. Setup container image (requires network, creates squashfs on SD card)
setup-home-assistant-image

# 3. Start services
rc-service home-assistant-rostore start
rc-service home-assistant-container start
rc-update add home-assistant-rostore boot
rc-update add home-assistant-container default

# 4. Persist with lbu
lbu commit
```

The setup script:
- Temporarily remounts SD card read-write
- Pulls the Home Assistant container image
- Creates a compressed squashfs on the SD card (~400MB)
- Remounts SD card read-only

Requirements:
- Network access during setup
- ~2GB temporary space for image pull
- SD card with ~500MB free space

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

### occu / occu-java

HomeMatic CCU components for HomeMatic IP devices.

```sh
apk add occu-java
rc-service occu-hmserver start
rc-update add occu-hmserver default
```

- **Port:** 32010 (XML-RPC API)
- **Config:** `/etc/occu/config/`
- **Hardware:** HmIP-RFUSB (auto-detected), RPI-RF-MOD

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
