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

2. **Run the test VM**:
   ```bash
   nix run .#test-vm
   ```

   This will:
   - Detect hardware info from your host system
   - Generate an ACPI table with the hardware info
   - Build and start a test VM with the ACPI table
   - Allow you to run `read-hwinfo` inside the VM to verify it works

3. **Generate hardware info manually**:
   ```bash
   nix run .#generate-hwinfo -- /path/to/output
   ```

## Testing

The main test command runs a VM with your host's hardware info:

```bash
nix run .#test-vm
```

This provides an end-to-end test that:
- ✅ Detects hardware (NVMe serial, MAC address) from your host
- ✅ Generates and compiles ACPI table
- ✅ Builds a NixOS VM with the guest tools
- ✅ Injects the ACPI table into the VM
- ✅ Allows verification with `read-hwinfo` inside the VM

## Usage

### Host Setup (Automatic Generation)

For production use on VM hosts, enable the NixOS module:

```nix
{
  imports = [ qemu-acpi-hwinfo.nixosModules.host ];
  
  services.acpi-hwinfo = {
    enable = true;
    outputDir = "/var/lib/acpi-hwinfo";  # default
  };
}
```

This generates ACPI tables on every boot and rebuild. See [HOST-SETUP.md](docs/HOST-SETUP.md) for details.

### Manual Generation

For testing or one-off use:

```bash
# Generate in default location (/var/lib/acpi-hwinfo)
nix run .#generate-hwinfo

# Generate in custom location
nix run .#generate-hwinfo -- /path/to/output
```

### VM Configuration

Configure VMs to use the generated ACPI table:

```bash
qemu-system-x86_64 \
  -acpitable file=/var/lib/acpi-hwinfo/hwinfo.aml \
  # ... other QEMU options
```

### Guest Side (Read Hardware Info)

In the guest VM with the NixOS module enabled:

```nix
{
  imports = [ qemu-acpi-hwinfo.nixosModules.guest ];
  acpi-hwinfo.guest.enable = true;
}
```

Then read the hardware info:

```bash
read-hwinfo
```

## NixOS Modules

### Host Module

For VM host systems to automatically generate ACPI tables:

```nix
{
  services.acpi-hwinfo = {
    enable = true;                        # Enable automatic generation
    outputDir = "/var/lib/acpi-hwinfo";   # Where to store files
  };
}
```

### Guest Module  

For VMs to read hardware info from ACPI:

```nix
{
  acpi-hwinfo = {
    guest.enable = true;  # Adds read-hwinfo command
  };
}
```

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

