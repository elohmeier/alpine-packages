#!/usr/bin/env bash
# Target architecture for melange, plus the QEMU runner paths derived from it.
# Override with a pre-exported MELANGE_ARCH, e.g.
#   MELANGE_ARCH=x86_64 melange test <package>.yaml
#
# Build the kernel and initramfs once per architecture:
#   mise run fetch-kernel
#   mise run build-initramfs
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD/.mise/env.sh}")/.." && pwd)"

arch="${MELANGE_ARCH:-aarch64}"
case "$arch" in
    arm64 | aarch64) arch="aarch64" ;;
    x64 | amd64 | x86_64) arch="x86_64" ;;
esac

export MELANGE_ARCH="$arch"
export QEMU_KERNEL_IMAGE="$root/kernel/$arch/vmlinuz"
export QEMU_KERNEL_MODULES="$root/kernel/$arch/modules/"

# melange otherwise builds this initramfs from https://apk.cgr.dev/chainguard,
# which we cannot authenticate against; the VM then panics with
# "No working init found". build-initramfs uses this repo's microvm-init.
export QEMU_BASE_INITRAMFS="$root/.test-cache/melange-base-initramfs-$arch.cpio"
