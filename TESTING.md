# Testing Guide

This document describes how to test the ACPI hardware info functionality with MicroVM.

## Quick Start

Enter the development environment and run the end-to-end test:

```bash
nix develop
run-test-vm-with-hwinfo
```

## Test Commands

### `run-test-vm-with-hwinfo`
End-to-end test that validates:
- Hardware info generation
- Module syntax validation
- Hardware info file verification
- Integration with MicroVM functionality

### `run-test-microvm`
MicroVM-specific test that validates:
- MicroVM configuration syntax
- Guest module structure
- MicroVM integration options (microvmFlags, microvmShares)

## Test Structure

### 1. Hardware Info Generation
- Detects NVMe serial and MAC address
- Generates JSON metadata
- Compiles ACPI ASL to AML format
- Stores files in `/var/lib/acpi-hwinfo/` or `./acpi-hwinfo/`

### 2. Module Validation
- Tests that guest module can be imported
- Validates module structure (function type)
- Checks MicroVM-specific options

### 3. MicroVM Configuration
- Validates `./examples/microvm.nix` syntax
- Tests integration with microvm.nix flake input
- Verifies MicroVM-specific features:
  - ACPI table injection via `microvmFlags`
  - Hardware info sharing via `microvmShares`
  - Helper scripts and environment variables

## Manual Testing

To manually build and test a MicroVM:

```bash
# Build the MicroVM
nix build --impure --expr 'let flake = builtins.getFlake (toString ./.); in (flake.inputs.nixpkgs.lib.nixosSystem { system = "x86_64-linux"; modules = [ (import ./examples/microvm.nix { inherit (flake) self; inherit (flake.inputs) nixpkgs microvm; }) flake.inputs.microvm.nixosModules.microvm ]; }).config.system.build.toplevel'

# Run the MicroVM (if built successfully)
# ./result/bin/microvm-run
```

## Test Files

- `./examples/microvm.nix` - Example MicroVM configuration with ACPI hardware info
- `./modules/guest.nix` - Guest module with MicroVM options
- `./packages/default.nix` - Test runner implementations

## Expected Output

Successful tests should show:
- ✅ Hardware info generated successfully
- ✅ Module syntax test passed
- ✅ Hardware info JSON/AML found
- ✅ MicroVM configuration is valid
- ✅ Guest module MicroVM options work correctly

## Troubleshooting

### Permission Issues
If you can't write to `/var/lib/acpi-hwinfo/`, the tools will automatically use `./acpi-hwinfo/` instead.

### Missing Dependencies
The development shell includes all necessary dependencies. If running outside the shell, ensure you have:
- `acpica-tools` (for ASL compilation)
- `nvme-cli` (for NVMe detection)
- `iproute2` (for network interface detection)
- `jq` (for JSON processing)

### MicroVM Build Issues
MicroVM building requires:
- `microvm.nix` flake input (automatically handled)
- Valid NixOS configuration
- Proper module imports

The tests validate configuration syntax without actually building/running VMs to keep testing fast and reliable.