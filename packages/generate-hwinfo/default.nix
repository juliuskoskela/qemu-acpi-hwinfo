{ pkgs }:

pkgs.writeShellScriptBin "generate-hwinfo" ''
  export PATH="${pkgs.lib.makeBinPath (with pkgs; [ nvme-cli iproute2 acpica-tools coreutils ])}:$PATH"
  set -euo pipefail
  
  HWINFO_DIR="''${1:-/var/lib/acpi-hwinfo}"
  mkdir -p "$HWINFO_DIR"
  
  # Detect NVMe serial with multiple fallback methods
  NVME_SERIAL=""
  if command -v nvme >/dev/null 2>&1; then
    # Method 1: nvme id-ctrl (most reliable)
    for nvme_dev in /dev/nvme*n1; do
      if [ -e "$nvme_dev" ]; then
        NVME_SERIAL=$(nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "")
        if [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ]; then
          break
        fi
      fi
    done
    
    # Method 2: nvme list fallback (column 3 is the serial number)
    if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
      NVME_SERIAL=$(nvme list 2>/dev/null | awk 'NR>1 && !/^-+/ && $3 != "" {print $3; exit}' || echo "")
    fi
  fi
  if [ -z "$NVME_SERIAL" ] && [ -f /sys/class/nvme/nvme0/serial ]; then
    NVME_SERIAL=$(cat /sys/class/nvme/nvme0/serial 2>/dev/null | tr -d ' \n' || echo "")
  fi
  # Try alternative paths
  if [ -z "$NVME_SERIAL" ]; then
    for nvme_dev in /sys/class/nvme/nvme*/serial; do
      if [ -f "$nvme_dev" ]; then
        NVME_SERIAL=$(cat "$nvme_dev" 2>/dev/null | tr -d ' \n' || echo "")
        [ -n "$NVME_SERIAL" ] && break
      fi
    done
  fi
  # Try lsblk method
  if [ -z "$NVME_SERIAL" ] && command -v lsblk >/dev/null 2>&1; then
    NVME_SERIAL=$(lsblk -d -o NAME,SERIAL | grep nvme | awk '{print $2; exit}' || echo "")
  fi
  # Clean up the serial - if it's just dashes or empty, treat as not detected
  if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ] || echo "$NVME_SERIAL" | grep -q '^-*$'; then
    NVME_SERIAL="no-nvme-detected"
  fi
  
  # Detect MAC address
  MAC_ADDRESS=$(ip link show 2>/dev/null | awk '/ether/ {print $2; exit}' || echo "00:00:00:00:00:00")
  
  # Generate ASL file
  cat >"$HWINFO_DIR/hwinfo.asl" <<EOF
  DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
  {
      Scope (\_SB)
      {
          Device (HWIN)
          {
              Name (_HID, "ACPI0001")
              Name (_UID, 0x00)
              Method (GHWI, 0, NotSerialized)
              {
                  Return (Package (0x04)
                  {
                      "NVME_SERIAL", "$NVME_SERIAL", 
                      "MAC_ADDRESS", "$MAC_ADDRESS"
                  })
              }
              Method (_STA, 0, NotSerialized) { Return (0x0F) }
          }
      }
  }
  EOF
  
  # Compile to AML
  cd "$HWINFO_DIR" && iasl hwinfo.asl >/dev/null 2>&1
  echo "Generated ACPI hardware info in $HWINFO_DIR"
''