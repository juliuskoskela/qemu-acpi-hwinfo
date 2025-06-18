{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    ./modules/guest.nix
    "${modulesPath}/virtualisation/qemu-vm.nix"
  ];

  # Enable ACPI hardware info
  virtualisation.acpi-hwinfo = {
    enable = true;
    guestTools = true;
  };

  # VM configuration
  virtualisation = {
    memorySize = 1024;
    qemu.options = [
      "-nographic"
      "-smp"
      "2"
    ];
  };

  # System configuration
  system.stateVersion = "24.05";

  # Auto-login for testing
  services.getty.autologinUser = "root";

  # Test packages
  environment.systemPackages = with pkgs; [
    jq
    acpica-tools
    vim
    htop
  ];

  # Create test script
  environment.etc."test-acpi-hwinfo.sh" = {
    text = ''
      #!/bin/bash
      set -euo pipefail
      
      echo "🧪 Testing ACPI hardware info in NixOS VM..."
      echo "============================================"
      
      # Test 1: Check if service is running
      echo "1️⃣  Checking acpi-hwinfo service..."
      if systemctl is-active --quiet acpi-hwinfo; then
        echo "✅ acpi-hwinfo service is running"
      else
        echo "❌ acpi-hwinfo service is not running"
        systemctl status acpi-hwinfo || true
      fi
      
      # Test 2: Check if hardware info file exists
      echo "2️⃣  Checking hardware info file..."
      if [ -f "/var/lib/acpi-hwinfo/hwinfo.json" ]; then
        echo "✅ Hardware info file exists"
        echo "📄 Hardware info content:"
        jq . /var/lib/acpi-hwinfo/hwinfo.json 2>/dev/null || cat /var/lib/acpi-hwinfo/hwinfo.json
      else
        echo "❌ Hardware info file not found"
        ls -la /var/lib/acpi-hwinfo/ || echo "Directory not found"
      fi
      
      # Test 3: Check ACPI device
      echo "3️⃣  Checking ACPI device..."
      if [ -d "/sys/bus/acpi/devices/ACPI0001:00" ]; then
        echo "✅ ACPI device found"
      else
        echo "⚠️  ACPI device not found (may be expected in VM)"
        echo "Available ACPI devices:"
        ls -la /sys/bus/acpi/devices/ 2>/dev/null || echo "No ACPI devices found"
      fi
      
      echo "🎉 NixOS VM test completed!"
      echo "   Press Ctrl+C to exit"
    '';
    mode = "0755";
  };
}
