#!/bin/sh
# Setup script for diskless Home Assistant
# Pulls container image and creates squashfs on SD card

set -e

: ${HASS_IMAGE:="ghcr.io/home-assistant/home-assistant:stable"}

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

# Use temp directory on SD card (tmpfs may not have enough space)
WORKDIR="$SD_MOUNT/.home-assistant-setup"
cleanup() {
    echo "Cleaning up..."
    # Unmount temp storage if mounted
    umount "$SD_MOUNT/.home-assistant-setup/storage" 2>/dev/null || true
    rm -rf "$WORKDIR"
    # Ensure SD card is remounted read-only on exit
    mount -o remount,ro "$SD_MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Setting up Home Assistant container image ==="
echo "Target: $SQUASHFS_PATH"

# Check if squashfs already exists
if [ -f "$SQUASHFS_PATH" ]; then
    echo "Image already exists at $SQUASHFS_PATH"
    echo "Remove it first to re-pull: rm $SQUASHFS_PATH"
    exit 0
fi

# Remount SD card read-write
echo "Remounting $SD_MOUNT read-write..."
mount -o remount,rw "$SD_MOUNT"

# Create temp ext4 image for Podman storage (FAT32 doesn't support overlay)
echo "Creating temporary storage image..."
mkdir -p "$WORKDIR"
TEMP_IMG="$WORKDIR/temp-storage.img"
TEMP_MOUNT="$WORKDIR/storage"

# Create 3GB sparse image and format as ext4 (FAT32 has 4GB limit)
truncate -s 3G "$TEMP_IMG"
mkfs.ext4 -q "$TEMP_IMG"
mkdir -p "$TEMP_MOUNT"
mount -o loop "$TEMP_IMG" "$TEMP_MOUNT"

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
echo "Start services:"
echo "  rc-service home-assistant-rostore start"
echo "  rc-service home-assistant-container start"
