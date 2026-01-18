#!/bin/sh
# Setup script for diskless Home Assistant
# Pulls container image and creates squashfs on SD card
#
# Usage:
#   setup-home-assistant-image           # Initial setup (fails if exists)
#   setup-home-assistant-image --upgrade # Upgrade existing installation

set -e

: ${HASS_IMAGE:="ghcr.io/home-assistant/home-assistant:@VERSION@"}

# Parse arguments
UPGRADE_MODE=false
if [ "$1" = "--upgrade" ] || [ "$1" = "-u" ]; then
    UPGRADE_MODE=true
fi

# Find SD card mount point
find_sd_mount() {
    for dir in /media/mmcblk0p1 /media/sda1 /media/usb; do
        [ -d "$dir" ] && echo "$dir" && return 0
    done
    return 1
}

SD_MOUNT=$(find_sd_mount) || {
    echo "Error: No SD card mount found"
    exit 1
}

SQUASHFS_PATH="$SD_MOUNT/home-assistant-image.squashfs"

# Use tmpfs for temporary storage (needs ~3GB RAM)
WORKDIR="/tmp/home-assistant-setup"
TEMP_MOUNT="$WORKDIR/storage"

cleanup() {
    echo "Cleaning up..."
    # Unmount tmpfs if mounted
    umount "$TEMP_MOUNT" 2>/dev/null || true
    rm -rf "$WORKDIR"
    # Ensure SD card is remounted read-only on exit
    mount -o remount,ro "$SD_MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Setting up Home Assistant container image ==="
echo "Target: $SQUASHFS_PATH"

# Check if squashfs already exists
if [ -f "$SQUASHFS_PATH" ]; then
    if [ "$UPGRADE_MODE" = "true" ]; then
        echo "Upgrade mode: replacing existing image..."
        # Stop services before unmounting
        rc-service home-assistant-container stop 2>/dev/null || true
        rc-service home-assistant-rostore stop 2>/dev/null || true
        # Remount and delete old squashfs
        mount -o remount,rw "$SD_MOUNT"
        rm -f "$SQUASHFS_PATH"
    else
        echo "Image already exists at $SQUASHFS_PATH"
        echo "Use --upgrade to replace with new version"
        exit 0
    fi
else
    # Remount SD card read-write for fresh install
    echo "Remounting $SD_MOUNT read-write..."
    mount -o remount,rw "$SD_MOUNT"
fi

# Create tmpfs for Podman storage (FAT32 doesn't support overlay)
echo "Creating temporary storage in RAM..."
mkdir -p "$WORKDIR" "$TEMP_MOUNT"
mount -t tmpfs -o size=3G tmpfs "$TEMP_MOUNT"

# Create Podman storage config
mkdir -p "$TEMP_MOUNT/graphroot" "$WORKDIR/runroot"
cat > "$WORKDIR/storage.conf" << EOF
[storage]
driver = "overlay"
graphroot = "$TEMP_MOUNT/graphroot"
runroot = "$WORKDIR/runroot"
EOF

echo "Pulling image: $HASS_IMAGE"
CONTAINERS_STORAGE_CONF="$WORKDIR/storage.conf" podman pull "$HASS_IMAGE"

# Create squashfs from the graphroot
echo "Creating squashfs (this may take a few minutes)..."
mksquashfs "$TEMP_MOUNT/graphroot" "$SQUASHFS_PATH" -comp zstd -noappend

# Unmount temp storage before cleanup
umount "$TEMP_MOUNT"

# Remount SD card read-only
echo "Remounting $SD_MOUNT read-only..."
mount -o remount,ro "$SD_MOUNT"

echo ""
echo "=== Done ==="
echo "Image saved to: $SQUASHFS_PATH"

# Restart services if upgrade mode
if [ "$UPGRADE_MODE" = "true" ]; then
    echo "Restarting services..."
    rc-service home-assistant-rostore start
    rc-service home-assistant-container start
else
    echo "Start services:"
    echo "  rc-service home-assistant-rostore start"
    echo "  rc-service home-assistant-container start"
fi
