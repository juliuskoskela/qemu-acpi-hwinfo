# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project creates ACPI SSDT tables containing hardware information (NVMe serial numbers and MAC addresses) for QEMU virtual machines. The hardware info is embedded in the ACPI tables and can be read from within the guest OS.

## Architecture

The project consists of three main components:

1. **qemu-acpi-hwinfo.sh** - Host-side script that detects hardware info and generates an ACPI SSDT table
2. **start-vm.sh** - QEMU launcher that includes the generated ACPI table
3. **guest-read-hwinfo.sh** - Guest-side script to read the hardware info from ACPI tables

## Workflow

1. Run `qemu-acpi-hwinfo.sh` on the host to generate `hwinfo.aml`
2. Use `start-vm.sh` to launch QEMU with the ACPI table
3. Inside the guest, use `guest-read-hwinfo.sh` to read the embedded hardware info

## Common Commands

### Generate ACPI table with auto-detected hardware:
```bash
./qemu-acpi-hwinfo.sh
```

### Generate ACPI table with custom values:
```bash
./qemu-acpi-hwinfo.sh CUSTOM_NVME_SERIAL 00:11:22:33:44:55
```

### Start VM with default settings:
```bash
./start-vm.sh
```

### Start VM with custom disk and memory:
```bash
./start-vm.sh mydisk.qcow2 4G
```

### Read hardware info from guest OS:
```bash
./guest-read-hwinfo.sh
```

## Dependencies

- `iasl` (ACPI compiler) - required for compiling ACPI tables
- `qemu-system-x86_64` - required for running VMs
- `nvme` command or `/sys/class/nvme/` - for NVMe serial detection