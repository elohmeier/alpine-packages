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

When adding a new package, update these files:

### 1. Create package files

```
<package>.yaml           # melange build definition
<package>/               # supporting files (optional)
  <package>.initd        # OpenRC init script
  <package>.confd        # OpenRC config
  99-<package>.rules     # udev rules
```

### 2. Update `.github/workflows/build.yaml`

Add in order:

1. **outputs** (detect-changes job):
   ```yaml
   build-<package>: ${{ steps.matrix.outputs.build-<package> }}
   ```

2. **file filters** (detect-changes job):
   ```yaml
   <package>:
     - '<package>.yaml'
     - '<package>/**'
   ```

3. **version check loop** - add package name to the `for pkg in ...` list

4. **env vars** (compute matrix step):
   ```yaml
   FILE_<PACKAGE>: ${{ steps.file-changes.outputs.<package> }}
   VERSION_<PACKAGE>: ${{ steps.version-check.outputs.<package>_version_changed }}
   ```

5. **build variables** - add `build_<package>="false"` and set to `"true"` in rebuild_all block

6. **individual check**:
   ```yaml
   if [[ "$FILE_<PACKAGE>" == "true" ]]; then
     if [[ "$VERSION_<PACKAGE>" == "true" ]]; then
       build_<package>="true"
     else
       echo "::warning::<package> files changed but version not bumped - skipping build"
     fi
   fi
   ```

7. **dependency propagation** (if package depends on another):
   ```yaml
   if [[ "$build_<dependency>" == "true" && "$build_<package>" != "true" ]]; then
     echo "::notice::<package> will rebuild due to <dependency> dependency"
     build_<package>="true"
   fi
   ```

8. **output and summary**:
   ```yaml
   echo "build-<package>=$build_<package>" >> "$GITHUB_OUTPUT"
   echo "| <package> | $build_<package> |" >> "$GITHUB_STEP_SUMMARY"
   ```

9. **any-builds check** - add `|| "$build_<package>" == "true"` to the condition

10. **build job** - add new job following existing patterns (standalone or with dependencies)

11. **publish job** - add to `needs:` list

### 3. Update `README.md`

Add package to the appropriate category table and add a "Package Details" section if it's a user-facing package with services.

### 4. Update `index.html`

The package table is auto-generated from APKINDEX during publish - no manual update needed.

## Relevant sources

- $HOME/repos/github.com/chainguard-dev/melange
- $HOME/repos/github.com/chainguard-dev/actions
- $HOME/repos/github.com/wolfi-dev/os
