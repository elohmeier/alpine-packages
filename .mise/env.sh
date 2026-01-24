#!/usr/bin/env bash
# Find the latest microvm-init apk by version
ARCH="$(uname -m)"
[[ "$ARCH" == "arm64" ]] && ARCH="aarch64"

latest=$(ls -v packages/"$ARCH"/microvm-init-*.apk 2>/dev/null | tail -1)
if [[ -n "$latest" ]]; then
  export QEMU_MICROVM_INIT_APK="$latest"
fi
