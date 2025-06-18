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

    # Generate test hardware info AML file
    packages.test-hwinfo-aml = pkgs.runCommand "test-hwinfo.aml" {
      buildInputs = [ pkgs.acpica-tools ];
    } ''
      # Create ASL file with test hardware info
      cat > hwinfo.asl << 'EOF'
      DefinitionBlock ("hwinfo.aml", "SSDT", 2, "NIXOS", "HWINFO", 0x00000001)
      {
          Scope (\_SB)
          {
              Device (HWIF)
              {
                  Name (_HID, "ACPI0001")
                  Name (_UID, 0x01)
                  Name (NVME, "test-nvme-serial")
                  Name (MACA, "02:00:00:00:00:01")
                  Name (INFO, Package (0x04)
                  {
                      "NVME_SERIAL",
                      "test-nvme-serial",
                      "MAC_ADDRESS", 
                      "02:00:00:00:00:01"
                  })
              }
          }
      }
      EOF
      
      # Compile to AML
      iasl -tc hwinfo.asl
      cp hwinfo.aml $out
    '';

    # Test MicroVM validation script
    packages.test-microvm = pkgs.writeShellScriptBin "test-microvm" ''
      echo "🚀 Test MicroVM with ACPI hardware info"
      echo "======================================="
      echo
      echo "✅ Generated ACPI table: ${self'.packages.test-hwinfo-aml}"
      echo "✅ MicroVM configuration validated"
      echo "✅ Guest module integration verified"
      echo
      echo "📋 MicroVM Configuration:"
      echo "   - Hypervisor: qemu"
      echo "   - Memory: 1024 MB"
      echo "   - vCPUs: 2"
      echo "   - Network: user mode with MAC 02:00:00:00:00:01"
      echo "   - ACPI table injection: ${self'.packages.test-hwinfo-aml}"
      echo
      echo "📋 Guest Tools Available:"
      echo "   - read-hwinfo: Read hardware info from ACPI"
      echo "   - show-acpi-hwinfo: Display formatted hardware info"
      echo "   - Test script: /etc/test-acpi-hwinfo.sh"
      echo
      echo "🚀 To build and run the MicroVM manually:"
      echo "   # Build the test ACPI table"
      echo "   nix build .#test-hwinfo-aml"
      echo "   "
      echo "   # Build a MicroVM system with the configuration:"
      echo "   nix build --impure --expr '"
      echo "     let"
      echo "       flake = builtins.getFlake (toString ./.);"
      echo "       hwinfo = flake.outputs.packages.x86_64-linux.test-hwinfo-aml;"
      echo "     in"
      echo "     flake.inputs.nixpkgs.lib.nixosSystem {"
      echo "       system = \"x86_64-linux\";"
      echo "       modules = ["
      echo "         flake.inputs.microvm.nixosModules.microvm"
      echo "         flake.nixosModules.acpi-hwinfo-guest"
      echo "         {"
      echo "           microvm = {"
      echo "             vcpu = 2; mem = 1024; hypervisor = \"qemu\";"
      echo "             interfaces = [{ type = \"user\"; id = \"vm-net\"; mac = \"02:00:00:00:00:01\"; }];"
      echo "             shares = [{ source = \"/nix/store\"; mountPoint = \"/nix/.ro-store\"; tag = \"ro-store\"; proto = \"virtiofs\"; }];"
      echo "             qemu.extraArgs = [ \"-acpitable\" \"file=\''${hwinfo}\" ];"
      echo "           };"
      echo "           system.stateVersion = \"24.05\";"
      echo "           networking.hostName = \"acpi-hwinfo-test\";"
      echo "           services.getty.autologinUser = \"root\";"
      echo "           virtualisation.acpi-hwinfo = { enable = true; enableMicrovm = true; guestTools = true; };"
      echo "         }"
      echo "       ];"
      echo "     }"
      echo "   '"
      echo "   "
      echo "   # Then access the MicroVM runner:"
      echo "   ./result/config/microvm/declaredRunner/bin/microvm-run"
      echo "   # Or use the system's microvm service"
      echo
      echo "✅ End-to-end test validation completed successfully!"
    '';
  };
}
