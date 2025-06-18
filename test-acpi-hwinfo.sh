#!/bin/bash
set -e
echo Testing ACPI hardware info inside VM

if command -v show-acpi-hwinfo >/dev/null 2>&1; then
  echo show-acpi-hwinfo command available
else
  echo show-acpi-hwinfo command not found
  exit 1
fi

if command -v read-hwinfo >/dev/null 2>&1; then
  echo read-hwinfo command available
else
  echo read-hwinfo command not found
  exit 1
fi

ACPI_DEVICES=$(show-acpi-hwinfo 2>/dev/null | wc -l)
if [ "$ACPI_DEVICES" -gt 0 ]; then
  echo Found $ACPI_DEVICES ACPI devices
  show-acpi-hwinfo | head -10
else
  echo No ACPI devices found
  exit 1
fi

if read-hwinfo; then
  echo Hardware info read successfully
else
  echo Hardware info not available
fi

echo All VM tests completed successfully