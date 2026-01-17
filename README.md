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
| **home-assistant** | Home Assistant Core - open-source home automation platform | x86_64, aarch64 |
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

### Libraries

| Package | Description | Architectures |
|---------|-------------|---------------|
| **gcompat-custom** | glibc compatibility layer (custom build) | x86_64, aarch64 |
| **detect-radio-module** | HomeMatic RF module detection tool | x86_64, aarch64 |

## Package Details

### home-assistant

Home Assistant Core - open-source home automation platform with bundled integrations.

```sh
apk add home-assistant
rc-service home-assistant start
rc-update add home-assistant default
```

- **Port:** 8123 (Web UI)
- **Config:** `/etc/conf.d/home-assistant`
- **Data:** `/var/lib/homeassistant`
- **Integrations:** MQTT, ZHA (Zigbee), Z-Wave JS, ESPHome, HomeKit

**Alpine/musl limitation:** The `dhcp` component requires `netifaces` which doesn't compile on musl libc. Replace `default_config:` in your `configuration.yaml` with individual components:

<details>
<summary>Click to expand configuration.yaml example</summary>

```yaml
# Individual components (excluding dhcp for Alpine compatibility)
assist_pipeline:
backup:
bluetooth:
cloud:
config:
conversation:
counter:
energy:
frontend:
hardware:
history:
homeassistant_alerts:
image_upload:
input_boolean:
input_button:
input_datetime:
input_number:
input_select:
input_text:
logbook:
logger:
map:
media_source:
mobile_app:
my:
network:
person:
schedule:
scene:
script: !include scripts.yaml
ssdp:
stream:
sun:
system_health:
tag:
timer:
usb:
webhook:
zeroconf:
zone:

automation: !include automations.yaml
```

</details>

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
- **Note:** Used as a build dependency for home-assistant package

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
