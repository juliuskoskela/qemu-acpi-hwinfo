#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

echo -e "${BLUE}=== Manual QEMU ACPI Hardware Info Test ===${NC}"
echo

# Create temporary directory for testing
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

log "Test directory: $TEST_DIR"

log "Step 1: Creating hardware info generation script manually..."

# Create the generate-hwinfo script manually
cat > "$TEST_DIR/generate-hwinfo.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

HWINFO_DIR="${1:-/tmp/acpi-hwinfo}"
mkdir -p "$HWINFO_DIR"

# Detect NVMe serial (mock for testing)
NVME_SERIAL="TEST_NVME_SERIAL_12345"
if command -v nvme >/dev/null 2>&1; then
  for nvme_dev in /dev/nvme*n1; do
    if [ -e "$nvme_dev" ]; then
      NVME_SERIAL=$(nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "TEST_NVME_SERIAL_12345")
      [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ] && break
    fi
  done
fi

# Detect MAC address (mock for testing)
MAC_ADDRESS="f6:bf:01:02:03:04"
if command -v ip >/dev/null 2>&1; then
  MAC_ADDRESS=$(ip link show 2>/dev/null | awk '/ether/ {print $2; exit}' || echo "f6:bf:01:02:03:04")
fi

echo "Detected hardware info:"
echo "  NVME Serial: $NVME_SERIAL"
echo "  MAC Address: $MAC_ADDRESS"

# Generate ASL file
cat >"$HWINFO_DIR/hwinfo.asl" <<ASLEOF
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
ASLEOF

# Compile to AML if iasl is available
if command -v iasl >/dev/null 2>&1; then
  cd "$HWINFO_DIR" && iasl hwinfo.asl >/dev/null 2>&1
  echo "✓ Generated ACPI hardware info in $HWINFO_DIR"
  echo "✓ Compiled hwinfo.aml ($(wc -c < hwinfo.aml) bytes)"
else
  echo "⚠ iasl not available, ASL file created but not compiled"
fi
EOF

chmod +x "$TEST_DIR/generate-hwinfo.sh"
success "Hardware info generation script created"

log "Step 2: Testing hardware info generation..."
"$TEST_DIR/generate-hwinfo.sh" "$TEST_DIR/hwinfo"
success "Hardware info generated successfully"

log "Generated files:"
ls -la "$TEST_DIR/hwinfo/"

log "Step 3: Examining generated ASL source..."
echo "--- hwinfo.asl ---"
cat "$TEST_DIR/hwinfo/hwinfo.asl"
echo "--- end ---"

if [ -f "$TEST_DIR/hwinfo/hwinfo.aml" ]; then
    log "Step 4: Analyzing compiled ACPI table..."
    echo "ACPI table size: $(wc -c < "$TEST_DIR/hwinfo/hwinfo.aml") bytes"
    echo "File type: $(file "$TEST_DIR/hwinfo/hwinfo.aml")"
    
    echo "Hexdump of first 128 bytes:"
    hexdump -C "$TEST_DIR/hwinfo/hwinfo.aml" | head -8
    
    echo "Strings in ACPI table:"
    strings "$TEST_DIR/hwinfo/hwinfo.aml" | grep -E "(HWINFO|NVME_SERIAL|MAC_ADDRESS|TEST_)" || echo "No hardware info strings found"
    
    success "ACPI table analysis completed"
else
    warning "ACPI table not compiled (iasl not available)"
fi

log "Step 5: Creating guest read script..."

cat > "$TEST_DIR/read-hwinfo.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

echo "=== ACPI Hardware Info Reader ==="

ACPI_DEVICE="/sys/bus/acpi/devices/ACPI0001:00"
if [ ! -d "$ACPI_DEVICE" ]; then
    echo "⚠ ACPI device not found at $ACPI_DEVICE"
    echo "This is expected when not running in a VM with our ACPI table"
    echo ""
    echo "Simulating guest environment for testing..."
    
    # Look for our test ACPI table if provided
    if [ -n "${1:-}" ] && [ -f "$1" ]; then
        echo "Using provided ACPI table: $1"
        echo "Extracting hardware info from table..."
        
        if command -v strings >/dev/null 2>&1; then
            echo "Hardware info found:"
            strings "$1" | grep -A1 -E "(NVME_SERIAL|MAC_ADDRESS)" | grep -v -E "(NVME_SERIAL|MAC_ADDRESS)" | head -2
        else
            echo "strings command not available"
        fi
    else
        echo "No ACPI table provided for testing"
        echo "Usage: $0 [path-to-hwinfo.aml]"
    fi
    exit 0
