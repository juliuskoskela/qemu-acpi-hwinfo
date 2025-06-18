#!/bin/bash

DISK_IMAGE=${1:-disk.qcow2}
MEMORY=${2:-2G}

if [ ! -f hwinfo.aml ]; then
    echo "Error: hwinfo.aml not found. Run hardware-acpi.sh first."
    exit 1
fi

echo "Starting VM with hardware info ACPI table..."

exec qemu-system-x86_64 \
    -acpitable file=hwinfo.aml \
    -drive file="$DISK_IMAGE",if=virtio \
    -netdev user,id=net0 -device virtio-net,netdev=net0 \
    -m "$MEMORY" \
    -enable-kvm \
    -cpu host \
    "${@:3}"
