# alpine-packages repository

## Layout

```
<package>.yaml      # melange build definition
<package>/          # supporting files (init scripts, config, udev rules)
pipelines/          # reusable melange pipelines
  test/             # test pipelines (e.g., podman-container.yaml)
.mise/tasks/        # mise task scripts
```

## mise Configuration

The `mise.toml` configures environment variables for melange. With mise activated, commands use these defaults automatically:

```bash
# Instead of:
melange build --arch arm64 --signing-key local-melange.rsa \
  --repository-append ./packages --keyring-append local-melange.rsa.pub \
  --pipeline-dirs ./pipelines <package>.yaml

# Just run:
melange build <package>.yaml
melange test <package>.yaml
```

Key environment variables:

- `MELANGE_ARCH` - target architecture (arm64)
- `MELANGE_SIGNING_KEY` - signing key path
- `MELANGE_REPOSITORY_APPEND` / `MELANGE_KEYRING_APPEND` - local repo
- `MELANGE_PIPELINE_DIRS` - custom pipeline directory
- `MELANGE_TEST_RUNNER` - test runner (qemu)
- `QEMU_KERNEL_IMAGE` / `QEMU_KERNEL_MODULES` - kernel for QEMU tests

### mise Tasks

```bash
mise run fetch-kernel [arch]   # Download Alpine linux-virt kernel for QEMU testing
mise run resign-packages [arch] # Resign all packages and regenerate APKINDEX
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
     target-architecture: # Required - specify all target architectures
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

## Podman Container Packages

For wrapping container images as Alpine packages with OpenRC integration and diskless system support, use `podman-container-common` as a dependency.

### Reference Design: podinfo-container

`podinfo-container.yaml` demonstrates the pattern:

```yaml
package:
  name: <name>-container
  dependencies:
    runtime:
      - podman-container-common
      - aardvark-dns
      - netavark
```

Required files in `<name>-container/`:

- `<name>-container.initd` - OpenRC init script
- `<name>-container.confd` - configuration defaults

### Init Script Pattern

```sh
#!/sbin/openrc-run
. /usr/lib/podman-container/functions.sh

name="<name>-container"
CONTAINER_NAME="<name>"
: ${CONTAINER_IMAGE:="<registry>/<image>:<version>"}

depend() {
    need net cgroups
    after firewall
}