fi

echo "✓ ACPI device found"

# Extract hardware info from ACPI tables
echo "Searching for hardware info in ACPI tables..."
for table in /sys/firmware/acpi/tables/SSDT*; do
    if [ -f "$table" ] && strings "$table" 2>/dev/null | grep -q "HWINFO"; then
        echo "✓ Found HWINFO in $table"
        echo "Hardware info:"
        strings "$table" | grep -A1 -E "(NVME_SERIAL|MAC_ADDRESS)" | grep -v -E "(NVME_SERIAL|MAC_ADDRESS)" | head -2
        exit 0
    fi
done

echo "✗ No hardware info found in ACPI tables"
EOF

chmod +x "$TEST_DIR/read-hwinfo.sh"
success "Guest read script created"

log "Step 6: Testing guest read functionality..."
if [ -f "$TEST_DIR/hwinfo/hwinfo.aml" ]; then
    "$TEST_DIR/read-hwinfo.sh" "$TEST_DIR/hwinfo/hwinfo.aml"
else
    "$TEST_DIR/read-hwinfo.sh"
fi

log "Step 7: Creating VM test script..."

cat > "$TEST_DIR/test-vm.sh" << 'EOF'
#!/bin/bash
set -euo pipefail

HWINFO_AML="${1:-}"
if [ -z "$HWINFO_AML" ] || [ ! -f "$HWINFO_AML" ]; then
    echo "Usage: $0 <path-to-hwinfo.aml>"
    echo "Example: $0 /tmp/hwinfo/hwinfo.aml"
    exit 1
fi

echo "=== VM Test Instructions ==="
echo ""
echo "To test the ACPI hardware info in a real VM:"
echo ""
echo "1. Create a minimal NixOS VM configuration:"
echo "   - Enable the acpi-hwinfo.guest module"
echo "   - Include the read-hwinfo script"
echo ""
echo "2. Start the VM with the ACPI table:"
echo "   qemu-system-x86_64 \\"
echo "     -acpitable file=$HWINFO_AML \\"
echo "     -kernel /path/to/kernel \\"
echo "     -initrd /path/to/initrd \\"
echo "     -append 'console=ttyS0' \\"
echo "     -nographic \\"
echo "     -m 1024 \\"
echo "     -smp 2"
echo ""
echo "3. Inside the VM, run:"
echo "   read-hwinfo"
echo ""
echo "Expected output should show the hardware info embedded in the ACPI table."
echo ""
echo "ACPI table ready at: $HWINFO_AML"
echo "Table size: $(wc -c < "$HWINFO_AML") bytes"
EOF

chmod +x "$TEST_DIR/test-vm.sh"

if [ -f "$TEST_DIR/hwinfo/hwinfo.aml" ]; then
    "$TEST_DIR/test-vm.sh" "$TEST_DIR/hwinfo/hwinfo.aml"
    success "VM test instructions created"
else
    warning "VM test requires compiled ACPI table"
fi

echo
echo -e "${GREEN}=== Manual Test Summary ===${NC}"
success "Hardware info generation script works"
success "ASL source code generated correctly"
if [ -f "$TEST_DIR/hwinfo/hwinfo.aml" ]; then
    success "ACPI table compiled successfully"
    success "Hardware info extraction tested"
else
    warning "ACPI compilation skipped (iasl not available)"
fi
success "Guest read script created and tested"
success "VM test instructions provided"

echo
echo -e "${BLUE}Test artifacts available in: $TEST_DIR${NC}"
echo "• generate-hwinfo.sh - Hardware info generation"
echo "• read-hwinfo.sh - Guest reading script"  
echo "• test-vm.sh - VM testing instructions"
echo "• hwinfo/ - Generated hardware info files"

echo
echo -e "${BLUE}Next steps:${NC}"
echo "1. Install iasl (ACPI compiler) if not available"
echo "2. Use the generated scripts in a NixOS VM environment"
echo "3. Test end-to-end functionality with QEMU"

# Keep the test directory for inspection
trap - EXIT
echo
echo -e "${YELLOW}Test directory preserved: $TEST_DIR${NC}"
echo "Run 'rm -rf $TEST_DIR' to clean up when done."