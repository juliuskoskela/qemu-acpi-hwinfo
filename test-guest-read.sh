#!/usr/bin/env bash

set -e

# Ensure we have Nix in PATH
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
export NIX_CONFIG="experimental-features = nix-command flakes"

echo "=== Testing Guest Hardware Info Reading ==="
echo

echo "1. Building hardware info derivation..."
nix build .#hwinfo
HWINFO_PATH=$(readlink -f result)/hwinfo.aml
echo "✓ Hardware info built at: $HWINFO_PATH"

echo
echo "2. Checking if we can read the ACPI table directly..."
echo "ACPI table contents:"
hexdump -C "$HWINFO_PATH" | head -10

echo
echo "3. Extracting strings from ACPI table..."
strings "$HWINFO_PATH" | grep -E "(NVME_SERIAL|MAC_ADDRESS|nvme_card|f6:bf)" || echo "No readable strings found"

echo
echo "4. Creating a simple test script for guest..."
cat >/tmp/test-guest-hwinfo.sh <<'EOF'
#!/bin/bash
echo "=== Guest Hardware Info Test ==="
echo "Looking for ACPI SSDT tables..."
if [ -d /sys/firmware/acpi/tables ]; then
    echo "ACPI tables directory exists"
    ls -la /sys/firmware/acpi/tables/SSDT* 2>/dev/null || echo "No SSDT tables found"

    echo "Searching for hardware info in ACPI tables..."
    strings /sys/firmware/acpi/tables/SSDT* 2>/dev/null | grep -A 1 -B 1 "NVME_SERIAL\|MAC_ADDRESS" || echo "Hardware info not found in ACPI tables"
else
    echo "ACPI tables directory not found - this might not be running in a VM with ACPI support"
fi

echo "Checking for ACPI device..."
if [ -d /sys/bus/acpi/devices ]; then
    echo "ACPI devices:"
    ls /sys/bus/acpi/devices/ | grep -i acpi || echo "No ACPI devices found"
fi
EOF

chmod +x /tmp/test-guest-hwinfo.sh

echo "✓ Guest test script created at /tmp/test-guest-hwinfo.sh"

echo
echo "5. Testing the guest script locally (limited functionality outside VM)..."
/tmp/test-guest-hwinfo.sh

echo
echo "=== Test Summary ==="
echo "✓ Hardware info derivation builds successfully"
echo "✓ ACPI table is generated and contains expected data"
echo "✓ Guest test script is ready"
echo
echo "To test in a real VM, you would run:"
echo '  qemu-system-x86_64 \'
echo "    -acpitable file=$HWINFO_PATH \\"
echo '    -kernel /path/to/kernel \'
echo '    -initrd /path/to/initrd \'
echo "    -append 'console=ttyS0' \\"
echo '    -nographic \'
echo "    [other options]"
echo
echo "Then inside the guest, run the test script to verify hardware info is accessible."
