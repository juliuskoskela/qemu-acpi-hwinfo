{ config, lib, pkgs, ... }:

with lib;

{
  options.acpi-hwinfo = {
    guest.enable = mkEnableOption "ACPI hardware info guest support";
  };

  config = mkIf config.acpi-hwinfo.guest.enable {
    # Add read-hwinfo script to system
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "read-hwinfo" ''
        set -euo pipefail
        
        ACPI_DEVICE="/sys/bus/acpi/devices/ACPI0001:00"
        [ ! -d "$ACPI_DEVICE" ] && { echo "ACPI device not found"; exit 1; }
        
        # Extract hardware info from ACPI tables
        for table in /sys/firmware/acpi/tables/SSDT*; do
          if ${pkgs.binutils}/bin/strings "$table" 2>/dev/null | grep -q "HWINFO"; then
            ${pkgs.binutils}/bin/strings "$table" | grep -A1 -E "(NVME_SERIAL|MAC_ADDRESS)" | grep -v -E "(NVME_SERIAL|MAC_ADDRESS)" | head -2
            break
          fi
        done
      '')
    ];
  };
}
