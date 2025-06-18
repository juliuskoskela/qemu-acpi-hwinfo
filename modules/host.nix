{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.acpi-hwinfo;
in
{
  options.services.acpi-hwinfo = {
    enable = mkEnableOption "ACPI hardware info generation service";

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/acpi-hwinfo";
      description = "Directory to store generated hardware info files";
    };

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

    generateOnBoot = mkOption {
      type = types.bool;
      default = true;
      description = "Generate hardware info automatically on system boot";
    };

    user = mkOption {
      type = types.str;
      default = "acpi-hwinfo";
      description = "User to run the service as";
    };

    group = mkOption {
      type = types.str;
      default = "acpi-hwinfo";
      description = "Group to run the service as";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "ACPI hardware info service user";
    };

    users.groups.${cfg.group} = { };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Hardware info generation script
    systemd.services.acpi-hwinfo-generate = {
      description = "Generate ACPI hardware info";
      wantedBy = mkIf cfg.generateOnBoot [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = pkgs.writeShellScript "acpi-hwinfo-generate" ''
          set -euo pipefail
          
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
          
          echo "Detected hardware:"
          echo "  NVMe Serial: $NVME_SERIAL"
          echo "  MAC Address: $MAC_ADDRESS"
          
          # Generate JSON file
          cat > "${cfg.dataDir}/hwinfo.json" <<EOF
          {
            "nvme_serial": "$NVME_SERIAL",
            "mac_address": "$MAC_ADDRESS",
            "generated": "$(date -Iseconds)"
          }
          EOF
          
          # Generate ASL file
          cat > "${cfg.dataDir}/hwinfo.asl" <<EOF
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
          cd "${cfg.dataDir}"
          ${pkgs.acpica-tools}/bin/iasl hwinfo.asl
          
          echo "Hardware info generated successfully in ${cfg.dataDir}"
        '';

        # Allow access to hardware detection tools
        SupplementaryGroups = [ "disk" ];
      };
    };

    # Timer for periodic regeneration (optional)
    systemd.timers.acpi-hwinfo-generate = mkIf cfg.generateOnBoot {
      description = "Regenerate ACPI hardware info daily";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };

    # Install required packages
    environment.systemPackages = with pkgs; [
      acpica-tools
      nvme-cli
      util-linux
    ];

    # Manual generation command
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "acpi-hwinfo-generate" ''
        sudo systemctl start acpi-hwinfo-generate.service
      '')

      (pkgs.writeShellScriptBin "acpi-hwinfo-show" ''
        if [ -f "${cfg.dataDir}/hwinfo.json" ]; then
          echo "📊 Current hardware info:"
          ${pkgs.jq}/bin/jq . "${cfg.dataDir}/hwinfo.json" 2>/dev/null || cat "${cfg.dataDir}/hwinfo.json"
          echo
          echo "📁 Available files:"
          ls -la "${cfg.dataDir}/"
        else
          echo "❌ No hardware info found. Run 'acpi-hwinfo-generate' first."
          exit 1
        fi
      '')
    ];
  };
}
