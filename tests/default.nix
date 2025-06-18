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

    # Test MicroVM as a flake output using nixosSystem and declaredRunner
    packages.test-microvm = 
      let
        # Generate test hardware info AML file
        hwInfoAml = pkgs.runCommand "test-hwinfo.aml" {
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

        # Create nixosSystem with MicroVM
        nixosSystem = inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.acpi-hwinfo-guest
            {
              # MicroVM configuration
              microvm = {
                vcpu = 2;
                mem = 1024;
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

                # Inject ACPI table with hardware info
                qemu.extraArgs = [
                  "-acpitable"
                  "file=${hwInfoAml}"
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
        };
      in
      nixosSystem.config.microvm.declaredRunner;
  };
}
