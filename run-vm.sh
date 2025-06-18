#!/usr/bin/env bash

set -e

# Ensure we have Nix in PATH
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Enable experimental features for flakes
export NIX_CONFIG="experimental-features = nix-command flakes"

echo "Building ACPI hardware info..."
nix build .#hwinfo

echo "Generated hardware info:"
cat result/hwinfo.json

echo ""
echo "ACPI table location: $(readlink -f result)/hwinfo.aml"

echo ""
echo "To use with microvm, the hwinfo.aml will be automatically included."
echo "You can now build and run a microVM with:"
echo "  nix run github:astro/microvm.nix -- --flake .#vm"

echo ""
echo "Or build the VM configuration:"
echo "  nix build .#nixosConfigurations.vm.config.microvm.declaredRunner"