start_pre() {
    wait_for_podman || return 1
    # Mount squashfs if available (diskless mode), otherwise pull on first run
    if ! ensure_rostore_mounted "$CONTAINER_NAME" "$CONTAINER_IMAGE"; then
        einfo "No rostore image found, will pull on first run"
    fi
    podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

start() {
    ebegin "Starting ${name}"
    local storage_conf
    storage_conf=$(get_storage_conf "$CONTAINER_IMAGE")
    CONTAINERS_STORAGE_CONF="$storage_conf" \
    podman run -d --rm --name "$CONTAINER_NAME" \
        -p <host-port>:<container-port> \
        ${CONTAINER_EXTRA_OPTS} \
        "$CONTAINER_IMAGE" >/dev/null 2>&1
    eend $?
}

stop() {
    ebegin "Stopping ${name}"
    podman stop -t 30 "$CONTAINER_NAME" 2>/dev/null
    eend $?
}

status() {
    container_status "$CONTAINER_NAME"
}
```

### podman-container-common Functions

Located in `/usr/lib/podman-container/functions.sh`:

| Function                                   | Description                                                    |
| ------------------------------------------ | -------------------------------------------------------------- |
| `sanitize_image_ref <image>`               | Convert image ref to filesystem-safe name                      |
| `find_sd_mount`                            | Find SD card mount (/media/mmcblk0p1, /media/sda1, /media/usb) |
| `get_squashfs_path <name> <image> [mount]` | Get squashfs file path on SD card                              |
| `get_rostore_mount <image>`                | Get read-only store mount path                                 |
| `ensure_rostore_mounted <name> <image>`    | Mount squashfs if available                                    |
| `unmount_rostore <image>`                  | Unmount read-only store                                        |
| `get_storage_conf <image>`                 | Generate storage.conf (includes rostore if mounted)            |
| `wait_for_podman`                          | Wait for podman to be ready                                    |
| `container_status <name>`                  | Check if container is running                                  |

### setup-container-image Script

For diskless systems, `/usr/bin/setup-container-image` creates squashfs images on SD card:

```bash
# Initial setup - pulls image and creates squashfs
setup-container-image podinfo ghcr.io/stefanprodan/podinfo:6.9.4

# Upgrade - replaces existing squashfs with new version
setup-container-image podinfo ghcr.io/stefanprodan/podinfo:6.9.5 --upgrade
```

### Testing Container Packages

Use composable test pipelines for integration testing. Pipelines can be chained together in sequence.

**Available test pipelines:**

| Pipeline                    | Description                                   | Needs                   |
| --------------------------- | --------------------------------------------- | ----------------------- |
| `test/openrc-start`         | Start an OpenRC service                       | `openrc`                |
| `test/openrc-stop`          | Stop an OpenRC service                        | `openrc`                |
| `test/podman-verify-stopped`| Verify Podman containers are stopped          | none                    |
| `test/http-health`          | Wait for HTTP endpoint                        | `curl`                  |
| `test/dbus`                 | Start D-Bus service (creates messagebus user) | `dbus`, `dbus-openrc`   |
| `test/bluetooth`            | Start Bluetooth service (requires dbus first) | `bluez`, `bluez-openrc` |
| `test/debug`                | Pause execution for debugging (see below)     | none                    |

**Basic example (container service):**

```yaml
test:
  environment:
    contents:
      packages:
        - busybox
        - podman-container-common
        - curl
        - iptables
        - openrc
  pipeline:
    - uses: test/openrc-start
      with:
        service_name: myapp-container
    - uses: test/http-health
      with:
        url: "http://localhost:8080/health"
        expected: "OK"
    - uses: test/openrc-stop
      with:
        service_name: myapp-container
    - uses: test/podman-verify-stopped
      with:
        container_name: myapp
```

**Example with debugging (container keeps running):**

```yaml
test:
  pipeline:
    - uses: test/openrc-start
      with:
        service_name: podinfo-container
    - uses: test/http-health
      with:
        url: "http://localhost:9898/healthz"
        expected: "OK"
    - name: "Custom verification"
      runs: |
        curl -s http://localhost:9898/ | grep -q "podinfo"
    - uses: test/debug # Debug while container still runs
    - uses: test/openrc-stop
      with:
        service_name: podinfo-container
    - uses: test/podman-verify-stopped
      with:
        container_name: podinfo
```

**Advanced example (container requiring dbus/bluetooth):**

```yaml
test:
  environment:
    contents:
      packages:
        - busybox
        - podman-container-common
        - curl
        - iptables
        - openrc
  pipeline:
    - uses: test/dbus
    - uses: test/bluetooth
    - name: "Setup directories"
      runs: |
        mkdir -p /var/lib/homeassistant
    - uses: test/openrc-start
      with:
        service_name: home-assistant-container
    - uses: test/http-health
      with:
        url: "http://localhost:8123/manifest.json"
        expected: "Home Assistant"
        timeout: "120"
    - uses: test/openrc-stop
      with:
        service_name: home-assistant-container
    - uses: test/podman-verify-stopped
      with:
        container_name: home-assistant
```

**Pipeline parameters:**

`test/openrc-start`:

| Parameter      | Required | Description                                       |
| -------------- | -------- | ------------------------------------------------- |
| `service_name` | Yes      | OpenRC service name (e.g., `"podinfo-container"`) |

`test/openrc-stop`:

| Parameter      | Required | Description                 |
| -------------- | -------- | --------------------------- |
| `service_name` | Yes      | OpenRC service name to stop |

`test/podman-verify-stopped`:

| Parameter        | Required | Description                                        |
| ---------------- | -------- | -------------------------------------------------- |
| `container_name` | No       | Container name to verify (verifies all if omitted) |

`test/http-health`:

| Parameter  | Required | Description                                          |
| ---------- | -------- | ---------------------------------------------------- |
| `url`      | Yes      | URL to poll (e.g., `"http://localhost:8080/health"`) |
| `expected` | Yes      | String to match in response (e.g., `"OK"`)           |
| `timeout`  | No       | Timeout in seconds (default: `"60"`)                 |

**Notes:**

- OpenRC environment is automatically initialized by microvm-init when OpenRC is installed
- `test/openrc-start` also initializes OpenRC if not already done
- Service pipelines mark services as started for OpenRC dependency tracking

### Debugging Tests

Use `test/debug` to pause execution and inspect the test environment. Run with interactive flags:

```bash
melange test --interactive --debug-runner <package>.yaml
```

Add the debug pipeline between health check and stop to debug a running container:

```yaml
pipeline:
  - uses: test/openrc-start
    with:
      service_name: myapp-container
  - uses: test/http-health
    with:
      url: "http://localhost:8080/health"
      expected: "OK"
  - uses: test/debug # Pauses here - container still running
  - uses: test/openrc-stop
    with:
      service_name: myapp-container
```

While paused:

- SSH into the VM using credentials from melange output
- Use SSH port forwarding to access services: `ssh -L 8123:localhost:8123 build@localhost -p <port>`
- Create `/tmp/debug-continue` inside the VM to resume execution
- Press Ctrl+C in melange to abort

**IMPORTANT:** After modifying a package yaml, always run `melange build <package>.yaml` to verify the configuration is valid.

## Relevant sources

- $HOME/repos/github.com/chainguard-dev/melange
- $HOME/repos/github.com/chainguard-dev/actions
- $HOME/repos/github.com/wolfi-dev/os
