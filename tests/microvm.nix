{ config, pkgs, ... }:
{
  imports = [
    ../modules/guest.nix
  ];

  # MicroVM configuration for testing
  microvm = {
    vcpu = 2;
    mem = 2048;
    hypervisor = "qemu";

    # Network configuration
    interfaces = [{
      type = "user";
      id = "vm-net";
      mac = "02:00:00:00:00:01";
    }];

    # Share the Nix store
    shares = [{
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
      tag = "ro-store";
      proto = "virtiofs";
    }] ++ (
      # Share hardware info directory if it exists
      if builtins.pathExists "/var/lib/acpi-hwinfo" then [{
        source = "/var/lib/acpi-hwinfo";
        mountPoint = "/var/lib/acpi-hwinfo";
        tag = "acpi-hwinfo";
        proto = "virtiofs";
      }] else [ ]
    );

    # QEMU options for ACPI table injection
    qemu.extraArgs = [
      # Inject custom ACPI table if available
    ] ++ (
      if builtins.pathExists "/var/lib/acpi-hwinfo/hwinfo.aml" then [
        "-acpitable"
        "file=/var/lib/acpi-hwinfo/hwinfo.aml"
      ] else [ ]
    );
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

  # Create comprehensive test script
  environment.etc."test-acpi-hwinfo.sh" = {
    text = ''
      #!/bin/bash
      set -euo pipefail
      
      echo "🧪 Testing ACPI hardware info in MicroVM..."
      echo "=========================================="
      
      # Test 1: Check validation service
      echo "1️⃣  Checking MicroVM ACPI validation service..."
      if systemctl is-active --quiet microvm-acpi-hwinfo; then
        echo "✅ MicroVM ACPI validation service is active"
        systemctl status microvm-acpi-hwinfo --no-pager
      else
        echo "❌ MicroVM ACPI validation service is not active"
        systemctl status microvm-acpi-hwinfo --no-pager || true
      fi
      
      echo
      echo "2️⃣  Running guest tools..."
      
      # Test read-hwinfo command
      echo "📖 Testing read-hwinfo command:"
      if command -v read-hwinfo >/dev/null 2>&1; then
        read-hwinfo || echo "⚠️  read-hwinfo failed"
      else
        echo "❌ read-hwinfo command not found"
      fi
      
      echo
      echo "📊 Testing show-acpi-hwinfo command:"
      if command -v show-acpi-hwinfo >/dev/null 2>&1; then
        show-acpi-hwinfo
      else
        echo "❌ show-acpi-hwinfo command not found"
      fi
      
      echo
      echo "📄 Testing extract-hwinfo-json command:"
      if command -v extract-hwinfo-json >/dev/null 2>&1; then
        extract-hwinfo-json || echo "⚠️  extract-hwinfo-json failed"
      else
        echo "❌ extract-hwinfo-json command not found"
      fi
      
      echo
      echo "3️⃣  Checking virtiofs shared hardware info..."
      if [ -f "/var/lib/acpi-hwinfo/hwinfo.json" ]; then
        echo "✅ Hardware info JSON found via virtiofs"
        cat /var/lib/acpi-hwinfo/hwinfo.json | jq .
      else
        echo "⚠️  Hardware info JSON not found via virtiofs"
      fi
      
      if [ -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
        echo "✅ Hardware info AML found via virtiofs"
        ls -la /var/lib/acpi-hwinfo/hwinfo.aml
      else
        echo "⚠️  Hardware info AML not found via virtiofs"
      fi
      
      echo
      echo "✅ MicroVM ACPI hardware info test completed"
    '';
    mode = "0755";
  };

  # Enable ACPI hardware info guest support
  virtualisation.acpi-hwinfo = {
    enable = true;
    enableMicrovm = true;
    guestTools = true;
  };

  # Enable host ACPI hardware info service
  services.acpi-hwinfo.enable = true;
}
