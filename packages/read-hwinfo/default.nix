{ pkgs }:

pkgs.writeShellScriptBin "read-hwinfo" ''
  export PATH="${pkgs.lib.makeBinPath (with pkgs; [ binutils coreutils ])}:$PATH"
  set -euo pipefail
  
  ACPI_DEVICE="/sys/bus/acpi/devices/ACPI0001:00"
  [ ! -d "$ACPI_DEVICE" ] && { echo "ACPI device not found"; exit 1; }
  
  # Extract hardware info from ACPI tables
  for table in /sys/firmware/acpi/tables/SSDT*; do
    if strings "$table" 2>/dev/null | grep -q "HWINFO"; then
      strings "$table" | grep -A1 -E "(NVME_SERIAL|MAC_ADDRESS)" | grep -v -E "(NVME_SERIAL|MAC_ADDRESS)" | head -2
      break
    fi
  done
''