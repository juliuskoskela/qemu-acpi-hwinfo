{ config, pkgs, ... }:
{
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
    }];
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
      
      echo "🧪 Testing ACPI hardware info in MicroVM..."
      
      # Check if ACPI hardware info is available
      if [ -f "/var/lib/acpi-hwinfo/hwinfo.json" ]; then
        echo "✅ Hardware info JSON found"
        cat /var/lib/acpi-hwinfo/hwinfo.json | jq .
      else
        echo "❌ Hardware info JSON not found"
        exit 1
      fi
      
      if [ -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
        echo "✅ Hardware info AML found"
        ls -la /var/lib/acpi-hwinfo/hwinfo.aml
      else
        echo "❌ Hardware info AML not found"
        exit 1
      fi
      
      # Test ACPI table access
      if command -v acpidump >/dev/null 2>&1; then
        echo "🔍 Checking ACPI tables..."
        acpidump -t | grep -i hwinfo || echo "⚠️  Custom ACPI table not found in dump"
      fi
      
      echo "✅ MicroVM ACPI hardware info test completed successfully"
    '';
    mode = "0755";
  };

  # Enable ACPI hardware info
  services.acpi-hwinfo.enable = true;
}