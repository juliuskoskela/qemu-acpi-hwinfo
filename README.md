# QEMU ACPI Hardware Info

A tool for embedding host hardware information into QEMU virtual machines via ACPI tables, allowing guests to access host hardware identifiers like NVMe serial numbers and MAC addresses.

## Overview

This project provides a way to pass hardware information from the host system to QEMU guests through ACPI SSDT tables. The hardware info becomes accessible within the guest OS through the ACPI interface.

## Components

- **qemu-acpi-hwinfo.sh** - Detects host hardware and generates ACPI SSDT table
- **start-vm.sh** - Launches QEMU with the generated ACPI table
- **guest-read-hwinfo.sh** - Reads hardware info from ACPI tables within the guest

## Prerequisites

- `iasl` (Intel ACPI Source Language Compiler)
- `qemu-system-x86_64`
- Root/sudo access for reading certain hardware information

### Installing Prerequisites

**Ubuntu/Debian:**
```bash
sudo apt install acpica-tools qemu-system-x86
```

**RHEL/Fedora:**
```bash
sudo dnf install acpica-tools qemu-system-x86
```

## Quick Start with Nix (Recommended)

If you have Nix with flakes enabled:

```bash
# Enter development environment
nix develop

# Read current machine hardware info
acpi-hwinfo

# Build hwinfo package for current machine
build-hwinfo

# The generated files will be in ./result/
ls -la ./result/
```

The Nix-based workflow provides a complete development environment with all dependencies and convenience commands. See [`nix/README.md`](nix/README.md) for detailed information about the modular Nix structure.

## Traditional Usage

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

