# QEMU ACPI Hardware Info

Embed host hardware information into QEMU VMs via ACPI tables.

## Usage

```bash
# Generate hardware info on host
nix run .#generate-hwinfo

# Read hardware info in guest
nix run .#read-hwinfo
```

## NixOS Module

```nix
{
  imports = [ inputs.qemu-acpi-hwinfo.nixosModules.default ];
  
  acpi-hwinfo.guest.enable = true;
}
```

## How It Works

1. Host detects NVMe serial and MAC address
2. Generates ACPI SSDT table with hardware info
3. QEMU loads table into VM
4. Guest reads hardware info via ACPI

