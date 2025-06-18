# QEMU ACPI Hardware Info - Nix Flake

A nixified version of the QEMU ACPI Hardware Info tool that provides hardware information to QEMU virtual machines via ACPI tables using Nix flakes and microvm.nix.

## Features

- **Nix Flake**: Complete flake-based build system
- **NixOS Modules**: Ready-to-use modules for both host and guest
- **MicroVM Integration**: Built-in support for microvm.nix
- **Derivation-based**: Hardware info generation as a pure Nix derivation
- **Configurable**: Override hardware values or auto-detect from host

## Quick Start

### Prerequisites

- Nix with flakes enabled
- Linux system (for hardware detection)

### Enable Nix Flakes

```bash
# Add to ~/.config/nix/nix.conf or /etc/nix/nix.conf
experimental-features = nix-command flakes
```

### Generate Hardware Info

```bash
# Auto-detect hardware and generate ACPI table
nix build .#hwinfo

# View generated hardware info
cat result/hwinfo.json
ls -la result/hwinfo.aml
```

### Run a MicroVM with Hardware Info

```bash
# Build and run the example VM
nix build .#nixosConfigurations.vm.config.microvm.declaredRunner
./result/bin/microvm-run
```

## Usage

### As a Flake Input

Add to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    qemu-acpi-hwinfo.url = "path:./path/to/this/flake";
    microvm.url = "github:astro/microvm.nix";
  };

  outputs = { self, nixpkgs, qemu-acpi-hwinfo, microvm }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      nixosConfigurations.my-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          qemu-acpi-hwinfo.nixosModules.guest
          {
            services.acpi-hwinfo-guest.enable = true;

            microvm = {
              enable = true;
              qemu.extraArgs = [
                "-acpitable"
                "file=${qemu-acpi-hwinfo.packages.${system}.default}/hwinfo.aml"
              ];
              # ... other microvm config
            };
          }
        ];
      };
    };
}
```

### Custom Hardware Values

```bash
# Generate with custom values
nix build .#packages.x86_64-linux.hwinfo-custom \
  --override-input nvmeSerial "CUSTOM_SERIAL_123" \
  --override-input macAddress "00:11:22:33:44:55"
```

Or in Nix code:

```nix
let
  customHwInfo = qemu-acpi-hwinfo.packages.${system}.generateHwInfo {
    nvmeSerial = "CUSTOM_SERIAL_123";
    macAddress = "00:11:22:33:44:55";
  };
in {
  microvm.qemu.extraArgs = [
    "-acpitable"
    "file=${customHwInfo}/hwinfo.aml"
  ];
}
```

### Using the Helper Function

```nix
{
  nixosConfigurations.my-vm = qemu-acpi-hwinfo.lib.mkMicroVMWithHwInfo {
    system = "x86_64-linux";
    nvmeSerial = "CUSTOM_SERIAL";  # optional
    macAddress = "00:11:22:33:44:55";  # optional

    # Additional microvm configuration
    microvm.vcpu = 4;
    microvm.mem = 4096;

    # Additional system configuration
    services.openssh.enable = true;
  };
}
```

## Available Outputs

### Packages

- `hwinfo` - Auto-detected hardware info ACPI table
- `hwinfo-custom` - Function to generate custom hardware info

### NixOS Modules

- `acpi-hwinfo` - Host-side module for generating hardware info
- `guest` - Guest-side module for reading hardware info

### Apps

- `generate-hwinfo` - CLI app to generate hardware info

### Library Functions

- `mkMicroVMWithHwInfo` - Helper to create MicroVM with hardware info

## Development

### Development Shell

```bash
nix develop
```

This provides:
- `acpica-tools` (iasl compiler)
- `qemu`
- `iproute2`
- `nvme-cli`

### Testing

```bash
# Build the hardware info derivation
nix build .#hwinfo

# Check the generated files
ls -la result/
cat result/hwinfo.json
hexdump -C result/hwinfo.aml | head

# Test the VM
nix build .#nixosConfigurations.vm.config.microvm.declaredRunner
./result/bin/microvm-run
```

### Inside the Guest VM

Once the VM is running, you can read the hardware info:

```bash
# Using the provided script
read-hwinfo

# Or manually
sudo strings /sys/firmware/acpi/tables/SSDT* | grep -A 1 -B 1 "NVME_SERIAL\|MAC_ADDRESS"
```

## How It Works

1. **Hardware Detection**: The Nix derivation detects NVMe serial numbers and MAC addresses from the build environment
2. **ACPI Generation**: Creates an ACPI SSDT table containing the hardware info
3. **Compilation**: Uses `iasl` to compile the table to `.aml` format
4. **Storage**: Stores the compiled table in the Nix store
5. **VM Integration**: MicroVM configuration automatically includes the table via `-acpitable` flag
6. **Guest Access**: Guest VMs can read the hardware info through ACPI interfaces

## File Structure

```
.
├── flake.nix              # Main flake definition
├── microvm.nix            # Example MicroVM configuration
├── run-vm.sh              # Helper script to build and run
├── README-NIX.md          # This file
└── legacy/                # Original shell scripts (for reference)
    ├── qemu-acpi-hwinfo.sh
    ├── start-vm.sh
    └── guest-read-hwinfo.sh
```

## Migration from Shell Scripts

The original shell scripts are preserved for reference, but the Nix version provides:

- **Reproducibility**: Pure builds with no side effects
- **Caching**: Nix store caching of generated tables
- **Integration**: Seamless integration with NixOS and microvm.nix
- **Modularity**: Reusable components via flake outputs
- **Configuration**: Declarative VM configuration

## Troubleshooting

### Hardware Detection Issues

If hardware detection fails in the Nix build environment:

```bash
# Use custom values instead
nix build .#packages.x86_64-linux.hwinfo-custom \
  --override-input nvmeSerial "YOUR_SERIAL" \
  --override-input macAddress "YOUR_MAC"
```

### VM Won't Start

Check that:
1. KVM is available: `ls /dev/kvm`
2. User is in kvm group: `groups`
3. Nix daemon is running: `systemctl status nix-daemon`

### ACPI Table Not Found in Guest

Verify the table is loaded:
```bash
# In guest
ls /sys/firmware/acpi/tables/
sudo cat /sys/firmware/acpi/tables/SSDT* | strings | grep -i hwinfo
```

## License

MIT License - see original project for details.