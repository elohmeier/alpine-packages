#!/bin/sh
# Generic setup script for Podman container images on diskless systems
# Pulls container image and creates squashfs on SD card
#
# Usage:
#   setup-container-image <container-name> <image:tag>              # Initial setup
#   setup-container-image <container-name> <image:tag> --upgrade    # Upgrade

set -e

# shellcheck source=/dev/null
. /usr/lib/podman-container/functions.sh

usage() {
    echo "Usage: setup-container-image <container-name> <image:tag> [--upgrade]"
    echo ""
    echo "Examples:"
    echo "  setup-container-image podinfo ghcr.io/stefanprodan/podinfo:6.7.1"
    echo "  setup-container-image podinfo ghcr.io/stefanprodan/podinfo:6.7.2 --upgrade"
    exit 1
}

# Parse arguments
[ $# -lt 2 ] && usage

CONTAINER_NAME="$1"
CONTAINER_IMAGE="$2"
UPGRADE_MODE=false

if [ "$3" = "--upgrade" ] || [ "$3" = "-u" ]; then
    UPGRADE_MODE=true
fi

# Find SD card mount point
SD_MOUNT=$(find_sd_mount) || {
    echo "Error: No SD card mount found"
    exit 1
}

SQUASHFS_PATH=$(get_squashfs_path "$CONTAINER_NAME" "$CONTAINER_IMAGE" "$SD_MOUNT")

# Check if this version already exists
if [ -f "$SQUASHFS_PATH" ]; then
    echo "Image already exists at $SQUASHFS_PATH"
    exit 0
fi

# Check for any existing image (different version)
OLD_SQUASHFS=$(find "$SD_MOUNT" -maxdepth 1 -name "${CONTAINER_NAME}-*.squashfs" -print -quit 2>/dev/null) || true

if [ -n "$OLD_SQUASHFS" ] && [ "$UPGRADE_MODE" != "true" ]; then
    echo "Existing image found: $OLD_SQUASHFS"
    echo "Use --upgrade to replace with new version"
    exit 0
fi

# Use tmpfs for temporary storage
WORKDIR="/tmp/${CONTAINER_NAME}-setup"
TEMP_MOUNT="$WORKDIR/storage"

# Check if SD card is already mounted read-write
# We only remount to read-only at the end if we changed it
SD_WAS_RO=false
if grep -q " $SD_MOUNT .*\bro\b" /proc/mounts 2>/dev/null; then
    SD_WAS_RO=true
fi

cleanup() {
    echo "Cleaning up..."
    umount "$TEMP_MOUNT" 2>/dev/null || true
    rm -rf "$WORKDIR"
    # Only remount read-only if it was read-only before we started
    if [ "$SD_WAS_RO" = "true" ]; then
        mount -o remount,ro "$SD_MOUNT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "=== Setting up ${CONTAINER_NAME} container image ==="
echo "Image: $CONTAINER_IMAGE"
echo "Target: $SQUASHFS_PATH"

# Remount SD card read-write if needed
if [ "$SD_WAS_RO" = "true" ]; then
    echo "Remounting $SD_MOUNT read-write..."
    mount -o remount,rw "$SD_MOUNT"
else
    echo "$SD_MOUNT is already read-write"
fi

# Remove old image if upgrading
if [ -n "$OLD_SQUASHFS" ]; then
    echo "Upgrade mode: stopping service..."
    rc-service "${CONTAINER_NAME}-container" stop 2>/dev/null || true
    echo "Removing old image: $OLD_SQUASHFS"
    rm -f "$OLD_SQUASHFS"
fi

# Create tmpfs for Podman storage
echo "Creating temporary storage in RAM..."
mkdir -p "$WORKDIR" "$TEMP_MOUNT"
mount -t tmpfs -o size=3G tmpfs "$TEMP_MOUNT"

# Create Podman storage config
mkdir -p "$TEMP_MOUNT/graphroot" "$WORKDIR/runroot"
cat >"$WORKDIR/storage.conf" <<EOF
[storage]
driver = "overlay"
graphroot = "$TEMP_MOUNT/graphroot"
runroot = "$WORKDIR/runroot"
EOF

echo "Pulling image: $CONTAINER_IMAGE"
CONTAINERS_STORAGE_CONF="$WORKDIR/storage.conf" podman pull "$CONTAINER_IMAGE"

# Create squashfs from the graphroot
echo "Creating squashfs (this may take a few minutes)..."
mksquashfs "$TEMP_MOUNT/graphroot" "$SQUASHFS_PATH" -comp zstd -noappend

# Unmount temp storage
umount "$TEMP_MOUNT"

# Remount SD card read-only if it was read-only before
if [ "$SD_WAS_RO" = "true" ]; then
    echo "Remounting $SD_MOUNT read-only..."
    mount -o remount,ro "$SD_MOUNT"
fi

echo ""
echo "=== Done ==="
echo "Image saved to: $SQUASHFS_PATH"

# Restart service if we stopped it
if [ -n "$OLD_SQUASHFS" ]; then
    echo "Restarting service..."
    rc-service "${CONTAINER_NAME}-container" start
else
    echo "Start service:"
    echo "  rc-service ${CONTAINER_NAME}-container start"
fi
