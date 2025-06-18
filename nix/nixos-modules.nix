{ inputs, ... }:
{
  flake = {
    nixosModules = {
      # Host module for generating and providing hwinfo to VMs
      acpi-hwinfo = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.acpi-hwinfo;
        in {
          options.services.acpi-hwinfo = {
            enable = mkEnableOption "ACPI hardware info for VMs";

            nvmeSerial = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Override NVMe serial number";
            };

            macAddress = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Override MAC address";
            };

            hwinfoPath = mkOption {
              type = types.path;
              readOnly = true;
              description = "Path to the generated hwinfo.aml file";
            };
          };

          config = mkIf cfg.enable {
            services.acpi-hwinfo.hwinfoPath =
              let
                hwinfo = inputs.self.packages.${pkgs.system}.generateHwInfo {
                  nvmeSerial = cfg.nvmeSerial;
                  macAddress = cfg.macAddress;
                };
              in "${hwinfo}/hwinfo.aml";
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

        in {
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