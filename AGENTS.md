# alpine-packages repository

## Layout

```
<package>.yaml      # melange build definition
<package>/          # supporting files (init scripts, config, udev rules)
```

## Building

```bash
melange build --arch arm64 <package>.yaml
```

## Local Development

Generate a local signing key (one-time):

```bash
melange keygen local-melange.rsa
```

Build a package with local dependencies (e.g., matter-server depends on zap-cli):

```bash
# Build dependency first
melange build --arch arm64 --signing-key local-melange.rsa zap-cli.yaml

# Build package with local repo
melange build --arch arm64 --signing-key local-melange.rsa \
  --repository-append ./packages --keyring-append local-melange.rsa.pub \
  matter-server.yaml
```

Run tests:

```bash
melange test --arch arm64 \
  --repository-append ./packages --keyring-append local-melange.rsa.pub \
  <package>.yaml
```

## Caching

Melange uses `./melange-cache/` as the default cache directory. Configure package-level caching via environment variables in the yaml:

```yaml
environment:
  environment:
    npm_config_cache: /var/cache/melange/npm
    PIP_CACHE_DIR: /var/cache/melange/pip
    CCACHE_DIR: /var/cache/melange/ccache
```

The `/var/cache/melange/` path inside the container maps to `./melange-cache/` on the host.

## CI/CD

GitHub Actions builds packages on push to main using `chainguard-dev/actions/melange-build-pkg`. Packages are published to GitHub Pages at `https://elohmeier.github.io/alpine-packages/<arch>/`.

Required secret: `ABUILD_PRIVKEY` (RSA signing key)

## Relevant sources

- $HOME/repos/github.com/chainguard-dev/melange
- $HOME/repos/github.com/chainguard-dev/actions
- $HOME/repos/github.com/wolfi-dev/os
