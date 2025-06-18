{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      # QEMU launcher that uses runtime-generated hwinfo
      qemu-with-hwinfo = pkgs.writeShellScriptBin "qemu-with-hwinfo" ''
        #!/bin/bash
        set -euo pipefail
        
        HWINFO_PATH="/var/lib/acpi-hwinfo/hwinfo.aml"
        
        # Check if hwinfo exists
        if [ ! -f "$HWINFO_PATH" ]; then
          echo "❌ Hardware info not found at $HWINFO_PATH"
          echo "💡 Make sure the acpi-hwinfo NixOS module is enabled and has run"
          echo "💡 Or run: sudo acpi-hwinfo-generate"
          exit 1
        fi
        
        echo "🚀 Starting QEMU with hardware info from $HWINFO_PATH"
        
        # Default QEMU arguments
        QEMU_ARGS=(
          -machine q35
          -cpu host
          -enable-kvm
          -m 2G
          -acpitable file="$HWINFO_PATH"
        )
        
        # Add disk if provided
        if [ $# -gt 0 ] && [ -f "$1" ]; then
          QEMU_ARGS+=(-drive file="$1",format=qcow2)
          shift
        fi
        
        # Add any additional arguments
        QEMU_ARGS+=("$@")
        
        echo "🔧 QEMU command: qemu-system-x86_64 ''${QEMU_ARGS[*]}"
        exec qemu-system-x86_64 "''${QEMU_ARGS[@]}"
      '';

      # Utility to show current hwinfo status
      hwinfo-status = pkgs.writeShellScriptBin "hwinfo-status" ''
        #!/bin/bash
        
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        
        echo "🔍 ACPI Hardware Info Status"
        echo "=========================="
        echo
        
        if [ -d "$HWINFO_DIR" ]; then
          echo "📁 Directory: $HWINFO_DIR"
          echo "📋 Contents:"
          ls -la "$HWINFO_DIR/" 2>/dev/null || echo "   (empty or no access)"
          echo
          
          if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
            echo "📄 Hardware Info:"
            ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
          else
            echo "❌ No hwinfo.json found"
          fi
          
          echo
          if [ -f "$HWINFO_DIR/hwinfo.aml" ]; then
            echo "✅ ACPI table ready: $HWINFO_DIR/hwinfo.aml"
          else
            echo "❌ No hwinfo.aml found"
          fi
        else
          echo "❌ Hardware info directory not found: $HWINFO_DIR"
          echo "💡 Enable the acpi-hwinfo NixOS module to create it"
        fi
        
        echo
        echo "🛠️  Available commands:"
        echo "   acpi-hwinfo-generate  - Generate hardware info"
        echo "   acpi-hwinfo-show      - Show current hardware info"
        echo "   qemu-with-hwinfo      - Start QEMU with hardware info"
      '';

      # Development utility to create test hwinfo
      create-test-hwinfo = pkgs.writeShellScriptBin "create-test-hwinfo" ''
        #!/bin/bash
        set -euo pipefail
        
        NVME_SERIAL="''${1:-test-nvme-serial}"
        MAC_ADDRESS="''${2:-00:11:22:33:44:55}"
        OUTPUT_DIR="''${3:-./test-hwinfo}"
        
        echo "🧪 Creating test hardware info..."
        echo "   NVMe Serial: $NVME_SERIAL"
        echo "   MAC Address: $MAC_ADDRESS"
        echo "   Output Dir: $OUTPUT_DIR"
        
        mkdir -p "$OUTPUT_DIR"
        
        # Generate JSON
        cat > "$OUTPUT_DIR/hwinfo.json" <<EOF
{
  "nvme_serial": "$NVME_SERIAL",
  "mac_address": "$MAC_ADDRESS",
  "generated": "$(date -Iseconds)"
}
EOF
        
        # Generate ASL
        cat > "$OUTPUT_DIR/hwinfo.asl" <<EOF
DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
{
    Scope (\_SB)
    {
        Device (HWIN)
        {
            Name (_HID, "ACPI0001")
            Name (_STA, 0x0F)
            Method (GHWI, 0, NotSerialized)
            {
                Return (Package (0x02)
                {
                    "$NVME_SERIAL",
                    "$MAC_ADDRESS"
                })
            }
        }
    }
}
EOF
        
        # Compile to AML
        cd "$OUTPUT_DIR"
        ${pkgs.acpica-tools}/bin/iasl hwinfo.asl
        
        echo "✅ Test hardware info created in $OUTPUT_DIR"
        echo "📋 Files:"
        ls -la "$OUTPUT_DIR/"
      '';

      # Default package points to the QEMU launcher
      default = self'.packages.qemu-with-hwinfo;
    };
  };
}
