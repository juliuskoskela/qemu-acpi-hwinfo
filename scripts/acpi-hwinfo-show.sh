#!/bin/bash

# Check multiple possible locations
HWINFO_DIRS=("/var/lib/acpi-hwinfo" "./acpi-hwinfo")
HWINFO_DIR=""

for dir in "${HWINFO_DIRS[@]}"; do
  if [ -d "$dir" ] && [ -f "$dir/hwinfo.json" ]; then
    HWINFO_DIR="$dir"
    break
  fi
done

if [ -z "$HWINFO_DIR" ]; then
  echo "❌ No hardware info found in any of these locations:"
  for dir in "${HWINFO_DIRS[@]}"; do
    echo "   $dir"
  done
  echo "💡 Run 'acpi-hwinfo-generate' first to create hardware info"
  exit 1
fi

echo "📊 Current hardware info from $HWINFO_DIR:"
echo
if command -v jq >/dev/null 2>&1; then
  jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
else
  cat "$HWINFO_DIR/hwinfo.json"
fi
echo
echo "📁 Available files:"
ls -la "$HWINFO_DIR/"
