#!/bin/bash

HWINFO_DIRS=("/var/lib/acpi-hwinfo" "./acpi-hwinfo")

echo "🔍 ACPI Hardware Info Status"
echo "=========================="
echo

found_any=false
for HWINFO_DIR in "${HWINFO_DIRS[@]}"; do
  if [ -d "$HWINFO_DIR" ]; then
    found_any=true
    echo "📁 Directory: $HWINFO_DIR"
    echo "📋 Contents:"
    ls -la "$HWINFO_DIR/" 2>/dev/null || echo "   (empty or no access)"
    echo

    if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
      echo "📄 Hardware Info:"
      if command -v jq >/dev/null 2>&1; then
        jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
      else
        cat "$HWINFO_DIR/hwinfo.json"
      fi
    else
      echo "❌ No hwinfo.json found in $HWINFO_DIR"
    fi

    echo
    if [ -f "$HWINFO_DIR/hwinfo.aml" ]; then
      echo "✅ ACPI table ready: $HWINFO_DIR/hwinfo.aml"
    else
      echo "❌ No hwinfo.aml found in $HWINFO_DIR"
    fi
    echo
  fi
done

if [ "$found_any" = false ]; then
  echo "❌ Hardware info directory not found in any of these locations:"
  for dir in "${HWINFO_DIRS[@]}"; do
    echo "   $dir"
  done
  echo "💡 Run 'acpi-hwinfo-generate' to create hardware info"
fi

echo
echo "🛠️  Available commands:"
echo "   acpi-hwinfo-generate  - Generate hardware info"
echo "   acpi-hwinfo-show      - Show current hardware info"
echo "   qemu-with-hwinfo      - Start QEMU with hardware info"
