#!/bin/bash
# Test script for home-assistant-container on diskless Alpine Linux
# Uses QEMU with HVF acceleration on macOS Apple Silicon
#
# Usage:
#   ./scripts/test-diskless.sh          # Run interactive test
#   ./scripts/test-diskless.sh --test   # Run automated tests
#   ./scripts/test-diskless.sh --clean  # Clean cached files

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="$REPO_DIR/.test-cache"
ALPINE_VERSION="3.23"
ALPINE_RELEASE="${ALPINE_VERSION}.2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test mode flag
TEST_MODE=0

info() { echo -e "${GREEN}==>${NC} $1"; }
warn() { echo -e "${YELLOW}Warning:${NC} $1"; }
error() { echo -e "${RED}Error:${NC} $1" >&2; exit 1; }

# Check dependencies
check_deps() {
    info "Checking dependencies..."
    command -v qemu-system-aarch64 >/dev/null || error "qemu-system-aarch64 not found. Install with: brew install qemu"
    command -v curl >/dev/null || error "curl not found"
    if [ "$TEST_MODE" -eq 1 ]; then
        command -v expect >/dev/null || error "expect not found. Install with: brew install expect"
    fi
}

# Clean cached files
clean() {
    info "Cleaning cached files..."
    rm -rf "$CACHE_DIR"
    echo "Done."
    exit 0
}

# Download Alpine Linux if not cached
download_alpine() {
    local iso="$CACHE_DIR/alpine-virt-${ALPINE_RELEASE}-aarch64.iso"

    if [ -f "$iso" ]; then
        info "Using cached Alpine ISO"
    else
        info "Downloading Alpine Linux ${ALPINE_RELEASE} aarch64..."
        mkdir -p "$CACHE_DIR"
        curl -L -o "$iso" \
            "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/aarch64/alpine-virt-${ALPINE_RELEASE}-aarch64.iso"
    fi

    ALPINE_ISO="$iso"
}

# Create FAT32 disk image for virtual SD card
create_sdcard_image() {
    local img="$CACHE_DIR/sdcard.img"
    local mnt="$CACHE_DIR/sdcard-mnt"

    info "Creating 8GB FAT32 SD card image..."

    # 8GB is needed for: 3GB temp ext4 image + squashfs output + overhead
    rm -f "$img"

    # Create sparse raw image
    truncate -s 8G "$img"

    # Attach as raw disk image and format entire disk as FAT32 (no partitions)
    local dev_info
    dev_info=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage "$img")
    local loop_dev
    loop_dev=$(echo "$dev_info" | awk '{print $1}')

    if [ -z "$loop_dev" ]; then
        error "Failed to attach SD card image"
    fi

    # Format entire disk as FAT32 (superfloppy format - no partition table)
    newfs_msdos -F 32 -v SDCARD "$loop_dev"

    # Verify by mounting
    mkdir -p "$mnt"
    if mount -t msdos "$loop_dev" "$mnt"; then
        info "SD card image formatted and verified"
        umount "$mnt"
    else
        warn "Could not verify mount, continuing anyway"
    fi

    hdiutil detach "$loop_dev"

    SD_IMG="$img"
}

