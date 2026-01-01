# Alpine Packages

Custom Alpine Linux APK repository for armhf (armv6).

## Packages

- **prusalink** - Web interface and REST API for Prusa 3D printers

## Usage

Add this repository to your Alpine system:

```sh
# Add the signing key
wget -qO /etc/apk/keys/packages@elohmeier.rsa.pub \
  https://raw.githubusercontent.com/elohmeier/alpine-packages/main/keys/packages@elohmeier.rsa.pub

# Add the repository (APK appends the architecture automatically)
echo "https://elohmeier.github.io/alpine-packages" >> /etc/apk/repositories

# Update and install prusalink
apk update
apk add prusalink
```

## Building Packages Locally

### Generate Signing Keys

```sh
# Generate a new keypair (do this once)
abuild-keygen -a -i -n
```

### Build a Package

```sh
cd packages/prusalink
abuild -r
```

## CI Setup

The GitHub Actions workflow requires:

1. `ABUILD_PRIVKEY` secret - the private signing key
2. GitHub Pages enabled for the repository

## License

MIT
