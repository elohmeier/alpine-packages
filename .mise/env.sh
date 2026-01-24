#!/usr/bin/env bash
# Find the latest microvm-init apk by version
ARCH="$(uname -m)"
[[ "$ARCH" == "arm64" ]] && ARCH="aarch64"

latest=$(find packages/"$ARCH" -maxdepth 1 -name 'microvm-init-*.apk' -print 2>/dev/null | sort -V | tail -1)
if [[ -n "$latest" ]]; then
    export QEMU_MICROVM_INIT_APK="$latest"
fi
