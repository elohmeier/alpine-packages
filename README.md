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
