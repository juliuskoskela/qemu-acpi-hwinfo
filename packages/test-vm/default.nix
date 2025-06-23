{ pkgs, generate-hwinfo }:

pkgs.writeShellScriptBin "test-vm" ''
  set -euo pipefail
  
  echo "🚀 Testing QEMU ACPI Hardware Info"
  echo "=================================="
  echo
  
  # Check if we need sudo for hardware detection
  if [ "$EUID" -ne 0 ] && ! nvme list >/dev/null 2>&1; then
    echo "⚠️  Hardware detection may require sudo privileges"
    echo "   Run with: sudo test-vm"
    echo
    echo "   Continuing anyway, but NVMe detection might fail..."
    echo
  fi
  
  # Generate hardware info from host
  echo "📋 Generating hardware info from host system..."
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf $TEMP_DIR" EXIT
  
  ${pkgs.lib.getExe generate-hwinfo} "$TEMP_DIR"
  
  if [ ! -f "$TEMP_DIR/hwinfo.aml" ]; then
    echo "❌ Failed to generate ACPI table"
    exit 1
  fi
  
  echo "✅ Generated ACPI table: $TEMP_DIR/hwinfo.aml"
  echo
  
  # Display what was detected
  echo "📊 Hardware info detected:"
  if [ -f "$TEMP_DIR/hwinfo.asl" ]; then
    grep -E "(NVME_SERIAL|MAC_ADDRESS)" "$TEMP_DIR/hwinfo.asl" | grep -v "Method" | sed 's/.*"\(.*\)".*/  \1/'
  fi
  echo
  
  # Build and run the test VM
  echo "🔨 Building test VM..."
  VM_PATH=$(nix build --no-link --print-out-paths .#nixosConfigurations.test-vm.config.system.build.vm)
  
  if [ -z "$VM_PATH" ]; then
    echo "❌ Failed to build test VM"
    exit 1
  fi
  
  echo "✅ VM built successfully"
  echo
  echo "🖥️  Starting VM with ACPI hardware info..."
  echo "   - VM will auto-login as root"
  echo "   - Run 'read-hwinfo' inside the VM to see hardware info"
  echo "   - Press Ctrl+A X to exit QEMU"
  echo
  
  # Run the VM with the ACPI table
  VM_RUNNER=$(find "$VM_PATH/bin" -name "run-*" -type l | head -1)
  if [ -z "$VM_RUNNER" ]; then
    echo "❌ Could not find VM runner script"
    ls -la "$VM_PATH/bin/" >&2
    exit 1
  fi
  exec "$VM_RUNNER" -acpitable file="$TEMP_DIR/hwinfo.aml"
''