#!/bin/bash

# hardware-acpi.sh - Generate ACPI table with hardware info

set -e

# Get hardware info
get_nvme_serial() {
    if command -v nvme >/dev/null 2>&1; then
        nvme id-ctrl /dev/nvme0n1 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "UNKNOWN"
    elif [ -f "/sys/class/nvme/nvme0/serial" ]; then
        cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "UNKNOWN"
    else
        echo "UNKNOWN"
    fi
}

get_mac_address() {
    ip link show | grep -E "link/ether" | head -1 | awk '{print $2}' 2>/dev/null || echo "00:00:00:00:00:00"
}

# Allow overrides from environment or command line
NVME_SERIAL=${1:-$(get_nvme_serial)}
MAC_ADDRESS=${2:-$(get_mac_address)}

echo "Detected hardware:"
echo "  NVMe Serial: $NVME_SERIAL"
echo "  MAC Address: $MAC_ADDRESS"

# Create ACPI SSDT table
cat > hwinfo.asl << EOF
/*
 * Hardware Info ACPI Table
 * Generated: $(date)
 */
DefinitionBlock ("hwinfo.aml", "SSDT", 2, "QEMU", "HWINFO", 1)
{
    Scope (\\_SB)
    {
        Device (HWIN)
        {
            Name (_HID, "ACPI0001")
            Name (_UID, 0)
            Name (_STR, Unicode("Hardware Info Device"))
            
            Method (GHWI, 0, NotSerialized)
            {
                Return (Package (0x04) {
                    "NVME_SERIAL", 
                    "$NVME_SERIAL",
                    "MAC_ADDRESS", 
                    "$MAC_ADDRESS"
                })
            }
            
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)  // Device present and enabled
            }
        }
    }
}
EOF

# Compile ACPI table
if command -v iasl >/dev/null 2>&1; then
    echo "Compiling ACPI table..."
    iasl hwinfo.asl
    
    if [ -f hwinfo.aml ]; then
        echo "ACPI table compiled successfully: hwinfo.aml"
        echo ""
        echo "Usage:"
        echo "  qemu-system-x86_64 -acpitable file=hwinfo.aml [other options]"
        echo ""
        
    else
        echo "Error: Failed to compile ACPI table"
        exit 1
    fi
else
    echo "Error: iasl (ACPI compiler) not found"
    exit 1
fi

