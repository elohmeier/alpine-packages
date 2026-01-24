# Shared functions for Podman container services
# Source this file in init scripts: . /usr/lib/podman-container/functions.sh

# Sanitize image reference for filesystem use
# ghcr.io/stefanprodan/podinfo:6.5.0 -> ghcr.io-stefanprodan-podinfo-6.5.0
sanitize_image_ref() {
    local image="$1"
    echo "$image" | sed 's|[/:]|-|g'
}

# Get squashfs path on SD card
# Args: container_name, image_ref, [sd_mount]
get_squashfs_path() {
    local container_name="$1"
    local image="$2"
    local sd_mount="${3:-}"
    local sanitized

    sanitized=$(sanitize_image_ref "$image")

    if [ -z "$sd_mount" ]; then
        sd_mount=$(find_sd_mount) || return 1
    fi

    echo "${sd_mount}/${container_name}-${sanitized}.squashfs"
}

# Get rostore mountpoint path for an image
get_rostore_mount() {
    local image="$1"
    local sanitized

    sanitized=$(sanitize_image_ref "$image")
    echo "/var/lib/containers/rostore/${sanitized}"
}

# Find SD card mount point
find_sd_mount() {
    local dir
    for dir in /media/mmcblk0p1 /media/sda1 /media/usb; do
        [ -d "$dir" ] && echo "$dir" && return 0
    done
    return 1
}

# Mount squashfs if not already mounted
# Returns 0 if mounted (or already was), 1 if squashfs not found
ensure_rostore_mounted() {
    local container_name="$1"
    local image="$2"
    local mount_point squashfs_path

    mount_point=$(get_rostore_mount "$image")
    squashfs_path=$(get_squashfs_path "$container_name" "$image") || return 1

    # Already mounted?
    if mountpoint -q "$mount_point" 2>/dev/null; then
        return 0
    fi

    # Check if squashfs exists
    if [ ! -f "$squashfs_path" ]; then
        return 1
    fi

    # Mount it
    mkdir -p "$mount_point"
    mount -t squashfs -o ro,loop "$squashfs_path" "$mount_point"
}

# Unmount rostore for an image
unmount_rostore() {
    local image="$1"
    local mount_point

    mount_point=$(get_rostore_mount "$image")

    if mountpoint -q "$mount_point" 2>/dev/null; then
        umount "$mount_point"
    fi
}

# Generate a temporary storage.conf pointing to rostore (if available)
# Returns path to the generated file
get_storage_conf() {
    local image="$1"
    local rostore_mount conf_file

    rostore_mount=$(get_rostore_mount "$image")
    conf_file="/run/podman-container/storage-$(sanitize_image_ref "$image").conf"

    mkdir -p /run/podman-container

    # Only add additionalimagestores if rostore is actually mounted
    if mountpoint -q "$rostore_mount" 2>/dev/null; then
        cat > "$conf_file" << EOF
[storage]
driver = "overlay"
graphroot = "/var/lib/containers/storage"
runroot = "/run/containers/storage"

[storage.options]
additionalimagestores = ["${rostore_mount}"]
EOF
    else
        cat > "$conf_file" << EOF
[storage]
driver = "overlay"
graphroot = "/var/lib/containers/storage"
runroot = "/run/containers/storage"
EOF
    fi

    echo "$conf_file"
}

# Wait for podman to be ready
wait_for_podman() {
    local i=0
    while ! podman info >/dev/null 2>&1; do
        i=$((i + 1))
        if [ $i -ge 30 ]; then
            eerror "Timeout waiting for podman to be ready"
            return 1
        fi
        sleep 1
    done
    return 0
}

# Check container status (for OpenRC status command)
container_status() {
    local name="$1"
    if podman ps --format "{{.Names}}" | grep -q "^${name}$"; then
        einfo "Container ${name} is running"
        return 0
    else
        einfo "Container ${name} is not running"
        return 3
    fi
}

# Run podman with custom storage config
# Usage: podman_run <image> [podman args...]
podman_run() {
    local image="$1"
    shift
    local storage_conf

    storage_conf=$(get_storage_conf "$image")
    CONTAINERS_STORAGE_CONF="$storage_conf" podman "$@"
}
