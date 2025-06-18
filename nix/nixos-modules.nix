{ inputs, ... }:
{
  flake = {
    nixosModules = {
      # Host module for generating hardware info at runtime
      acpi-hwinfo = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.acpi-hwinfo;
          
          # Script to detect and generate hardware info at runtime
          hwinfo-generator = pkgs.writeShellScript "hwinfo-generator" ''
            set -euo pipefail
            
            HWINFO_DIR="/var/lib/acpi-hwinfo"
            mkdir -p "$HWINFO_DIR"
            
            echo "Detecting hardware information..."
            
            # Detect NVMe serial
            NVME_SERIAL="${cfg.nvmeSerial or ""}"
            if [ -z "$NVME_SERIAL" ]; then
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
            fi
            
            # Detect MAC address
            MAC_ADDRESS="${cfg.macAddress or ""}"
            if [ -z "$MAC_ADDRESS" ]; then
              if command -v ip >/dev/null 2>&1; then
                MAC_ADDRESS=$(ip link show | awk '/ether/ {print $2; exit}' || echo "")
              fi
              if [ -z "$MAC_ADDRESS" ]; then
                MAC_ADDRESS="00:00:00:00:00:00"
              fi
            fi
            
            echo "Using NVMe Serial: $NVME_SERIAL"
            echo "Using MAC Address: $MAC_ADDRESS"
            
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
              iasl hwinfo.asl
              echo "Generated ACPI files in $HWINFO_DIR"
            else
              echo "Warning: iasl not available, only ASL file generated"
            fi
            
            # Set permissions
            chmod 644 "$HWINFO_DIR"/* 2>/dev/null || true
            
            echo "Hardware info generation complete"
          '';
        in
        {
          options.services.acpi-hwinfo = {
            enable = mkEnableOption "ACPI hardware info for VMs";

            nvmeSerial = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Override NVMe serial number (auto-detected if null)";
            };

            macAddress = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Override MAC address (auto-detected if null)";
            };

            generateAtBoot = mkOption {
              type = types.bool;
              default = true;
              description = "Generate hardware info at boot time";
            };

            hwinfoPath = mkOption {
              type = types.str;
              default = "/var/lib/acpi-hwinfo/hwinfo.aml";
              readOnly = true;
              description = "Path to the runtime-generated hwinfo.aml file";
            };
          };

          config = mkIf cfg.enable {
            environment.systemPackages = with pkgs; [
              acpica-tools
              nvme-cli
              
              # Convenience commands
              (writeShellScriptBin "acpi-hwinfo-generate" ''
                echo "Regenerating ACPI hardware info..."
                sudo ${hwinfo-generator}
              '')
              
              (writeShellScriptBin "acpi-hwinfo-show" ''
                HWINFO_DIR="/var/lib/acpi-hwinfo"
                if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
                  echo "Current hardware info:"
                  ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json"
                  echo
                  echo "Files available:"
                  ls -la "$HWINFO_DIR/"
                else
                  echo "No hardware info found. Run 'acpi-hwinfo-generate' first."
                fi
              '')
            ];

            # Create the hardware info directory
            systemd.tmpfiles.rules = [
              "d /var/lib/acpi-hwinfo 0755 root root -"
            ];

            # Systemd service to generate hardware info at boot
            systemd.services.acpi-hwinfo-generator = mkIf cfg.generateAtBoot {
              description = "Generate ACPI hardware info";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${hwinfo-generator}";
                RemainAfterExit = true;
                StandardOutput = "journal";
                StandardError = "journal";
              };
            };
          };
        };

      # Guest module for reading hardware info inside VMs
      guest = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.acpi-hwinfo-guest;

          readHwInfoScript = pkgs.writeShellScriptBin "read-hwinfo" ''
            #!/bin/bash
            echo "🔍 Reading ACPI hardware info from guest VM..."
            echo
            
            # Try to read from ACPI tables
            if [ -d "/sys/firmware/acpi/tables" ]; then
              echo "📋 Searching ACPI SSDT tables..."
              found=false
              
              for table in /sys/firmware/acpi/tables/SSDT*; do
                if [ -f "$table" ]; then
                  hwinfo=$(${pkgs.util-linux}/bin/strings "$table" 2>/dev/null | \
                    ${pkgs.gnugrep}/bin/grep -A 1 -B 1 "NVME_SERIAL\|MAC_ADDRESS" 2>/dev/null)
                  
                  if [ -n "$hwinfo" ]; then
                    echo "✅ Found hardware info in $table:"
                    echo "$hwinfo" | while read -r line; do
                      echo "   $line"
                    done
                    echo
                    found=true
                  fi
                fi
              done
              
              if [ "$found" = false ]; then
                echo "❌ No hardware info found in ACPI SSDT tables"
              fi
            else
              echo "❌ ACPI tables directory not found"
            fi
            
            echo
            echo "💡 This command reads hardware info injected via QEMU ACPI tables"
            echo "💡 The info should match the host machine that generated the hwinfo"
          '';

        in
        {
          options.services.acpi-hwinfo-guest = {
            enable = mkEnableOption "ACPI hardware info reader for guest VMs";
          };

          config = mkIf cfg.enable {
            environment.systemPackages = [ readHwInfoScript ];

            # Create a systemd service to read hwinfo on boot
            systemd.services.acpi-hwinfo-reader = {
              description = "Read ACPI Hardware Info";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${readHwInfoScript}/bin/read-hwinfo";
                RemainAfterExit = true;
              };
            };
          };
        };
    };
  };
}
