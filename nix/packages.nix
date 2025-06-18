{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      # QEMU launcher that uses runtime-generated hwinfo
      qemu-with-hwinfo = pkgs.writeShellScriptBin "qemu-with-hwinfo" ''
        #!/bin/bash
        set -euo pipefail
        
        # Check multiple possible locations for hwinfo
        HWINFO_PATHS=("/var/lib/acpi-hwinfo/hwinfo.aml" "./acpi-hwinfo/hwinfo.aml")
        HWINFO_PATH=""
        
        for path in "''${HWINFO_PATHS[@]}"; do
          if [ -f "$path" ]; then
            HWINFO_PATH="$path"
            break
          fi
        done
        
        if [ -z "$HWINFO_PATH" ]; then
          echo "❌ Hardware info not found in any of these locations:"
          for path in "''${HWINFO_PATHS[@]}"; do
            echo "   $path"
          done
          echo "💡 Run 'acpi-hwinfo-generate' first to create hardware info"
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
        
        HWINFO_DIRS=("/var/lib/acpi-hwinfo" "./acpi-hwinfo")
        
        echo "🔍 ACPI Hardware Info Status"
        echo "=========================="
        echo
        
        found_any=false
        for HWINFO_DIR in "''${HWINFO_DIRS[@]}"; do
          if [ -d "$HWINFO_DIR" ]; then
            found_any=true
            echo "📁 Directory: $HWINFO_DIR"
            echo "📋 Contents:"
            ls -la "$HWINFO_DIR/" 2>/dev/null || echo "   (empty or no access)"
            echo
            
            if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
              echo "📄 Hardware Info:"
              ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
            else
              echo "❌ No hwinfo.json found in $HWINFO_DIR"
            fi
            
            echo
            if [ -f "$HWINFO_DIR/hwinfo.aml" ]; then
              echo "✅ ACPI table ready: $HWINFO_DIR/hwinfo.aml"
            else
              echo "❌ No hwinfo.aml found in $HWINFO_DIR"
            fi
            echo
          fi
        done
        
        if [ "$found_any" = false ]; then
          echo "❌ Hardware info directory not found in any of these locations:"
          for dir in "''${HWINFO_DIRS[@]}"; do
            echo "   $dir"
          done
          echo "💡 Run 'acpi-hwinfo-generate' to create hardware info"
        fi
        
        echo
        echo "🛠️  Available commands:"
        echo "   acpi-hwinfo-generate  - Generate hardware info"
        echo "   acpi-hwinfo-show      - Show current hardware info"
        echo "   qemu-with-hwinfo      - Start QEMU with hardware info"
      '';

      # Generate hardware info (standalone version for development)
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
        
        # Detect NVMe serial
        NVME_SERIAL=""
        if command -v nvme >/dev/null 2>&1; then
          NVME_SERIAL=$(nvme list 2>/dev/null | awk 'NR>1 {print $2; exit}' || echo "")
        fi
        if [ -z "$NVME_SERIAL" ] && [ -f /sys/class/nvme/nvme0/serial ]; then
          NVME_SERIAL=$(cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "")
        fi
        if [ -z "$NVME_SERIAL" ]; then
          NVME_SERIAL="no-nvme-detected"
        fi
        
        # Detect MAC address
        MAC_ADDRESS=""
        if command -v ip >/dev/null 2>&1; then
          MAC_ADDRESS=$(ip link show | awk '/ether/ {print $2; exit}' || echo "")
        fi
        if [ -z "$MAC_ADDRESS" ]; then
          MAC_ADDRESS="00:00:00:00:00:00"
        fi
        
        echo "📊 Detected hardware:"
        echo "   NVMe Serial: $NVME_SERIAL"
        echo "   MAC Address: $MAC_ADDRESS"
        
        # Generate JSON file
        cat > "$HWINFO_DIR/hwinfo.json" <<EOF
{
  "nvme_serial": "$NVME_SERIAL",
  "mac_address": "$MAC_ADDRESS",
  "generated": "$(date -Iseconds)"
}
EOF
        
        # Generate ASL file
        cat > "$HWINFO_DIR/hwinfo.asl" <<EOF
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
        
        # Compile ASL to AML
        if command -v iasl >/dev/null 2>&1; then
          cd "$HWINFO_DIR"
          ${pkgs.acpica-tools}/bin/iasl hwinfo.asl
          echo "✅ Generated ACPI files in $HWINFO_DIR"
        else
          echo "⚠️  iasl not available, only ASL file generated"
        fi
        
        # Set permissions if possible
        chmod 644 "$HWINFO_DIR"/* 2>/dev/null || true
        
        echo "🎉 Hardware info generation complete!"
        echo "📁 Files created:"
        ls -la "$HWINFO_DIR/"
      '';

      # Show current hardware info (standalone version for development)
      acpi-hwinfo-show = pkgs.writeShellScriptBin "acpi-hwinfo-show" ''
        #!/bin/bash
        
        # Check multiple possible locations
        HWINFO_DIRS=("/var/lib/acpi-hwinfo" "./acpi-hwinfo")
        HWINFO_DIR=""
        
        for dir in "''${HWINFO_DIRS[@]}"; do
          if [ -d "$dir" ] && [ -f "$dir/hwinfo.json" ]; then
            HWINFO_DIR="$dir"
            break
          fi
        done
        
        if [ -z "$HWINFO_DIR" ]; then
          echo "❌ No hardware info found in any of these locations:"
          for dir in "''${HWINFO_DIRS[@]}"; do
            echo "   $dir"
          done
          echo "💡 Run 'acpi-hwinfo-generate' first to create hardware info"
          exit 1
        fi
        
        echo "📊 Current hardware info from $HWINFO_DIR:"
        echo
        ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
        echo
        echo "📁 Available files:"
        ls -la "$HWINFO_DIR/"
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
        cd - > /dev/null
        
        echo "✅ Test hardware info created in $OUTPUT_DIR"
        echo "📋 Files:"
        ls -la "$OUTPUT_DIR/"
      '';

      # Default package points to the QEMU launcher
      default = self'.packages.qemu-with-hwinfo;
    };
  };
}
