#!/bin/bash

# Check multiple possible locations for hwinfo
HWINFO_PATHS=("/var/lib/acpi-hwinfo/hwinfo.aml" "./acpi-hwinfo/hwinfo.aml")
HWINFO_PATH=""

for path in "${HWINFO_PATHS[@]}"; do
  if [ -f "$path" ]; then
    HWINFO_PATH="$path"
    break
  fi
done

if [ -z "$HWINFO_PATH" ]; then
  echo "❌ Hardware info not found in any of these locations:"
  for path in "${HWINFO_PATHS[@]}"; do
    echo "   $path"
  done
  echo "💡 Run 'acpi-hwinfo-generate' first to create hardware info"
  exit 1
fi

echo "🚀 Starting QEMU with hardware info from $HWINFO_PATH"

# Default QEMU arguments
QEMU_ARGS=(
  -machine q35
  -cpu host
  -enable-kvm
  -m 2G
  -acpitable file="$HWINFO_PATH"
)

# Add disk if provided
if [ $# -gt 0 ] && [ -f "$1" ]; then
  QEMU_ARGS+=(-drive "file=$1,format=qcow2")
  shift
fi

# Add any additional arguments
QEMU_ARGS+=("$@")

echo "🔧 QEMU command: qemu-system-x86_64 ${QEMU_ARGS[*]}"
exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
