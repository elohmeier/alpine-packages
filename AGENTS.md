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

Build and test workflow:

```bash
# 1. Build the package
melange build --arch arm64 --signing-key local-melange.rsa \
  --repository-append ./packages --keyring-append local-melange.rsa.pub \
  <package>.yaml

# 2. Run tests against the built package
melange test --arch arm64 \
  --repository-append ./packages --keyring-append local-melange.rsa.pub \
  <package>.yaml
```

Inspect package contents:

```bash
# List files in package
tar -tzf packages/aarch64/<package>-<version>.apk

# Extract and check specific file
tar -xzf packages/aarch64/<package>-<version>.apk -O <path/to/file>
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

## Adding a New Package

1. **Create package files**:
   ```
   <package>.yaml           # melange build definition (must include target-architecture)
   <package>/               # supporting files (optional)
     <package>.initd        # OpenRC init script
     <package>.confd        # OpenRC config
     99-<package>.rules     # udev rules
   ```

2. **Required fields in `<package>.yaml`**:
   ```yaml
   package:
     name: <package>
     version: "1.0.0"
     epoch: 0
     target-architecture:    # Required - specify all target architectures
       - x86_64
       - aarch64
   ```

3. **Update `README.md`** - add package to the appropriate category table.

That's it. The workflow automatically:
- Discovers new packages by scanning `*.yaml` files
- Detects dependencies from `package.dependencies.runtime` and `environment.contents.packages`
- Computes build order using topological sort
- Builds only when files change AND version differs from published

### Testing locally

```bash
# Preview the build matrix
REBUILD_ALL=true uv run generate-matrix

# Test change detection
BASE_REF=HEAD~1 uv run generate-matrix
```

## Relevant sources

- $HOME/repos/github.com/chainguard-dev/melange
- $HOME/repos/github.com/chainguard-dev/actions
- $HOME/repos/github.com/wolfi-dev/os
