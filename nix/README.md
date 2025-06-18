# Nix Development Infrastructure

This directory contains the modular Nix configuration for the qemu-acpi-hwinfo project, organized using flake-parts.

## Structure

- **`packages.nix`** - Package definitions for generating ACPI hardware info
- **`devshell.nix`** - Development shell configuration with convenience commands
- **`formatter.nix`** - Code formatting configuration using treefmt-nix
- **`nixos-modules.nix`** - NixOS modules for host and guest systems
- **`lib.nix`** - Library functions for creating VMs with hardware info

## Development Commands

When you enter the development shell with `nix develop`, you get access to these convenience commands:

### `acpi-hwinfo`
Reads hardware info from the current development machine and shows:
- Current NVMe serial number
- Current MAC address
- Instructions for generating hwinfo packages

### `build-hwinfo`
Builds the hwinfo package for the current machine and displays:
- Generated files (hwinfo.aml, hwinfo.asl, hwinfo.json)
- Hardware info in JSON format

### `test-vm`
Provides information about testing hwinfo in microVMs.

## Usage Examples

```bash
# Enter development shell
nix develop

# Read current machine hardware info
acpi-hwinfo

# Build hwinfo package
build-hwinfo

# Format code
nix fmt

# Build with custom hardware values
nix build .#packages.x86_64-linux.generateHwInfo --override-input nvmeSerial "CUSTOM_SERIAL"
```

## Architecture Benefits

This modular structure provides:

1. **Separation of Concerns** - Each file has a specific purpose
2. **Maintainability** - Easier to modify individual components
3. **Reusability** - Modules can be imported independently
4. **Developer Experience** - Rich development shell with helpful commands
5. **Code Quality** - Integrated formatting and linting
6. **Scalability** - Easy to add new modules as the project grows

## Integration with flake-parts

The main `flake.nix` imports all modules using flake-parts, which provides:
- Automatic system handling
- Module composition
- Type checking
- Better error messages