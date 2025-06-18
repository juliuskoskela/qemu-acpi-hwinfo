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
- MicroVM configuration validation
- Test ACPI table generation
- Complete integration workflow

### `test-microvm` (via `nix build .#test-microvm`)
MicroVM validation script that:
- Shows generated test ACPI table
- Validates MicroVM configuration
- Provides manual build instructions
- Demonstrates complete workflow

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
- Generates test ACPI table with hardware info
- Creates nixosSystem with MicroVM modules
- Validates ACPI table injection configuration
- Tests guest module integration
- Verifies guest tools availability

## Manual Testing

### Build Test Components

```bash
# Build the test ACPI table
nix build .#test-hwinfo-aml

# Verify it's a valid ACPI table
file result
```

### Build and Run Test MicroVM

```bash
# Build a complete MicroVM system with ACPI injection
nix build --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    hwinfo = flake.outputs.packages.x86_64-linux.test-hwinfo-aml;
  in
  flake.inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      flake.inputs.microvm.nixosModules.microvm
      flake.nixosModules.acpi-hwinfo-guest
      {
        microvm = {
          vcpu = 2; mem = 1024; hypervisor = "qemu";
          interfaces = [{ type = "user"; id = "vm-net"; mac = "02:00:00:00:00:01"; }];
          shares = [{ source = "/nix/store"; mountPoint = "/nix/.ro-store"; tag = "ro-store"; proto = "virtiofs"; }];
          qemu.extraArgs = [ "-acpitable" "file=${hwinfo}" ];
        };
        system.stateVersion = "24.05";
        networking.hostName = "acpi-hwinfo-test";
        services.getty.autologinUser = "root";
        virtualisation.acpi-hwinfo = { enable = true; enableMicrovm = true; guestTools = true; };
      }
    ];
  }
'

# Access the MicroVM runner (if available)
./result/config/microvm/declaredRunner/bin/microvm-run
```

### Test Inside MicroVM

Once the MicroVM is running, test the guest tools:

```bash
# Test reading hardware info
read-hwinfo

# Display formatted hardware info
show-acpi-hwinfo

# Run the comprehensive test script
/etc/test-acpi-hwinfo.sh
```

## Test Files

- `./tests/default.nix` - Test MicroVM configuration and validation scripts
- `./examples/microvm-with-hwinfo.nix` - Example MicroVM configuration with ACPI hardware info
- `./modules/guest.nix` - Guest module with MicroVM options
- `./packages/default.nix` - Test runner implementations

## Expected Output

Successful tests should show:
- ✅ Hardware info generated successfully
- ✅ Module syntax test passed
- ✅ Hardware info JSON/AML found
- ✅ Generated ACPI table: /nix/store/...-test-hwinfo.aml
- ✅ MicroVM configuration validated
- ✅ Guest module integration verified
- ✅ End-to-end test validation completed successfully!

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
- Use `--impure` flag when using `builtins.getFlake`

The tests validate configuration syntax and generate all necessary components. Manual MicroVM execution is optional and provided for complete integration testing.