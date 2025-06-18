{ self, nixpkgs, microvm, ... }:

{
  system = "x86_64-linux";
  modules = [
    microvm.nixosModules.microvm
    self.nixosModules.acpi-hwinfo-guest
    {
      # MicroVM configuration
      microvm = {
        vcpu = 2;
        mem = 1024;
        hypervisor = "qemu";
        
        # Network interface
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

        # Inject ACPI table with hardware info
        qemu.extraArgs = [
          "-acpitable"
          "file=${self.packages.x86_64-linux.hwinfo-aml}"
        ];
      };

      # System configuration
      system.stateVersion = "24.05";
      networking.hostName = "acpi-hwinfo-test";
      services.getty.autologinUser = "root";

      # Enable ACPI hardware info guest support
      virtualisation.acpi-hwinfo = {
        enable = true;
        enableMicrovm = true;
        guestTools = true;
      };

      # Test packages
      environment.systemPackages = with nixpkgs.legacyPackages.x86_64-linux; [
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
          echo "=========================================="
          
          # Test guest tools
          echo "📖 Testing read-hwinfo command:"
          if command -v read-hwinfo >/dev/null 2>&1; then
            read-hwinfo || echo "⚠️  read-hwinfo failed"
          else
            echo "❌ read-hwinfo command not found"
          fi
          
          echo "📊 Testing show-acpi-hwinfo command:"
          if command -v show-acpi-hwinfo >/dev/null 2>&1; then
            show-acpi-hwinfo
          else
            echo "❌ show-acpi-hwinfo command not found"
          fi
          
          echo "✅ MicroVM ACPI hardware info test completed"
        '';
        mode = "0755";
      };
    }
  ];
}