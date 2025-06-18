# QEMU ACPI Hardware Info

A NixOS module and tools for embedding hardware information in ACPI tables for QEMU virtual machines.

## Overview

This project provides a way to pass hardware information from the host system to QEMU virtual machines through ACPI tables. The hardware information is detected on the host, compiled into an ACPI SSDT table, and can be read by the guest operating system.

## Features

- **Hardware Detection**: Automatically detects NVMe serial numbers and MAC addresses
- **ACPI Integration**: Generates ACPI SSDT tables containing hardware information
- **NixOS Module**: Provides a NixOS module for easy integration
- **Guest Tools**: Includes tools for reading hardware info from within the VM
- **Comprehensive Testing**: Full test suite with end-to-end VM testing

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd qemu-acpi-hwinfo
   ```

2. **Enter the development environment**:
   ```bash
   nix develop
   ```

3. **Run the test suite**:
   ```bash
   ./run-test-vm-with-hwinfo  # End-to-end test
   ./test-build.sh            # Build tests
   ./test-guest-read.sh       # Guest functionality tests
   ```

4. **Generate hardware info**:
   ```bash
   nix run .#generate-hwinfo
   ```

## Testing

This project includes comprehensive testing infrastructure. See [TESTING.md](TESTING.md) for detailed testing documentation.

### Quick Test Commands

```bash
# Enter development environment
nix develop

# Run all tests
./run-test-vm-with-hwinfo  # Complete end-to-end test
./test-build.sh            # Build and compilation tests  
./test-guest-read.sh       # Guest reading functionality
./manual-test.sh           # Manual testing with detailed output
```

### Test Coverage

- ✅ Hardware detection and ACPI generation
- ✅ ACPI table compilation with `iasl`
- ✅ Guest-side hardware info extraction
- ✅ End-to-end VM workflow demonstration
- ✅ Mock environment testing
- ✅ Development environment validation

## Usage

### Host Side (Generate ACPI Table)

Generate hardware information and compile it into an ACPI table:

```bash
# Generate in default location (/var/lib/acpi-hwinfo)
nix run .#generate-hwinfo

# Generate in custom location
nix run .#generate-hwinfo /path/to/output
```

This creates:
- `hwinfo.asl` - ACPI source code
- `hwinfo.aml` - Compiled ACPI table

### QEMU Integration

Use the generated ACPI table with QEMU:

```bash
qemu-system-x86_64 \
  -acpitable file=/var/lib/acpi-hwinfo/hwinfo.aml \
  # ... other QEMU options
```

### Guest Side (Read Hardware Info)

In the guest VM with the NixOS module enabled:

```bash
# Read hardware information
read-hwinfo
```

This will output the hardware information that was embedded in the ACPI table.

## NixOS Module

The module provides the following options:

```nix
{
  acpi-hwinfo = {
    guest.enable = true;  # Enable guest-side tools
  };
}
```

When enabled, the module:
- Adds the `read-hwinfo` command to the system
- Provides tools for extracting hardware info from ACPI tables

### Example NixOS Configuration

```nix
{
  inputs.qemu-acpi-hwinfo.url = "github:your-username/qemu-acpi-hwinfo";
  
  outputs = { self, nixpkgs, qemu-acpi-hwinfo }: {
    nixosConfigurations.my-vm = nixpkgs.lib.nixosSystem {
      modules = [
        qemu-acpi-hwinfo.nixosModules.default
        {
          acpi-hwinfo.guest.enable = true;
        }
      ];
    };
  };
}
```

## Development

### Development Environment

Enter the development shell:

```bash
nix develop
```

This provides:
- ACPI tools (`iasl`)
- Hardware detection tools (`nvme-cli`, `iproute2`)
- QEMU for VM testing
- All test scripts and development utilities

The development shell shows available commands:
```
🚀 QEMU ACPI Hardware Info Development Environment
Available test commands:
  ./run-test-vm-with-hwinfo  - Run end-to-end test with VM
  ./test-build.sh            - Test building hardware info
  ./test-guest-read.sh       - Test guest reading functionality

Development tools available:
  iasl, nvme, qemu-system-x86_64
```

### Building

Build individual components:

```bash
# Build hardware info generator
nix build .#generate-hwinfo

# Build hardware info reader
nix build .#read-hwinfo

# Build test VM
nix build .#nixosConfigurations.test-vm.config.system.build.vm
```

### Testing and Validation

The project includes comprehensive testing:

```bash
# Run all tests in development environment
nix develop --command bash -c "
  ./test-build.sh &&
  ./test-guest-read.sh &&
  ./run-test-vm-with-hwinfo
"

# Individual test components
./test-build.sh            # Build and compilation
./test-guest-read.sh       # Guest functionality
./run-test-vm-with-hwinfo  # End-to-end workflow
./manual-test.sh           # Manual testing with detailed output
```

See [TESTING.md](TESTING.md) for comprehensive testing documentation.

## Architecture

### Components

1. **Hardware Detection**: Scans for NVMe devices and network interfaces
2. **ACPI Generation**: Creates ACPI SSDT tables with hardware information
3. **ACPI Compilation**: Uses `iasl` to compile ASL source to AML bytecode
4. **Guest Tools**: Extracts hardware information from ACPI tables in the VM
5. **Test Infrastructure**: Comprehensive testing covering all components

### ACPI Table Structure

The generated ACPI table creates a device with:
- **Device ID**: `ACPI0001`
- **Hardware ID**: `HWIN`
- **Method**: `GHWI` - Returns hardware information package

Example ACPI structure:
```asl
DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
{
    Scope (\_SB)
    {
        Device (HWIN)
        {
            Name (_HID, "ACPI0001")
            Name (_UID, 0x00)
            Method (GHWI, 0, NotSerialized)
            {
                Return (Package (0x04)
                {
                    "NVME_SERIAL", "actual-serial-number",
                    "MAC_ADDRESS", "actual-mac-address"
                })
            }
            Method (_STA, 0, NotSerialized) { Return (0x0F) }
        }
    }
}
```

### Testing Architecture

The testing infrastructure includes:

- **Unit Tests**: Individual component testing
- **Integration Tests**: Cross-component functionality
- **End-to-End Tests**: Complete workflow validation
- **Mock Environments**: Simulated guest environments
- **Manual Testing**: Detailed step-by-step validation

## Files and Structure

```
├── flake.nix              # Main Nix flake with packages and modules
├── modules/default.nix    # NixOS module definition
├── devshell.nix          # Development environment
├── run-test-vm-with-hwinfo # End-to-end VM test script
├── test-build.sh         # Build and compilation tests
├── test-guest-read.sh    # Guest reading functionality tests
├── manual-test.sh        # Manual testing and demonstration
├── TESTING.md            # Comprehensive testing documentation
└── README.md             # This file
```

## How It Works

1. Host detects NVMe serial and MAC address
2. Generates ACPI SSDT table with hardware info
3. QEMU loads table into VM with `-acpitable` option
4. Guest reads hardware info via ACPI using `read-hwinfo`

## License

[Add your license information here]

## Contributing

[Add contribution guidelines here]

For testing and development, see [TESTING.md](TESTING.md) for detailed information about the test infrastructure and development workflow.

