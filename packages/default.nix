{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    packages = {
      # Standalone scripts for development and testing
      acpi-hwinfo-generate = pkgs.writeShellScriptBin "acpi-hwinfo-generate" (builtins.readFile ../scripts/acpi-hwinfo-generate.sh);
      acpi-hwinfo-show = pkgs.writeShellScriptBin "acpi-hwinfo-show" (builtins.readFile ../scripts/acpi-hwinfo-show.sh);
      hwinfo-status = pkgs.writeShellScriptBin "hwinfo-status" (builtins.readFile ../scripts/hwinfo-status.sh);
      qemu-with-hwinfo = pkgs.writeShellScriptBin "qemu-with-hwinfo" (builtins.readFile ../scripts/qemu-with-hwinfo.sh);

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
        ls -la "$OUTPUT_DIR"
      '';

      # Legacy hwinfo derivation (for compatibility)
      hwinfo = pkgs.stdenv.mkDerivation {
        name = "acpi-hwinfo";

        buildInputs = with pkgs; [ acpica-tools nvme-cli util-linux jq ];

        unpackPhase = "true";

        buildPhase = ''
          # Detect NVMe serial
          NVME_SERIAL=""
          if command -v nvme >/dev/null 2>&1; then
            # Try nvme id-ctrl method first (more reliable)
            for nvme_dev in /dev/nvme*n1; do
              if [ -e "$nvme_dev" ]; then
                NVME_SERIAL=$(nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "")
                if [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ]; then
                  break
                fi
              fi
            done
            
            # Fallback to nvme list if id-ctrl didn't work
            if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
              NVME_SERIAL=$(nvme list 2>/dev/null | awk 'NR>1 && $2 != "---------------------" {print $2; exit}' || echo "")
            fi
          fi
          
          # Fallback to sysfs
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
          
          echo "Detected hardware:"
          echo "  NVMe Serial: $NVME_SERIAL"
          echo "  MAC Address: $MAC_ADDRESS"
          
          # Generate JSON file
          cat > hwinfo.json <<EOF
          {
            "nvme_serial": "$NVME_SERIAL",
            "mac_address": "$MAC_ADDRESS",
            "generated": "$(date -Iseconds)"
          }
          EOF
          
          # Generate ASL file
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
          iasl hwinfo.asl
        '';

        installPhase = ''
          mkdir -p $out
          cp hwinfo.json hwinfo.asl hwinfo.aml $out/
        '';
      };
    };
  };
}
