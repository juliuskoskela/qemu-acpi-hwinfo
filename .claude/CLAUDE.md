# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Structure

This project uses flake-parts with a modular structure:

```
├── flake.nix                 # Minimal flake that imports modules
├── nix/
│   └── flake-module.nix     # Development shell configuration
├── packages/
│   ├── flake-module.nix     # Package definitions
│   ├── generate-hwinfo/     # Hardware info generator
│   ├── read-hwinfo/         # Guest-side reader
│   ├── test-microvm/        # MicroVM test configuration
│   └── ...                  # Other packages
├── modules/
│   ├── flake-module.nix     # NixOS modules and configurations
│   ├── default.nix          # Guest module for reading ACPI in VMs
│   ├── host.nix             # Host module for generating ACPI tables
│   └── test-vm.nix          # Test VM configuration
└── docs/
    └── TESTING.md           # Testing documentation
```

## Common Development Commands

### Testing

```bash
# Enter development environment
nix develop

# Run test VM with host hardware info (main test command)
nix run .#test-vm
# or in devshell:
test-vm
```

### Other Commands

```bash
# Generate hardware info manually
nix run .#generate-hwinfo -- /path/to/output

# Read hardware info (only works inside VM)
read-hwinfo

# Build test VM without running
nix build .#nixosConfigurations.test-vm.config.system.build.vm
```

## Architecture Overview

This project embeds hardware information from the host system into QEMU virtual machines through ACPI tables.

### Key Components

1. **Hardware Detection** (`packages/generate-hwinfo/`)
   - Detects NVMe serial numbers using multiple fallback methods (nvme id-ctrl, nvme list, sysfs, lsblk)
   - Detects primary MAC address from network interfaces
   - Generates ACPI ASL source code with detected hardware info
   - Compiles ASL to AML bytecode using `iasl`

2. **ACPI Table Structure**
   - Creates SSDT table with device `\_SB.HWIN` (ACPI0001)
   - Implements `GHWI` method returning hardware info package
   - Hardware info format: `["NVME_SERIAL", "<serial>", "MAC_ADDRESS", "<mac>"]`

3. **Guest-Side Reading** (`packages/read-hwinfo/`)
   - Scans `/sys/firmware/acpi/tables/SSDT*` for HWINFO table
   - Extracts hardware info strings using `strings` and pattern matching
   - Available as system command when `acpi-hwinfo.guest.enable = true`

4. **NixOS Modules**
   - **Guest Module** (`modules/default.nix`): Provides `acpi-hwinfo.guest.enable` for VMs
   - **Host Module** (`modules/host.nix`): Provides `services.acpi-hwinfo` for automatic generation
   - Systemd service and timer for periodic updates on hosts

5. **Test Infrastructure**
   - Development shell (`nix/flake-module.nix`) with all required tools
   - MicroVM support for lightweight testing
   - Test VM configuration in `modules/test-vm.nix`

### Workflow

1. Host generates hardware info and compiles ACPI table
2. QEMU loads table with `-acpitable file=/path/to/hwinfo.aml`
3. Guest OS accesses hardware info via ACPI using `read-hwinfo`

### Important Paths

- Generated ACPI tables: `/var/lib/acpi-hwinfo/` (default) or custom path
- Test artifacts: `./test-hwinfo.aml`, `/tmp/qemu-acpi-hwinfo-test.aml`
- ACPI device in guest: `/sys/bus/acpi/devices/ACPI0001:00`
- ACPI tables in guest: `/sys/firmware/acpi/tables/SSDT*`

## Flake-Parts Structure

This project uses flake-parts for modular organization:

- Each directory (`nix/`, `packages/`, `modules/`) has a `flake-module.nix`
- The main `flake.nix` imports these modules
- `perSystem` configuration is used for packages and devshells
- `flake` configuration is used for NixOS modules and configurations

When adding new functionality:
1. Place it in the appropriate directory
2. Update the corresponding `flake-module.nix`
3. No need to modify the main `flake.nix`