{ config, lib, pkgs, inputs, ... }:

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
          
                    # Import shared hardware detection functions
                    ${inputs.self.lib.hardwareDetectionScript pkgs}
          
                    # Detect NVMe serial
                    NVME_SERIAL="${cfg.nvmeSerial or ""}"
                    if [ -z "$NVME_SERIAL" ]; then
                      NVME_SERIAL=$(detect_nvme_serial)
                    fi
          
                    # Detect MAC address
                    MAC_ADDRESS="${cfg.macAddress or ""}"
                    if [ -z "$MAC_ADDRESS" ]; then
                      MAC_ADDRESS=$(detect_mac_address)
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
          
                    # Generate ASL file using shared template
                    cat > "${cfg.dataDir}/hwinfo.asl" <<EOF
          ${inputs.self.lib.generateAcpiTemplate { nvmeSerial = "$NVME_SERIAL"; macAddress = "$MAC_ADDRESS"; }}
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

    # Install required packages and management commands
    environment.systemPackages = with pkgs; [
      # Required tools for hardware detection and ACPI compilation
      acpica-tools
      nvme-cli
      util-linux
      jq

      # Management commands
      (writeShellScriptBin "acpi-hwinfo-generate" ''
        sudo systemctl start acpi-hwinfo-generate.service
      '')

      (writeShellScriptBin "acpi-hwinfo-show" ''
        if [ -f "${cfg.dataDir}/hwinfo.json" ]; then
          echo "📊 Current hardware info:"
          ${jq}/bin/jq . "${cfg.dataDir}/hwinfo.json" 2>/dev/null || cat "${cfg.dataDir}/hwinfo.json"
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
