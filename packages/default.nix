{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      # ACPI hardware info generator - detects hardware and creates ACPI files
      acpi-hwinfo-generate = pkgs.writeShellScriptBin "acpi-hwinfo-generate" ''
        #!/bin/bash
        set -euo pipefail
        
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        
        # Check if we can write to the system directory
        if [ ! -w "$(dirname "$HWINFO_DIR")" ] 2>/dev/null; then
          echo "⚠️  Cannot write to $HWINFO_DIR, using local directory instead"
          HWINFO_DIR="./acpi-hwinfo"
        fi
        
        echo "🔧 Generating ACPI hardware info in $HWINFO_DIR..."
        mkdir -p "$HWINFO_DIR"
        
        # Import shared hardware detection functions
        ${inputs.self.lib.hardwareDetectionScript pkgs}
        
        # Detect hardware
        NVME_SERIAL=$(detect_nvme_serial)
        MAC_ADDRESS=$(detect_mac_address)
        
        echo "📊 Detected hardware:"
        echo "   NVMe Serial: $NVME_SERIAL"
        echo "   MAC Address: $MAC_ADDRESS"
        
        # Generate JSON metadata
        cat >"$HWINFO_DIR/hwinfo.json" <<EOF
{
  "nvme_serial": "$NVME_SERIAL",
  "mac_address": "$MAC_ADDRESS",
  "generated": "$(date -Iseconds)"
}
EOF
        
        # Generate ASL file using shared template
        cat >"$HWINFO_DIR/hwinfo.asl" <<EOF
${inputs.self.lib.generateAcpiTemplate { nvmeSerial = "$NVME_SERIAL"; macAddress = "$MAC_ADDRESS"; }}
EOF
        
        # Compile ASL to AML
        echo "🔨 Compiling ACPI table..."
        cd "$HWINFO_DIR"
        ${pkgs.acpica-tools}/bin/iasl hwinfo.asl
        
        echo "✅ Hardware info generated successfully in $HWINFO_DIR"
        echo "📁 Files created:"
        ls -la "$HWINFO_DIR/"
      '';

      # Show current hardware info
      acpi-hwinfo-show = pkgs.writeShellScriptBin "acpi-hwinfo-show" ''
        #!/bin/bash
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        
        if [ ! -d "$HWINFO_DIR" ]; then
          HWINFO_DIR="./acpi-hwinfo"
        fi
        
        if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
          echo "📊 Current hardware info from $HWINFO_DIR:"
          echo
          ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
          echo
          echo "📁 Available files:"
          ls -la "$HWINFO_DIR/"
        else
          echo "❌ No hardware info found in $HWINFO_DIR"
          echo "💡 Run 'acpi-hwinfo-generate' first to create hardware info"
          exit 1
        fi
      '';

      # Status checker with helpful information
      hwinfo-status = pkgs.writeShellScriptBin "hwinfo-status" ''
        #!/bin/bash
        echo "🔍 ACPI Hardware Info Status"
        echo "=========================="
        echo
        
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        if [ ! -d "$HWINFO_DIR" ]; then
          HWINFO_DIR="./acpi-hwinfo"
        fi
        
        echo "📁 Directory: $HWINFO_DIR"
        if [ -d "$HWINFO_DIR" ]; then
          echo "📋 Contents:"
          ls -la "$HWINFO_DIR/"
          echo
          
          if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
            echo "📄 Hardware Info:"
            ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
            echo
            
            if [ -f "$HWINFO_DIR/hwinfo.aml" ]; then
              echo "✅ ACPI table ready: $HWINFO_DIR/hwinfo.aml"
            else
              echo "❌ ACPI table missing: $HWINFO_DIR/hwinfo.aml"
            fi
          else
            echo "❌ No hardware info found"
          fi
        else
          echo "❌ Directory does not exist"
        fi
        
        echo
        echo "🛠️  Available commands:"
        echo "   acpi-hwinfo-generate  - Generate hardware info"
        echo "   acpi-hwinfo-show      - Show current hardware info"
        echo "   qemu-with-hwinfo      - Start QEMU with hardware info"
      '';

      # QEMU launcher with hardware info
      qemu-with-hwinfo = pkgs.writeShellScriptBin "qemu-with-hwinfo" ''
        #!/bin/bash
        set -euo pipefail
        
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        if [ ! -d "$HWINFO_DIR" ]; then
          HWINFO_DIR="./acpi-hwinfo"
        fi
        
        HWINFO_AML="$HWINFO_DIR/hwinfo.aml"
        
        if [ ! -f "$HWINFO_AML" ]; then
          echo "❌ Hardware info not found at $HWINFO_AML"
          echo "💡 Run 'acpi-hwinfo-generate' first"
          exit 1
        fi
        
        DISK_IMAGE="''${1:-disk.qcow2}"
        MEMORY="''${2:-2G}"
        
        if [ ! -f "$DISK_IMAGE" ]; then
          echo "❌ Disk image not found: $DISK_IMAGE"
          echo "💡 Usage: qemu-with-hwinfo [disk_image] [memory]"
          exit 1
        fi
        
        echo "🚀 Starting QEMU with hardware info..."
        echo "   Disk: $DISK_IMAGE"
        echo "   Memory: $MEMORY"
        echo "   ACPI Table: $HWINFO_AML"
        echo
        
        exec ${pkgs.qemu}/bin/qemu-system-x86_64 \
          -machine q35 \
          -cpu host \
          -enable-kvm \
          -m "$MEMORY" \
          -drive file="$DISK_IMAGE",format=qcow2 \
          -acpitable file="$HWINFO_AML" \
          -netdev user,id=net0 \
          -device virtio-net-pci,netdev=net0 \
          -display gtk \
          "$@"
      '';

      # VM test - the only test we keep
      run-test-vm-with-hwinfo = pkgs.writeShellScriptBin "run-test-vm-with-hwinfo" ''
        #!/bin/bash
        set -euo pipefail
        
        echo "🧪 Running VM test with hardware info..."
        
        # Generate test hardware info if needed
        if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ] && [ ! -f "./acpi-hwinfo/hwinfo.aml" ]; then
          echo "📋 Generating test hardware info..."
          ${self'.packages.acpi-hwinfo-generate}/bin/acpi-hwinfo-generate
        fi
        
        # Use test VM image if available, otherwise prompt user
        if [ -f "nixos.qcow2" ]; then
          DISK_IMAGE="nixos.qcow2"
        elif [ -f "test-vm.qcow2" ]; then
          DISK_IMAGE="test-vm.qcow2"
        else
          echo "❌ No test VM image found (nixos.qcow2 or test-vm.qcow2)"
          echo "💡 Create a test VM image first or specify one as argument"
          echo "💡 Usage: run-test-vm-with-hwinfo [disk_image]"
          exit 1
        fi
        
        DISK_IMAGE="''${1:-$DISK_IMAGE}"
        
        echo "🚀 Starting test VM..."
        echo "   Using disk image: $DISK_IMAGE"
        
        ${self'.packages.qemu-with-hwinfo}/bin/qemu-with-hwinfo "$DISK_IMAGE" 2G
      '';
    };
  };
}
