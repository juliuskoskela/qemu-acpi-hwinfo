{ config, lib, pkgs, options, ... }:

with lib;

let
  cfg = config.virtualisation.acpi-hwinfo;
in
{
  options.virtualisation.acpi-hwinfo = {
    enable = mkEnableOption "ACPI hardware info support for VMs";

    hostHwinfoPath = mkOption {
      type = types.str;
      default = "/var/lib/acpi-hwinfo/hwinfo.aml";
      description = "Path to the hardware info AML file on the host";
    };

    enableMicrovm = mkOption {
      type = types.bool;
      default = false;
      description = "Enable MicroVM integration with hardware info";
    };

    microvmFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional flags to pass to MicroVM for hardware info integration";
      example = [ "--acpi-table" "/var/lib/acpi-hwinfo/hwinfo.aml" ];
    };

    microvmShares = mkOption {
      type = types.listOf (types.submodule {
        options = {
          source = mkOption {
            type = types.str;
            description = "Host path to share";
          };
          mountPoint = mkOption {
            type = types.str;
            description = "Guest mount point";
          };
          tag = mkOption {
            type = types.str;
            description = "Share tag";
          };
          proto = mkOption {
            type = types.str;
            default = "virtiofs";
            description = "Protocol to use for sharing";
          };
        };
      });
      default = [ ];
      description = "Additional virtiofs shares for hardware info";
      example = [{
        source = "/var/lib/acpi-hwinfo";
        mountPoint = "/var/lib/acpi-hwinfo";
        tag = "hwinfo";
        proto = "virtiofs";
      }];
    };

    enableQemuIntegration = mkOption {
      type = types.bool;
      default = true;
      description = "Enable QEMU integration with hardware info";
    };

    guestTools = mkOption {
      type = types.bool;
      default = true;
      description = "Install guest tools for reading hardware info";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Common configuration for all VM types
    {

      # Guest tools for reading hardware info
      environment.systemPackages = mkIf cfg.guestTools ([
        # Tool to read hardware info from ACPI tables
        (pkgs.writeShellScriptBin "read-hwinfo" ''
          #!/bin/bash
          PATH=${pkgs.binutils}/bin:$PATH
        
          echo "🔍 Reading hardware info from ACPI tables..."
          echo
        
          # Check if ACPI tables are available
          if [ ! -d /sys/firmware/acpi/tables ]; then
            echo "❌ ACPI tables not available"
            exit 1
          fi
        
          # Look for our hardware info in SSDT tables
          found=false
          for ssdt in /sys/firmware/acpi/tables/SSDT*; do
            if [ -f "$ssdt" ]; then
              # Extract strings and look for our hardware info
              hwinfo=$(strings "$ssdt" 2>/dev/null | grep -A 3 -B 1 "NVME_SERIAL\|MAC_ADDRESS" || true)
              if [ -n "$hwinfo" ]; then
                echo "📊 Hardware info found in $(basename "$ssdt"):"
                echo "$hwinfo" | while read -r line; do
                  echo "   $line"
                done
                found=true
                break
              fi
            fi
          done
        
          if [ "$found" = false ]; then
            echo "❌ Hardware info not found in ACPI tables"
            echo "💡 Make sure the VM was started with hardware info ACPI table"
            exit 1
          fi
        '')

        # Tool to show ACPI device info
        (pkgs.writeShellScriptBin "show-acpi-hwinfo" ''
          #!/bin/bash
        
          echo "🔍 ACPI Hardware Info Device Status"
          echo "=================================="
          echo
        
          # Check for ACPI devices
          if [ -d /sys/bus/acpi/devices ]; then
            echo "📱 ACPI devices:"
            for device in /sys/bus/acpi/devices/*; do
              if [ -d "$device" ]; then
                device_name=$(basename "$device")
                hid=""
                if [ -f "$device/hid" ]; then
                  hid=$(cat "$device/hid" 2>/dev/null || echo "unknown")
                fi
                echo "   $device_name (HID: $hid)"
              
                # Check if this is our hardware info device
                if [ "$hid" = "ACPI0001" ]; then
                  echo "   ✅ Hardware info device found!"
                  if [ -f "$device/path" ]; then
                    echo "   📍 Path: $(cat "$device/path" 2>/dev/null || echo "unknown")"
                  fi
                fi
              fi
            done
          else
            echo "❌ No ACPI devices found"
          fi
        
          echo
          echo "📋 ACPI tables:"
          if [ -d /sys/firmware/acpi/tables ]; then
            ls -la /sys/firmware/acpi/tables/ | grep -E "(SSDT|DSDT)" || echo "   No SSDT/DSDT tables found"
          else
            echo "   ACPI tables directory not available"
          fi
        '')

        # Tool to extract hardware info as JSON
        (pkgs.writeShellScriptBin "extract-hwinfo-json" ''
          #!/bin/bash
        
          echo "🔍 Extracting hardware info as JSON..."
        
          # Try to find hardware info in ACPI tables
          nvme_serial=""
          mac_address=""
        
          for ssdt in /sys/firmware/acpi/tables/SSDT*; do
            if [ -f "$ssdt" ]; then
              strings_output=$(strings "$ssdt" 2>/dev/null || true)
            
              # Look for NVME_SERIAL followed by the actual serial
              if echo "$strings_output" | grep -q "NVME_SERIAL"; then
                nvme_serial=$(echo "$strings_output" | grep -A 1 "NVME_SERIAL" | tail -1 | grep -v "NVME_SERIAL" || true)
              fi
            
              # Look for MAC_ADDRESS followed by the actual address
              if echo "$strings_output" | grep -q "MAC_ADDRESS"; then
                mac_address=$(echo "$strings_output" | grep -A 1 "MAC_ADDRESS" | tail -1 | grep -v "MAC_ADDRESS" || true)
              fi
            
              if [ -n "$nvme_serial" ] && [ -n "$mac_address" ]; then
                break
              fi
            fi
          done
        
          if [ -n "$nvme_serial" ] || [ -n "$mac_address" ]; then
            echo "{"
            echo "  \"source\": \"acpi-tables\","
            echo "  \"extracted\": \"$(date -Iseconds)\","
            if [ -n "$nvme_serial" ]; then
              echo "  \"nvme_serial\": \"$nvme_serial\","
            fi
            if [ -n "$mac_address" ]; then
              echo "  \"mac_address\": \"$mac_address\""
            fi
            echo "}"
          else
            echo "❌ No hardware info found in ACPI tables"
            exit 1
          fi
        '')
      ] ++ (with pkgs; [
        acpica-tools
        pciutils
        usbutils
      ]));
    }

    # MicroVM-specific configuration
    (mkIf cfg.enableMicrovm {
      # Ensure hardware info directory is available
      systemd.tmpfiles.rules = [
        "d /var/lib/acpi-hwinfo 0755 root root -"
      ];

      # Configure MicroVM shares for hardware info
      microvm.shares = mkMerge [
        # User-specified shares
        (mkIf (cfg.microvmShares != [ ]) cfg.microvmShares)

        # Default hardware info share if not already configured
        (mkIf (cfg.microvmShares == [ ] && config ? microvm) [{
          source = "/var/lib/acpi-hwinfo";
          mountPoint = "/var/lib/acpi-hwinfo";
          tag = "hwinfo";
          proto = "virtiofs";
        }])
      ];

      # Environment variable for MicroVM flags
      environment.variables.MICROVM_ACPI_FLAGS = mkIf (cfg.microvmFlags != [ ])
        (lib.concatStringsSep " " cfg.microvmFlags);

      # MicroVM service to validate ACPI hardware info
      systemd.services.microvm-acpi-hwinfo = {
        description = "MicroVM ACPI Hardware Info Validation";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeScript "validate-microvm-acpi" ''
            #!/bin/bash
            set -euo pipefail
            
            echo "🔍 Validating MicroVM ACPI hardware info..."
            
            # Show configured flags if any
            if [ -n "''${MICROVM_ACPI_FLAGS:-}" ]; then
              echo "🔧 MicroVM ACPI flags: $MICROVM_ACPI_FLAGS"
            fi
            
            # Check if hardware info is available via virtiofs share
            if [ -f "/var/lib/acpi-hwinfo/hwinfo.json" ]; then
              echo "✅ Hardware info JSON available via virtiofs"
              ${pkgs.jq}/bin/jq . /var/lib/acpi-hwinfo/hwinfo.json
            else
              echo "⚠️  Hardware info JSON not found via virtiofs"
            fi
            
            # Check if ACPI table was injected
            if [ -d "/sys/firmware/acpi/tables" ]; then
              echo "🔍 Checking for injected ACPI tables..."
              if ls /sys/firmware/acpi/tables/SSDT* >/dev/null 2>&1; then
                echo "✅ SSDT tables found"
                for ssdt in /sys/firmware/acpi/tables/SSDT*; do
                  if ${pkgs.binutils}/bin/strings "$ssdt" 2>/dev/null | grep -q "NVME_SERIAL\|MAC_ADDRESS"; then
                    echo "✅ Hardware info found in ACPI table: $(basename "$ssdt")"
                    break
                  fi
                done
              else
                echo "⚠️  No SSDT tables found"
              fi
            else
              echo "⚠️  ACPI tables directory not available"
            fi
            
            echo "✅ MicroVM ACPI hardware info validation completed"
          '';
        };
      };

      # Helper script for MicroVM with hardware info
      environment.systemPackages = mkIf cfg.guestTools [
        (pkgs.writeShellScriptBin "microvm-hwinfo-helper" ''
          #!/bin/bash
          
          echo "🔧 MicroVM Hardware Info Helper"
          echo "==============================="
          echo
          
          # Show current configuration
          echo "📋 Configuration:"
          echo "   Host hwinfo path: ${cfg.hostHwinfoPath}"
          echo "   MicroVM integration: ${if cfg.enableMicrovm then "enabled" else "disabled"}"
          if [ -n "''${MICROVM_ACPI_FLAGS:-}" ]; then
            echo "   ACPI flags: $MICROVM_ACPI_FLAGS"
          fi
          echo
          
          # Show available commands
          echo "📋 Available commands:"
          echo "   read-hwinfo           - Read hardware info from ACPI tables"
          echo "   show-acpi-hwinfo      - Show ACPI device status"
          echo "   extract-hwinfo-json   - Extract hardware info as JSON"
          echo
          
          # Show mount points
          echo "📁 Mount points:"
          if [ -d "/var/lib/acpi-hwinfo" ]; then
            echo "   /var/lib/acpi-hwinfo: $(ls -la /var/lib/acpi-hwinfo 2>/dev/null | wc -l) files"
          else
            echo "   /var/lib/acpi-hwinfo: not mounted"
          fi
        '')
      ];
    })

    # QEMU-specific configuration
    (mkIf cfg.enableQemuIntegration {
      # QEMU-specific ACPI handling can be added here
      # Currently handled by the QEMU launch scripts
    })
  ]);
}
