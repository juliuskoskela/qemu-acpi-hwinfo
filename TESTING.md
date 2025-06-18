# Testing Guide for QEMU ACPI Hardware Info

This document describes the comprehensive test infrastructure for the QEMU ACPI hardware info system.

## Quick Start

Enter the development environment and run all tests:

```bash
nix develop
./run-test-vm-with-hwinfo  # End-to-end test
./test-build.sh            # Build and compilation tests
./test-guest-read.sh       # Guest reading functionality tests
./manual-test.sh           # Manual testing and demonstration
```

## Test Scripts Overview

### 1. `run-test-vm-with-hwinfo` - End-to-End VM Testing

**Purpose**: Complete end-to-end test that demonstrates the full workflow from hardware detection to guest reading.

**What it tests**:
- Hardware info generation from host system
- ACPI table compilation with `iasl`
- ACPI table content verification
- VM test demonstration (shows how to use with QEMU)

**Usage**:
```bash
./run-test-vm-with-hwinfo
```

**Output**: Creates a complete ACPI table and shows how to use it with QEMU.

### 2. `test-build.sh` - Build and Compilation Tests

**Purpose**: Tests the build process and ACPI compilation functionality.

**What it tests**:
- Hardware info generation tool creation
- Hardware info reading tool creation
- ACPI ASL source generation
- ACPI table compilation with `iasl`
- ACPI table content analysis
- Development environment functionality

**Usage**:
```bash
./test-build.sh
```

**Output**: Verifies all build components work correctly and shows generated ACPI content.

### 3. `test-guest-read.sh` - Guest Reading Functionality

**Purpose**: Tests the guest-side hardware info reading functionality.

**What it tests**:
- ACPI table structure analysis
- Hardware info extraction from ACPI tables
- Mock guest environment simulation
- String extraction from compiled ACPI tables

**Usage**:
```bash
./test-guest-read.sh
```

**Output**: Demonstrates how hardware info is extracted from ACPI tables in a guest environment.

### 4. `manual-test.sh` - Manual Testing and Demonstration

**Purpose**: Provides a manual testing environment with detailed explanations.

**What it tests**:
- Step-by-step hardware info generation
- ACPI table analysis and verification
- Guest reading simulation
- VM testing instructions

**Usage**:
```bash
./manual-test.sh
```

**Output**: Creates test artifacts and provides detailed instructions for manual VM testing.

## Development Environment

### Entering the Development Shell

```bash
nix develop
```

This provides:
- `iasl` - ACPI compiler
- `nvme` - NVMe tools for hardware detection
- `qemu-system-x86_64` - QEMU for VM testing
- All necessary development tools

### Available Commands in Dev Shell

The development shell provides helpful information:
```
🚀 QEMU ACPI Hardware Info Development Environment
Available test commands:
  ./run-test-vm-with-hwinfo  - Run end-to-end test with VM
  ./test-build.sh            - Test building hardware info
  ./test-guest-read.sh       - Test guest reading functionality

Development tools available:
  iasl, nvme, qemu-system-x86_64
```

## Testing Workflow

### 1. Basic Functionality Test

```bash
nix develop
./test-build.sh
```

This verifies:
- ✅ Hardware detection works
- ✅ ACPI compilation succeeds
- ✅ Generated tables contain expected data

### 2. Guest Reading Test

```bash
./test-guest-read.sh
```

This verifies:
- ✅ ACPI table parsing works
- ✅ Hardware info extraction works
- ✅ Mock guest environment functions correctly

### 3. End-to-End Test

```bash
./run-test-vm-with-hwinfo
```

This verifies:
- ✅ Complete workflow from detection to VM usage
- ✅ ACPI table can be used with QEMU
- ✅ Instructions for real VM testing

## Real VM Testing

To test with a real VM:

1. **Generate ACPI table**:
   ```bash
   nix develop
   ./run-test-vm-with-hwinfo
   # Note the path to the generated hwinfo.aml file
   ```

2. **Build NixOS VM**:
   ```bash
   nix build .#nixosConfigurations.test-vm.config.system.build.vm
   ```

3. **Run VM with ACPI table**:
   ```bash
   ./result/bin/run-test-vm-vm \
     -acpitable file=/path/to/hwinfo.aml \
     -nographic
   ```

4. **Inside the VM**:
   ```bash
   read-hwinfo  # Should display the hardware info from ACPI
   ```

## Test Output Examples

### Successful Hardware Detection
```
Detected hardware info:
  NVME Serial: SAMSUNG_SSD_980_1TB_S649NX0R123456
  MAC Address: e2:0c:c9:55:0f:dc
```

### ACPI Table Generation
```
✓ Generated ACPI hardware info in /tmp/test-dir
✓ Compiled hwinfo.aml (165 bytes)
```

### Guest Reading
```
Hardware info found:
SAMSUNG_SSD_980_1TB_S649NX0R123456
e2:0c:c9:55:0f:dc
```

## Troubleshooting

### Common Issues

1. **Nix build failures**: The test scripts work around known Nix build issues by creating tools manually.

2. **Missing ACPI device**: Outside a VM, `/sys/bus/acpi/devices/ACPI0001:00` won't exist. This is expected.

3. **No hardware detected**: The scripts provide mock data when real hardware isn't available.

### Debug Information

All test scripts provide detailed output including:
- File paths and sizes
- Hexdump of ACPI tables
- String content analysis
- Step-by-step progress

### Getting Help

Run any test script to see detailed output and instructions. Each script provides:
- Clear success/failure indicators
- Detailed error messages
- Next steps and usage instructions

## Integration with CI/CD

The test scripts are designed to work in automated environments:

```bash
# Run all tests
nix develop --command bash -c "
  ./test-build.sh &&
  ./test-guest-read.sh &&
  ./run-test-vm-with-hwinfo
"
```

All tests return appropriate exit codes for CI/CD integration.