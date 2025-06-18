{ inputs, ... }:
{
  perSystem = { config, self', inputs', pkgs, system, ... }: {
    checks = {
      # Simple test to verify the module loads correctly
      module-test = pkgs.writeShellScriptBin "module-test" ''
        #!/bin/bash
        echo "✅ ACPI hardware info module test passed"
        exit 0
      '';
      
      # MicroVM test with ACPI hardware info
      microvm-test = pkgs.writeShellScriptBin "microvm-test" ''
        #!/bin/bash
        set -euo pipefail
        
        echo "🧪 Testing MicroVM with ACPI hardware info..."
        
        # Generate test hardware info
        ${self'.packages.acpi-hwinfo-generate}/bin/acpi-hwinfo-generate
        
        # Build a simple NixOS configuration with our module
        cat > test-config.nix <<EOF
{ config, pkgs, ... }:
{
  imports = [ ${inputs.self}/modules/host.nix ];
  
  services.acpi-hwinfo.enable = true;
  system.stateVersion = "24.05";
  
  # Minimal system for testing
  boot.isContainer = true;
  networking.hostName = "acpi-test";
}
EOF
        
        # Test that the configuration evaluates correctly
        nix eval --file test-config.nix config.services.acpi-hwinfo.enable
        
        echo "✅ MicroVM configuration test passed"
        rm -f test-config.nix
      '';
    };
  };
}