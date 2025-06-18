#!/usr/bin/env bash

set -e

# Ensure we have Nix in PATH
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
export NIX_CONFIG="experimental-features = nix-command flakes"

echo "=== Testing QEMU ACPI Hardware Info Nix Flake ==="
echo

echo "1. Building default hardware info derivation..."
nix build .#hwinfo
echo "✓ Built successfully"

echo
echo "Generated hardware info:"
cat result/hwinfo.json
echo

echo "2. Checking ACPI table was compiled..."
ls -la result/hwinfo.aml
echo "✓ ACPI table exists: $(wc -c <result/hwinfo.aml) bytes"

echo
echo "3. Viewing ACPI source code..."
echo "--- hwinfo.asl ---"
cat result/hwinfo.asl
echo "--- end ---"

echo
echo "4. Testing flake check..."
nix flake check
echo "✓ Flake check passed"

echo
echo "5. Testing development shell..."
nix develop --command bash -c "which iasl && iasl -v"
echo "✓ Development shell works"

echo
echo "=== All tests passed! ==="
echo
echo "The ACPI hardware info derivation is working correctly."
echo "The hwinfo.aml file can be used with QEMU using:"
echo "  qemu-system-x86_64 -acpitable file=$(readlink -f result)/hwinfo.aml [other options]"
echo
echo "For MicroVM integration, see example-vm.nix"