# Create disk image with packages
create_packages_image() {
    local img="$CACHE_DIR/packages.img"
    local mnt="$CACHE_DIR/packages-mnt"

    info "Building packages..."
    cd "$REPO_DIR"
    melange build --arch arm64 --signing-key local-melange.rsa home-assistant-container.yaml 2>&1 | tail -5

    info "Creating packages disk image..."

    # Create raw disk image (64MB is enough for home-assistant-container)
    rm -f "$img"
    truncate -s 64M "$img"

    # Attach as raw disk image and format as FAT32
    local dev_info
    dev_info=$(hdiutil attach -nomount -imagekey diskimage-class=CRawDiskImage "$img")
    local loop_dev
    loop_dev=$(echo "$dev_info" | awk '{print $1}')

    if [ -z "$loop_dev" ]; then
        error "Failed to attach packages image"
    fi

    # Format entire disk as FAT32 (superfloppy format)
    newfs_msdos -F 32 -v PACKAGES "$loop_dev"

    # Mount and copy packages
    mkdir -p "$mnt"
    mount -t msdos "$loop_dev" "$mnt"

    info "Copying packages..."
    mkdir -p "$mnt/aarch64"
    # Only copy home-assistant-container package and index
    cp "$REPO_DIR/packages/aarch64/home-assistant-container-"*.apk "$mnt/aarch64/" 2>/dev/null || true
    cp "$REPO_DIR/packages/aarch64/APKINDEX.tar.gz" "$mnt/aarch64/"
    cp "$REPO_DIR/local-melange.rsa.pub" "$mnt/"

    if [ -f "$mnt/aarch64/APKINDEX.tar.gz" ]; then
        info "Packages copied successfully"
        ls -la "$mnt/aarch64/"
    fi

    # Unmount and detach
    umount "$mnt"
    hdiutil detach "$loop_dev"

    PKG_IMG="$img"
}

# Run automated tests with expect
run_qemu_test() {
    info "Starting automated QEMU test..."

    local exp_script="$SCRIPT_DIR/test-diskless.exp"
    local log_file="$CACHE_DIR/test-output.log"

    if [ ! -f "$exp_script" ]; then
        error "Expect script not found: $exp_script"
    fi

    # Export paths for expect script
    export ALPINE_ISO SD_IMG PKG_IMG

    # Run expect script, capture output
    # Use PIPESTATUS to get expect's exit code through tee
    expect "$exp_script" 2>&1 | tee "$log_file"
    local result=${PIPESTATUS[0]}

    if [ "$result" -eq 0 ]; then
        info "All tests passed!"
        return 0
    else
        error "Tests failed (exit code: $result). See log: $log_file"
        return 1
    fi
}

# Print test instructions
print_instructions() {
    cat <<'EOF'

================================================================================
                        DISKLESS ALPINE TEST ENVIRONMENT
================================================================================

Once Alpine boots and you see the login prompt, run these commands:

1. Login as root (no password)

2. Setup networking:
   setup-interfaces -a
   ifup eth0

3. Mount SD card (virtual):
   mkdir -p /media/mmcblk0p1
   mount /dev/vdb /media/mmcblk0p1

4. Mount packages disk:
   mkdir -p /packages
   mount /dev/vdc /packages

5. Setup repositories:
   setup-apkrepos -1
   echo "http://dl-cdn.alpinelinux.org/alpine/v3.23/community" >> /etc/apk/repositories
   echo "/packages" >> /etc/apk/repositories
   cp /packages/local-melange.rsa.pub /etc/apk/keys/

6. Install package:
   apk update
   apk add home-assistant-container

7. Verify squashfs was created:
   ls -la /media/mmcblk0p1/

8. Check services:
   rc-service home-assistant-rostore status
   podman images

To exit QEMU: Press Ctrl+A, then X

================================================================================
EOF
}

# Run QEMU
run_qemu() {
    info "Starting QEMU with HVF acceleration..."
    print_instructions

    qemu-system-aarch64 \
        -accel hvf \
        -M virt \
        -cpu host \
        -m 8192 \
        -nographic \
        -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
        -drive file="$ALPINE_ISO",format=raw,if=virtio,media=cdrom \
        -drive file="$SD_IMG",format=raw,if=virtio \
        -drive file="$PKG_IMG",format=raw,if=virtio \
        -netdev user,id=net0,hostfwd=tcp::8123-:8123 \
        -device virtio-net-pci,netdev=net0
}

# Main
main() {
    # Handle flags
    case "$1" in
        --clean) clean ;;
        --test) TEST_MODE=1 ;;
    esac

    check_deps

    mkdir -p "$CACHE_DIR"

    download_alpine
    create_sdcard_image
    create_packages_image

    if [ "$TEST_MODE" -eq 1 ]; then
        run_qemu_test
    else
        run_qemu
    fi
}

main "$@"
