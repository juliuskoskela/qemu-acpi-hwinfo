# Testing Guide

This document describes how to test the ACPI hardware info module with MicroVM integration.

## Quick Start

1. **Enter the development shell:**
   ```bash
   nix develop
   ```

2. **Run the end-to-end test:**
   ```bash
   run-test-vm-with-hwinfo
   ```

This will:
- Generate ACPI hardware info for the current system
- Build a MicroVM with the ACPI hardware info module
- Start the MicroVM with virtiofs sharing and ACPI table injection
- Provide a comprehensive test environment

## Available Commands

In the development shell, you have access to:

- `acpi-hwinfo-generate` - Generate ACPI hardware info files
- `acpi-hwinfo-show` - Display current hardware info
- `run-test-vm-with-hwinfo` - Run MicroVM test with ACPI hardware info

## Test Environment

The MicroVM test environment includes:

### Host Features
- **Virtiofs sharing**: `/var/lib/acpi-hwinfo` shared with guest
- **ACPI table injection**: Hardware info injected as custom ACPI table
- **Network access**: NAT networking for package downloads

### Guest Features
- **ACPI hardware info module**: Automatically enabled
- **Guest tools**: Commands to read and display hardware info
- **Test script**: `/etc/test-acpi-hwinfo.sh` for comprehensive testing

### Guest Commands
- `read-hwinfo` - Read hardware info from ACPI device
- `show-acpi-hwinfo` - Display ACPI hardware info
- `extract-hwinfo-json` - Extract JSON from ACPI device

## Example Workflow

```bash
# 1. Enter development environment
nix develop

# 2. Generate hardware info
acpi-hwinfo-generate

# 3. View generated files
acpi-hwinfo-show

# 4. Run MicroVM test
run-test-vm-with-hwinfo

# Inside the MicroVM:
# - Run the test script: /etc/test-acpi-hwinfo.sh
# - Test guest tools: read-hwinfo, show-acpi-hwinfo
# - Exit with Ctrl+C
```

## Configuration

The MicroVM configuration is located in `examples/microvm-with-hwinfo.nix` and includes:

- Guest module import (`../modules/guest.nix`)
- Virtiofs sharing for hardware info files
- ACPI table injection
- Comprehensive test script
- All necessary guest tools

This provides a clean, reproducible way to test the ACPI hardware info module with MicroVM integration.