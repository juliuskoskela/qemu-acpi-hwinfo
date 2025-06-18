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
    # MicroVM integration
    (mkIf cfg.enableMicrovm {
      microvm.qemu.extraArgs = mkIf (cfg.hostHwinfoPath != "") [
        "-acpitable" "file=${cfg.hostHwinfoPath}"
      ];
    })

    # Common configuration
    {

      # Guest tools for reading hardware info
      environment.systemPackages = mkIf cfg.guestTools ([
        # Tool to read hardware info from ACPI tables
        (pkgs.writeShellScriptBin "read-hwinfo" ''
          #!/bin/bash
        
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
  ]);
}
