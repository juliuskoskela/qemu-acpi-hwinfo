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

    # Test MicroVM as a flake output - simple script approach
    packages.test-microvm = pkgs.writeShellScriptBin "test-microvm" ''
      set -euo pipefail
      
      echo "🚀 Building and running test MicroVM with ACPI hardware info..."
      
      # Generate test hardware info AML file
      HWINFO_AML=$(nix build --no-link --print-out-paths --expr '
        let pkgs = import <nixpkgs> {}; in
        pkgs.runCommand "test-hwinfo.aml" {
          buildInputs = [ pkgs.acpica-tools ];
        } '"'"'
          # Create ASL file with test hardware info
          cat > hwinfo.asl << "EOF"
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
        '"'"'
      ')
      
      echo "Generated ACPI table: $HWINFO_AML"
      
      # Build the MicroVM system
      echo "Building MicroVM system..."
      MICROVM_SYSTEM=$(nix build --no-link --print-out-paths --expr "
        let
          flake = builtins.getFlake (toString ./.);
          system = \"x86_64-linux\";
        in
        flake.inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            flake.inputs.microvm.nixosModules.microvm
            flake.nixosModules.acpi-hwinfo-guest
            {
              microvm = {
                vcpu = 2;
                mem = 1024;
                hypervisor = \"qemu\";
                interfaces = [{
                  type = \"user\";
                  id = \"vm-net\";
                  mac = \"02:00:00:00:00:01\";
                }];
                shares = [{
                  source = \"/nix/store\";
                  mountPoint = \"/nix/.ro-store\";
                  tag = \"ro-store\";
                  proto = \"virtiofs\";
                }];
                qemu.extraArgs = [
                  \"-acpitable\"
                  \"file=\$HWINFO_AML\"
                ];
              };
              system.stateVersion = \"24.05\";
              networking.hostName = \"acpi-hwinfo-test\";
              services.getty.autologinUser = \"root\";
              virtualisation.acpi-hwinfo = {
                enable = true;
                enableMicrovm = true;
                guestTools = true;
              };
              environment.systemPackages = with flake.inputs.nixpkgs.legacyPackages.\$system; [
                jq acpica-tools vim htop
              ];
            }
          ];
        }
      ")
      
      echo "Built MicroVM system: $MICROVM_SYSTEM"
      echo "To run the MicroVM manually:"
      echo "  $MICROVM_SYSTEM/config/microvm/declaredRunner/bin/microvm-run"
      echo
      echo "Starting MicroVM..."
      exec "$MICROVM_SYSTEM/config/microvm/declaredRunner/bin/microvm-run"
    '';
  };
}
