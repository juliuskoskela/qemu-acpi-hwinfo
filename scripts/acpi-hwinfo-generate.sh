#!/bin/bash
set -euo pipefail

HWINFO_DIR="/var/lib/acpi-hwinfo"

# Check if we can write to the system directory
if [ ! -w "$(dirname "$HWINFO_DIR")" ] 2>/dev/null; then
  echo "⚠️  Cannot write to $HWINFO_DIR, using local directory instead"
  HWINFO_DIR="./acpi-hwinfo"
fi

echo "🔧 Generating ACPI hardware info in $HWINFO_DIR..."
mkdir -p "$HWINFO_DIR"

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

echo "📊 Detected hardware:"
echo "   NVMe Serial: $NVME_SERIAL"
echo "   MAC Address: $MAC_ADDRESS"

# Generate JSON file
cat >"$HWINFO_DIR/hwinfo.json" <<EOF
{
  "nvme_serial": "$NVME_SERIAL",
  "mac_address": "$MAC_ADDRESS",
  "generated": "$(date -Iseconds)"
}
EOF

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
if command -v iasl >/dev/null 2>&1; then
  cd "$HWINFO_DIR"
  iasl hwinfo.asl >/dev/null 2>&1
  cd - >/dev/null
else
  echo "❌ Error: iasl (ACPI compiler) not found"
  exit 1
fi

echo "✅ Generated ACPI files in $HWINFO_DIR"
echo "🎉 Hardware info generation complete!"
echo "📁 Files created:"
ls -la "$HWINFO_DIR"
