{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      # Standalone scripts for development and testing
      acpi-hwinfo-generate = pkgs.writeShellScriptBin "acpi-hwinfo-generate" (builtins.readFile ../scripts/acpi-hwinfo-generate.sh);
      acpi-hwinfo-show = pkgs.writeShellScriptBin "acpi-hwinfo-show" (builtins.readFile ../scripts/acpi-hwinfo-show.sh);
      hwinfo-status = pkgs.writeShellScriptBin "hwinfo-status" (builtins.readFile ../scripts/hwinfo-status.sh);
      qemu-with-hwinfo = pkgs.writeShellScriptBin "qemu-with-hwinfo" (builtins.readFile ../scripts/qemu-with-hwinfo.sh);

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
        
        # Generate ASL using template
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
          
          # Detect NVMe serial with multiple fallback methods
          NVME_SERIAL=""
          
          # Method 1: nvme id-ctrl (most reliable)
          if command -v nvme >/dev/null 2>&1; then
            for nvme_dev in /dev/nvme*n1; do
              if [ -e "$nvme_dev" ]; then
                NVME_SERIAL=$(nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "")
                if [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ]; then
                  break
                fi
              fi
            done
            
            # Method 2: nvme list fallback
            if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
              NVME_SERIAL=$(nvme list 2>/dev/null | awk 'NR>1 && $2 != "---------------------" {print $2; exit}' || echo "")
            fi
          fi
          
          # Method 3: sysfs fallback
          if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
            if [ -f /sys/class/nvme/nvme0/serial ]; then
              NVME_SERIAL=$(cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "")
            fi
          fi
          
          # Final fallback
          if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
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
          
          # Generate JSON metadata
          cat > hwinfo.json <<EOF
{
  "nvme_serial": "$NVME_SERIAL",
  "mac_address": "$MAC_ADDRESS",
  "generated": "$(date -Iseconds)"
}
EOF
          
          # Generate ASL using template
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
