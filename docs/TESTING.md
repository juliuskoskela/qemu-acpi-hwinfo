# Testing Guide for QEMU ACPI Hardware Info

## Quick Start

Run the test VM with your host's hardware info:

```bash
nix run .#test-vm
```

This single command provides a complete end-to-end test of the ACPI hardware info system.

## What the Test Does

1. **Detects Hardware** - Reads NVMe serial number and MAC address from your host system
2. **Generates ACPI Table** - Creates ASL source and compiles it to AML bytecode
3. **Builds Test VM** - Builds a NixOS VM with the guest tools installed
4. **Runs VM with ACPI** - Starts QEMU with the ACPI table injected
5. **Allows Verification** - Run `read-hwinfo` inside the VM to see the hardware info

## Expected Output

When you run `test-vm`, you should see:

```
🚀 Testing QEMU ACPI Hardware Info
==================================

📋 Generating hardware info from host system...
✅ Generated ACPI table: /tmp/tmp.XXXXX/hwinfo.aml

📊 Hardware info detected:
  NVME_SERIAL: S6Z2NJ0TB38698J
  MAC_ADDRESS: c8:7f:54:05:d8:e9

🔨 Building test VM...
✅ VM built successfully

🖥️  Starting VM with ACPI hardware info...
   - VM will auto-login as root
   - Run 'read-hwinfo' inside the VM to see hardware info
   - Press Ctrl+A X to exit QEMU
```

Inside the VM, running `read-hwinfo` should output:
```
S6Z2NJ0TB38698J
c8:7f:54:05:d8:e9
```

## Manual Testing

If you want to test components individually:

```bash
# Generate hardware info manually
nix run .#generate-hwinfo -- /tmp/test-hwinfo

# Check the generated files
cat /tmp/test-hwinfo/hwinfo.asl  # ASL source
file /tmp/test-hwinfo/hwinfo.aml  # Compiled AML

# Build VM without running
nix build .#nixosConfigurations.test-vm.config.system.build.vm

# Run VM with custom ACPI table
./result/bin/run-*-vm -acpitable file=/tmp/test-hwinfo/hwinfo.aml
```

## Troubleshooting

### No NVMe Serial Detected

If you see "no-nvme-detected", the system either:
- Has no NVMe drives
- NVMe tools lack permissions (try with sudo)
- NVMe serial is not exposed by the hardware

### read-hwinfo Shows "ACPI device not found"

This command only works inside a VM with the ACPI table loaded. It won't work on the host system.

### VM Doesn't Start

Ensure you have KVM support:
```bash
ls /dev/kvm  # Should exist
```

If not, the VM will run in emulation mode (slower).