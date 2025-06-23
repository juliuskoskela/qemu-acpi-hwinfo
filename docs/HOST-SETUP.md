# Host Setup Guide

This guide explains how to set up the host-side NixOS module that automatically generates ACPI hardware info for VMs.

## Configuration

Add the module to your NixOS configuration:

```nix
{
  imports = [
    qemu-acpi-hwinfo.nixosModules.host
  ];

  # Enable the service
  services.acpi-hwinfo = {
    enable = true;
    
    # Optional: customize output directory (default: /var/lib/acpi-hwinfo)
    outputDir = "/var/lib/acpi-hwinfo";
  };
}
```

## What It Does

The host module:

1. **Creates a systemd service** that generates ACPI hardware info files
2. **Runs automatically** on every boot and NixOS rebuild
3. **Generates files** in the specified `outputDir`:
   - `hwinfo.asl` - ACPI source file
   - `hwinfo.aml` - Compiled ACPI binary
   - `metadata.json` - Generation timestamp and host info

## Using with VMs

Once the host module is enabled, you can configure VMs to use the generated ACPI table:

### With NixOS VM configuration:

```nix
{
  virtualisation.qemu.options = [
    "-acpitable file=/var/lib/acpi-hwinfo/hwinfo.aml"
  ];
}
```

### With raw QEMU:

```bash
qemu-system-x86_64 \
  -acpitable file=/var/lib/acpi-hwinfo/hwinfo.aml \
  # ... other options
```

### With libvirt XML:

```xml
<domain>
  <qemu:commandline>
    <qemu:arg value='-acpitable'/>
    <qemu:arg value='file=/var/lib/acpi-hwinfo/hwinfo.aml'/>
  </qemu:commandline>
</domain>
```

## Manual Operations

The service also adds `generate-hwinfo` to system packages, so you can manually regenerate:

```bash
# Regenerate in default location
sudo generate-hwinfo

# Or specify custom location
sudo generate-hwinfo /tmp/custom-hwinfo
```

To manually trigger the service:

```bash
sudo systemctl start acpi-hwinfo-generate
```

To check the service status:

```bash
systemctl status acpi-hwinfo-generate
```

## Verification

Check that hardware info is being generated:

```bash
ls -la /var/lib/acpi-hwinfo/
cat /var/lib/acpi-hwinfo/metadata.json
```

The directory should contain:
- `hwinfo.aml` - The compiled ACPI table to use with VMs
- `hwinfo.asl` - The source (for debugging)
- `metadata.json` - Generation metadata