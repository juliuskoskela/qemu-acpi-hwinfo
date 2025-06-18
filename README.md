# QEMU ACPI Hardware Info

A Nix-based solution for injecting hardware information into QEMU virtual machines via ACPI tables. This allows VMs to access host hardware identifiers like NVMe serial numbers and MAC addresses.

## Features

- 🔍 **Robust Hardware Detection**: Multi-method NVMe serial and MAC address detection with comprehensive fallbacks
- 🏗️ **ACPI Table Generation**: Creates SSDT tables that can be injected into QEMU VMs
- 🐧 **NixOS Integration**: Provides both host and guest NixOS modules
- 🧪 **Comprehensive Testing**: Includes VM and MicroVM test configurations with end-to-end testing
- 🛠️ **Rich Development Tools**: Development shell with testing commands and debug support
- 📦 **Modular Design**: Clean, maintainable codebase with shared libraries and DRY principles
- 🔧 **Debug Support**: Built-in debug mode for troubleshooting hardware detection
- 📚 **Comprehensive Documentation**: All commands include `--help` documentation

## Quick Start with Nix (Recommended)

If you have Nix with flakes enabled:

```bash
# Enter development environment with all dependencies
nix develop

# Check hardware info status
nix run .#hwinfo-status

# Generate hardware info
nix run .#acpi-hwinfo-generate

# Show current hardware info
nix run .#acpi-hwinfo-show

# Start QEMU with hardware info
nix run .#qemu-with-hwinfo -- disk.qcow2

# Test with VM (requires sudo for VM creation)
sudo run-test-vm-with-hwinfo

# Enable debug mode for hardware detection
ACPI_HWINFO_DEBUG=true nix run .#acpi-hwinfo-generate
```

## Hardware Detection

The system uses a robust multi-method approach to detect hardware:

### NVMe Serial Detection

1. **nvme id-ctrl**: Most reliable method using nvme-cli to query controller directly
2. **nvme list**: Fallback using nvme-cli list command with proper filtering
3. **sysfs**: Reading from `/sys/class/nvme/nvme0/serial` as final fallback
4. **Graceful fallback**: Returns "no-nvme-detected" if no NVMe found

### MAC Address Detection

1. **ip link**: Uses iproute2 to get the first ethernet interface MAC address
2. **Graceful fallback**: Returns "00:00:00:00:00:00" if no interface found

### Debug Mode

Enable comprehensive debug output to troubleshoot hardware detection:

```bash
ACPI_HWINFO_DEBUG=true acpi-hwinfo-generate
```

This shows detailed information about each detection method attempted and which one succeeded.

## NixOS Modules

This flake provides two NixOS modules:

### Host Module (`acpi-hwinfo-host`)

For the host system that generates hardware info:

```nix
{
  imports = [ inputs.qemu-acpi-hwinfo.nixosModules.acpi-hwinfo-host ];
  
  services.acpi-hwinfo = {
    enable = true;
    generateOnBoot = true;  # Generate hardware info at boot
    # Optional overrides:
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
    enableMicrovm = true;  # For MicroVM integration
    hostHwinfoPath = "/var/lib/acpi-hwinfo/hwinfo.aml";
    guestTools = true;     # Install guest reading tools
  };
}
```

## Architecture

The project uses a clean modular structure:

```
├── modules/           # NixOS modules
│   ├── host.nix      # Host-side hardware detection
│   ├── guest.nix     # Guest-side VM configuration
│   └── default.nix   # Module exports
├── packages/          # Nix packages
│   └── default.nix   # Package definitions
├── scripts/           # Shell scripts
│   ├── acpi-hwinfo-generate.sh
│   ├── acpi-hwinfo-show.sh
│   ├── hwinfo-status.sh
│   └── qemu-with-hwinfo.sh
├── nix/              # Development tooling
│   ├── devshell.nix  # Development environment
│   ├── formatter.nix # Code formatting
│   └── lib.nix       # Helper functions
└── examples/         # Example configurations
    ├── example-vm.nix
    └── microvm.nix
```

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

