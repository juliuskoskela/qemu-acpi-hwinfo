{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      # ACPI hardware info generator - detects hardware and creates ACPI files
      acpi-hwinfo-generate = pkgs.writeShellScriptBin "acpi-hwinfo-generate" ''
        #!/bin/bash
        set -euo pipefail
        
        # Import shared hardware detection functions
        ${inputs.self.lib.hardwareDetectionScript pkgs}
        
        HWINFO_DIR="/var/lib/acpi-hwinfo"
        
        # Check if we can write to the system directory
        if [ ! -w "$(dirname "$HWINFO_DIR")" ] 2>/dev/null; then
          echo "⚠️  Cannot write to $HWINFO_DIR, using local directory instead"
          HWINFO_DIR="./acpi-hwinfo"
        fi
        
        echo "🔧 Generating ACPI hardware info in $HWINFO_DIR..."
        mkdir -p "$HWINFO_DIR"
        
        # Use shared detection functions
        NVME_SERIAL=$(detect_nvme_serial)
        MAC_ADDRESS=$(detect_mac_address)
        
        echo "📊 Detected hardware:"
        echo "   NVMe Serial: $NVME_SERIAL"
        echo "   MAC Address: $MAC_ADDRESS"
        
        # Validate detected hardware info
        if ! validate_hardware_info "$NVME_SERIAL" "$MAC_ADDRESS"; then
          echo "⚠️  Warning: Hardware validation failed, but continuing with detected values"
        fi
        
        # Generate JSON metadata
        cat >"$HWINFO_DIR/hwinfo.json" <<EOF
{
  "nvme_serial": "$NVME_SERIAL",
  "mac_address": "$MAC_ADDRESS",
  "generated": "$(date -Iseconds)"
}
EOF
        
        # Generate ASL file
        cat >"$HWINFO_DIR/hwinfo.asl" <<EOF
DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
{
    Scope (\_SB)
    {
        Device (HWIN)
        {
            Name (_HID, "ACPI0001")
            Name (_UID, 0x00)
            Name (_STR, Unicode ("Hardware Info Device"))
            
            Method (GHWI, 0, NotSerialized)
            {
                Return (Package (0x04)
                {
                    "NVME_SERIAL", 
                    "$NVME_SERIAL", 
                    "MAC_ADDRESS", 
                    "$MAC_ADDRESS"
                })
            }
            
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
        }
    }
}
EOF
        
        # Compile ASL to AML
        echo "🔧 Compiling ASL to AML..."
        if ! (cd "$HWINFO_DIR" && ${pkgs.acpica-tools}/bin/iasl hwinfo.asl >/dev/null 2>&1); then
          echo "❌ Error: Failed to compile ASL file"
          exit 1
        fi
        
        echo "✅ Generated ACPI files in $HWINFO_DIR"
        echo "🎉 Hardware info generation complete!"
        echo "📁 Files created:"
        ls -la "$HWINFO_DIR"
      '';

      # ACPI hardware info display - shows current hardware info
      acpi-hwinfo-show = pkgs.writeShellScriptBin "acpi-hwinfo-show" ''
        #!/bin/bash
        set -euo pipefail
        
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
        if command -v ${pkgs.jq}/bin/jq >/dev/null 2>&1; then
          ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
        else
          cat "$HWINFO_DIR/hwinfo.json"
        fi
        echo
        echo "📁 Available files:"
        ls -la "$HWINFO_DIR/"
      '';

      # Hardware info status checker - shows status of all hardware info locations
      hwinfo-status = pkgs.writeShellScriptBin "hwinfo-status" ''
        #!/bin/bash
        set -euo pipefail
        
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
              if command -v ${pkgs.jq}/bin/jq >/dev/null 2>&1; then
                ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
              else
                cat "$HWINFO_DIR/hwinfo.json"
              fi
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

      # QEMU wrapper with hardware info - starts QEMU with ACPI hardware info loaded
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
        
        # Add additional QEMU options from environment if set
        if [ -n "''${QEMU_OPTS:-}" ]; then
          read -ra EXTRA_OPTS <<< "$QEMU_OPTS"
          QEMU_ARGS+=("''${EXTRA_OPTS[@]}")
        fi
        
        # Add disk if provided as first argument
        if [ $# -gt 0 ] && [ -f "$1" ]; then
          QEMU_ARGS+=(-drive "file=$1,format=qcow2")
          shift
        fi
        
        # Add any additional arguments
        QEMU_ARGS+=("$@")
        
        echo "🔧 QEMU command: ${pkgs.qemu}/bin/qemu-system-x86_64 ''${QEMU_ARGS[*]}"
        exec ${pkgs.qemu}/bin/qemu-system-x86_64 "''${QEMU_ARGS[@]}"
      '';

      # Development utility to create test hardware info
      create-test-hwinfo = pkgs.writeShellScriptBin "create-test-hwinfo" ''
        #!/bin/bash
        set -euo pipefail
        
        # Parse arguments with validation
        NVME_SERIAL="''${1:-test-nvme-serial}"
        MAC_ADDRESS="''${2:-00:11:22:33:44:55}"
        OUTPUT_DIR="''${3:-./test-hwinfo}"
        
        # Validate MAC address format (basic check)
        if [[ ! "$MAC_ADDRESS" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
          echo "❌ Error: Invalid MAC address format: $MAC_ADDRESS"
          echo "   Expected format: XX:XX:XX:XX:XX:XX"
          exit 1
        fi
        
        echo "🧪 Creating test hardware info..."
        echo "   NVMe Serial: $NVME_SERIAL"
        echo "   MAC Address: $MAC_ADDRESS"
        echo "   Output Dir: $OUTPUT_DIR"
        
        # Create output directory
        if ! mkdir -p "$OUTPUT_DIR"; then
          echo "❌ Error: Failed to create output directory: $OUTPUT_DIR"
          exit 1
        fi
        
        # Generate JSON metadata
        cat > "$OUTPUT_DIR/hwinfo.json" <<EOF
{
  "nvme_serial": "$NVME_SERIAL",
  "mac_address": "$MAC_ADDRESS",
  "generated": "$(date -Iseconds)"
}
EOF
        
        # Generate ASL using shared template
        cat > "$OUTPUT_DIR/hwinfo.asl" <<EOF
DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
{
    Scope (\_SB)
    {
        Device (HWIN)
        {
            Name (_HID, "ACPI0001")
            Name (_UID, 0x00)
            Name (_STR, Unicode ("Hardware Info Device"))
            
            Method (GHWI, 0, NotSerialized)
            {
                Return (Package (0x04)
                {
                    "NVME_SERIAL", 
                    "$NVME_SERIAL",
                    "MAC_ADDRESS", 
                    "$MAC_ADDRESS"
                })
            }
            
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
        }
    }
}
EOF
        
        # Compile ASL to AML
        echo "🔧 Compiling ASL to AML..."
        if ! (cd "$OUTPUT_DIR" && ${pkgs.acpica-tools}/bin/iasl hwinfo.asl); then
          echo "❌ Error: Failed to compile ASL file"
          exit 1
        fi
        
        echo "✅ Test hardware info created in $OUTPUT_DIR"
        echo "📋 Generated files:"
        ls -la "$OUTPUT_DIR"
      '';

      # Hardware info derivation - detects actual hardware and generates ACPI files
      hwinfo = pkgs.stdenv.mkDerivation {
        name = "acpi-hwinfo";
        
        nativeBuildInputs = with pkgs; [ acpica-tools ];
        buildInputs = with pkgs; [ nvme-cli util-linux iproute2 ];

        unpackPhase = "true";

        buildPhase = ''
          echo "🔍 Detecting hardware information..."
          
          # Import shared hardware detection functions
          ${inputs.self.lib.hardwareDetectionScript pkgs}
          
          # Use shared detection functions
          NVME_SERIAL=$(detect_nvme_serial)
          MAC_ADDRESS=$(detect_mac_address)
          
          echo "📊 Detected hardware:"
          echo "   NVMe Serial: $NVME_SERIAL"
          echo "   MAC Address: $MAC_ADDRESS"
          
          # Generate JSON metadata
          cat > hwinfo.json <<EOF
{
  "nvme_serial": "$NVME_SERIAL",
  "mac_address": "$MAC_ADDRESS",
  "generated": "$(date -Iseconds)"
}
EOF
          
          # Generate ASL using shared template
          cat > hwinfo.asl <<EOF
DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
{
    Scope (\_SB)
    {
        Device (HWIN)
        {
            Name (_HID, "ACPI0001")
            Name (_UID, 0x00)
            Name (_STR, Unicode ("Hardware Info Device"))
            
            Method (GHWI, 0, NotSerialized)
            {
                Return (Package (0x04)
                {
                    "NVME_SERIAL", 
                    "$NVME_SERIAL",
                    "MAC_ADDRESS", 
                    "$MAC_ADDRESS"
                })
            }
            
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
        }
    }
}
EOF
          
          # Compile ASL to AML
          echo "🔧 Compiling ASL to AML..."
          iasl hwinfo.asl
        '';

        installPhase = ''
          mkdir -p $out
          cp hwinfo.json hwinfo.asl hwinfo.aml $out/
          echo "✅ Hardware info files installed to $out"
        '';
      };
    };
  };
}
