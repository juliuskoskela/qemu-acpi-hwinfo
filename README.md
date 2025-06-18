# QEMU ACPI Hardware Info

A Nix-based tool for embedding host hardware information into QEMU virtual machines via ACPI tables, allowing guests to access host hardware identifiers like NVMe serial numbers and MAC addresses.

## 🚀 Quick Start & Testing

The easiest way to test the functionality:

```bash
# Clone and enter the development environment
git clone https://github.com/juliuskoskela/qemu-acpi-hwinfo.git
cd qemu-acpi-hwinfo
nix develop

# Test the complete workflow with a VM
run-test-vm-with-hwinfo

# Or run automated tests (exits automatically)
run-automated-vm-test
```

This will:
1. Build a NixOS VM with ACPI hardware info support
2. Inject your host's NVMe serial and MAC address via ACPI
3. Boot the VM and automatically test hardware detection
4. Show detected hardware info in the guest

## 📦 Available Commands

### Development Environment (nix develop)

```bash
nix develop  # Enter development shell with all tools

# Main commands available in devshell:
acpi-hwinfo                 # Show hardware detection status
run-test-vm-with-hwinfo     # Test VM with hardware info injection  
run-automated-vm-test       # Automated test (auto-exit)
create-test-hwinfo          # Create test hardware info files
qemu-with-hwinfo           # Start QEMU with hardware info
integration-test           # Run integration tests
```

### Direct Package Usage

```bash
# Hardware detection and generation
nix run .#hwinfo-status           # Check hardware detection status
nix run .#acpi-hwinfo-generate    # Generate ACPI hardware info
nix run .#acpi-hwinfo-show        # Show current hardware info

# Testing and VM management  
nix run .#run-test-vm-with-hwinfo # Run test VM with hardware info
nix run .#run-automated-vm-test   # Automated VM test
nix run .#qemu-with-hwinfo        # Start QEMU with hardware info

# MicroVM testing
nix run .#run-test-microvm        # Test with MicroVM
nix run .#run-automated-microvm-test # Automated MicroVM test
```

## 🔧 NixOS Modules

This flake provides NixOS modules for both host and guest systems:

### Host Module (`acpi-hwinfo-host`)

For the host system that generates hardware info:

```nix
{
  inputs.qemu-acpi-hwinfo.url = "github:juliuskoskela/qemu-acpi-hwinfo";
  
  # In your NixOS configuration:
  imports = [ inputs.qemu-acpi-hwinfo.nixosModules.acpi-hwinfo-host ];
  
  services.acpi-hwinfo = {
    enable = true;
    generateOnBoot = true;  # Generate hardware info at boot
    dataDir = "/var/lib/acpi-hwinfo";  # Storage directory
    
    # Optional overrides (auto-detected if not specified):
    # nvmeSerial = "custom-serial";
    # macAddress = "00:11:22:33:44:55";
  };
}
```

### Guest Module (`acpi-hwinfo-guest`)

For VMs that need to read hardware info:

```nix
{
  imports = [ inputs.qemu-acpi-hwinfo.nixosModules.acpi-hwinfo-guest ];
  
  virtualisation.acpi-hwinfo = {
    enable = true;
    enableMicrovm = false;        # Set to true for MicroVM integration
    enableQemuIntegration = true; # QEMU integration (default)
    hostHwinfoPath = "/var/lib/acpi-hwinfo/hwinfo.aml";
    guestTools = true;           # Install guest reading tools
  };
}
```

### Combined Module

For systems that act as both host and guest:

```nix
{
  imports = [ inputs.qemu-acpi-hwinfo.nixosModules.acpi-hwinfo ];
  
  # Enables both host and guest functionality
  services.acpi-hwinfo.enable = true;
  virtualisation.acpi-hwinfo.enable = true;
}
```

## 🏗️ Architecture

The project uses a clean modular structure:

```
├── modules/           # NixOS modules
│   ├── host.nix      # Host-side hardware detection & ACPI generation
│   ├── guest.nix     # Guest-side VM configuration & tools
│   └── default.nix   # Module exports
├── packages/          # Nix packages & tools
│   └── default.nix   # All package definitions
├── tests/             # Test configurations
│   ├── microvm.nix   # MicroVM test setup
│   └── vm.nix        # Standard VM test setup
├── nix/              # Development tooling
│   ├── devshell.nix  # Development environment
│   ├── formatter.nix # Code formatting
│   └── lib.nix       # Shared hardware detection logic
└── flake.nix         # Main flake configuration
```

## 🔍 Hardware Detection

The system uses multiple detection methods with fallbacks:

### NVMe Serial Detection
1. **Primary**: `nvme id-ctrl /dev/nvmeX` (most reliable)
2. **Fallback**: `nvme list` output parsing  
3. **Last resort**: `/sys/class/nvme/nvme0/serial`

### MAC Address Detection
1. **Primary**: `ip link show` first ethernet interface
2. **Fallback**: Network interface enumeration

### Enhanced Features
- **Validation**: Hardware info format validation
- **Debug mode**: `ACPI_HWINFO_DEBUG=true` for detailed logging
- **Error handling**: Comprehensive fallback mechanisms

## 🔧 How It Works

The system follows a clean workflow:

1. **Hardware Detection**: Host system detects NVMe serial numbers and MAC addresses using multiple methods
2. **ACPI Generation**: Creates an ACPI SSDT table containing the hardware information  
3. **VM Integration**: QEMU loads the ACPI table, making it available to the guest OS
4. **Guest Access**: Guest systems can query the ACPI interface to retrieve hardware info

### ACPI Table Structure

The generated SSDT creates a device `\_SB.HWIN` with:
- **Device ID**: `ACPI0001` 
- **Method `GHWI`**: Returns hardware info as an ACPI package
- **Status**: Always reports as present and enabled
- **Format**: Structured data accessible via standard ACPI interfaces

### Integration Points

- **NixOS Module**: Automatic hardware detection and ACPI generation
- **MicroVM**: Native integration with MicroVM hypervisor
- **QEMU**: Standard QEMU ACPI table injection
- **Guest Tools**: Utilities for reading hardware info in VMs

## 🧪 Testing & Development

### Running Tests

```bash
# Enter development environment
nix develop

# Quick test with VM
run-test-vm-with-hwinfo

# Automated testing (exits automatically)  
run-automated-vm-test

# MicroVM testing
nix run .#run-test-microvm

# Integration tests
integration-test
```

### Debug Mode

Enable detailed logging for troubleshooting:

```bash
ACPI_HWINFO_DEBUG=true nix run .#acpi-hwinfo-generate
ACPI_HWINFO_DEBUG=true run-test-vm-with-hwinfo
```

### Development Workflow

1. **Make changes** to modules or packages
2. **Test locally** with `run-test-vm-with-hwinfo`
3. **Run automated tests** with `run-automated-vm-test`
4. **Verify integration** with `integration-test`

## 📋 Requirements

- **Nix** with flakes enabled
- **Linux host** (for hardware detection)
- **KVM support** (for VM testing)
- **Sufficient RAM** (2GB+ recommended for VMs)

