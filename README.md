# QEMU ACPI Hardware Info

A tool for embedding host hardware information into QEMU virtual machines via ACPI tables, allowing guests to access host hardware identifiers like NVMe serial numbers and MAC addresses.

## Quick Start with Nix (Recommended)

If you have Nix with flakes enabled:

```bash
# Enter development environment with all dependencies
nix develop

# Check hardware info status (detects current machine + shows runtime status)
acpi-hwinfo

# Create test hardware info files for development
create-test-hwinfo

# Start QEMU with hardware info (requires NixOS module or test files)
qemu-with-hwinfo disk.qcow2
```

## Development Commands

The Nix devshell provides these convenience commands:

- **`acpi-hwinfo`** - Show hardware detection and runtime status
- **`create-test-hwinfo`** - Create test hardware info files
- **`qemu-with-hwinfo`** - Start QEMU with runtime hardware info
- **`menu`** - Show available commands

## Runtime Architecture

The new architecture generates hardware info at **runtime** rather than build time:

1. **NixOS Module**: Detects hardware at boot and saves to `/var/lib/acpi-hwinfo/`
2. **QEMU Integration**: Reads from the runtime location when starting VMs
3. **Development Tools**: Create test files and utilities for development

## NixOS Configuration

To enable automatic hardware info generation on NixOS systems:

```nix
{
  # Import the module
  imports = [ ./path/to/qemu-acpi-hwinfo ];
  
  # Enable the service
  services.acpi-hwinfo = {
    enable = true;
    # Optional: override detected values
    # nvmeSerial = "custom-serial";
    # macAddress = "00:11:22:33:44:55";
  };
}
```

This will:
- Create `/var/lib/acpi-hwinfo/` directory
- Generate hardware info at boot time
- Provide `acpi-hwinfo-generate` and `acpi-hwinfo-show` commands

## Architecture

The project uses a modular Nix structure with flake-parts:

- **`nix/packages.nix`** - Package definitions for generating ACPI hardware info
- **`nix/devshell.nix`** - Development shell with convenience commands
- **`nix/formatter.nix`** - Code formatting configuration
- **`nix/nixos-modules.nix`** - NixOS modules for host and guest systems
- **`nix/lib.nix`** - Library functions for creating VMs

## Traditional Usage (without Nix)

### Prerequisites

- `iasl` (Intel ACPI Source Language Compiler)
- `qemu-system-x86_64`
- Root/sudo access for reading hardware information

**Ubuntu/Debian:**
```bash
sudo apt install acpica-tools qemu-system-x86
```

**RHEL/Fedora:**
```bash
sudo dnf install acpica-tools qemu-system-x86
```

### 1. Generate ACPI Table

Auto-detect hardware:
```bash
./qemu-acpi-hwinfo.sh
```

Or specify custom values:
```bash
./qemu-acpi-hwinfo.sh CUSTOM_NVME_SERIAL 00:11:22:33:44:55
```

This creates `hwinfo.aml` containing the ACPI table.

### 2. Start Virtual Machine

```bash
./start-vm.sh [disk_image] [memory]
```

Examples:
```bash
./start-vm.sh                    # Uses disk.qcow2 and 2G RAM
./start-vm.sh ubuntu.qcow2 4G    # Custom disk and memory
```

### 3. Read Hardware Info in Guest

Inside the virtual machine:
```bash
./guest-read-hwinfo.sh
```

## How It Works

1. The host script detects NVMe serial numbers and MAC addresses
2. An ACPI SSDT table is generated containing this information
3. QEMU loads the table, making it available to the guest OS
4. The guest can query the ACPI interface to retrieve the hardware info

## Hardware Detection

- **NVMe Serial**: Uses `nvme` command or `/sys/class/nvme/nvme0/serial`
- **MAC Address**: Extracts from first Ethernet interface via `ip link`

## ACPI Table Structure

The generated SSDT creates a device `\_SB.HWIN` with:
- Device ID: `ACPI0001`
- Method `GHWI`: Returns hardware info as a package
- Always reports as present and enabled

