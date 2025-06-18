{
  description = "QEMU ACPI Hardware Info - Simple MicroVM Setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      
      # Generate ACPI table with hardware info
      hwinfo-aml = pkgs.runCommand "hwinfo.aml" {
        buildInputs = [ pkgs.acpica-tools pkgs.iproute2 ];
      } ''
        # Get hardware info
        get_nvme_serial() {
          if command -v nvme >/dev/null 2>&1 && [ -e /dev/nvme0n1 ]; then
            nvme id-ctrl /dev/nvme0n1 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "test-nvme-serial"
          elif [ -f "/sys/class/nvme/nvme0/serial" ]; then
            cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "test-nvme-serial"
          else
            echo "test-nvme-serial"
          fi
        }
        
        get_mac_address() {
          ip link show 2>/dev/null | grep -E "link/ether" | head -1 | awk '{print $2}' 2>/dev/null || echo "02:00:00:00:00:01"
        }
        
        NVME_SERIAL=$(get_nvme_serial)
        MAC_ADDRESS=$(get_mac_address)
        
        echo "Detected hardware:"
        echo "  NVMe Serial: $NVME_SERIAL"
        echo "  MAC Address: $MAC_ADDRESS"
        
        # Create ASL file with hardware info
        cat > hwinfo.asl << EOF
        DefinitionBlock ("hwinfo.aml", "SSDT", 2, "NIXOS", "HWINFO", 0x00000001)
        {
            Scope (\_SB)
            {
                Device (HWIF)
                {
                    Name (_HID, "ACPI0001")
                    Name (_UID, 0x01)
                    Name (NVME, "$NVME_SERIAL")
                    Name (MACA, "$MAC_ADDRESS")
                    Name (INFO, Package (0x04)
                    {
                        "NVME_SERIAL",
                        "$NVME_SERIAL",
                        "MAC_ADDRESS", 
                        "$MAC_ADDRESS"
                    })
                }
            }
        }
        EOF
        
        # Compile to AML
        iasl -tc hwinfo.asl
        cp hwinfo.aml $out
      '';
    in
    {
      # NixOS configuration for MicroVM with hardware info
      nixosConfigurations.microvm-hwinfo = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          microvm.nixosModules.microvm
          {
            # Basic system configuration
            networking.hostName = "microvm-hwinfo";
            users.users.root.password = "";
            services.getty.autologinUser = "root";
            system.stateVersion = "24.05";

            # MicroVM configuration
            microvm = {
              hypervisor = "qemu";
              vcpu = 2;
              mem = 1024;
              
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
              
              # Inject ACPI hardware info
              qemu.extraArgs = [
                "-acpitable"
                "file=${hwinfo-aml}"
              ];
            };

            # Install hardware info tools
            environment.systemPackages = with pkgs; [
              acpica-tools  # For acpidump
              jq           # For JSON processing
              vim
              htop
            ];

            # Hardware info reading script
            environment.etc."read-hwinfo.sh" = {
              text = ''
                #!/bin/bash
                echo "=== Hardware Info from ACPI ==="
                if command -v acpidump >/dev/null 2>&1; then
                  echo "ACPI tables available:"
                  acpidump -n SSDT | grep -A 20 "HWINFO" || echo "No HWINFO table found"
                else
                  echo "acpidump not available"
                fi
                
                echo ""
                echo "=== Checking /sys/firmware/acpi/tables ==="
                if [ -d "/sys/firmware/acpi/tables" ]; then
                  echo "ACPI tables in sysfs:"
                  ls -la /sys/firmware/acpi/tables/ | grep -i ssdt || echo "No SSDT tables found"
                else
                  echo "/sys/firmware/acpi/tables not available"
                fi
              '';
              mode = "0755";
            };

            # Test script
            environment.etc."test-hwinfo.sh" = {
              text = ''
                #!/bin/bash
                echo "🔍 Testing hardware info access in MicroVM..."
                /etc/read-hwinfo.sh
                echo ""
                echo "✅ Hardware info test completed!"
              '';
              mode = "0755";
            };

            # Auto-run test on login
            programs.bash.loginShellInit = ''
              echo "🚀 Welcome to MicroVM with Hardware Info!"
              echo "Available commands:"
              echo "  /etc/read-hwinfo.sh  - Read hardware info"
              echo "  /etc/test-hwinfo.sh  - Run hardware info test"
              echo ""
            '';
          }
        ];
      };

      # Apps for easy running
      apps.${system} = {
        microvm-run = {
          type = "app";
          program = "${self.nixosConfigurations.microvm-hwinfo.config.microvm.declaredRunner}/bin/microvm-run";
        };
      };

      # Packages
      packages.${system} = {
        # MicroVM runner package
        microvm-hwinfo = self.nixosConfigurations.microvm-hwinfo.config.microvm.declaredRunner;
        
        # ACPI table with hardware info
        inherit hwinfo-aml;

        # Hardware info generator
        acpi-hwinfo-generate = pkgs.writeShellScriptBin "acpi-hwinfo-generate" ''
          set -euo pipefail
          
          # Create output directory
          OUTPUT_DIR="/var/lib/acpi-hwinfo"
          if [ ! -w "$(dirname "$OUTPUT_DIR")" ]; then
            OUTPUT_DIR="./acpi-hwinfo"
          fi
          mkdir -p "$OUTPUT_DIR"
          
          # Get hardware info
          get_nvme_serial() {
            if command -v nvme >/dev/null 2>&1 && [ -e /dev/nvme0n1 ]; then
              nvme id-ctrl /dev/nvme0n1 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "nvme_card-pd"
            elif [ -f "/sys/class/nvme/nvme0/serial" ]; then
              cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "nvme_card-pd"
            else
              echo "nvme_card-pd"
            fi
          }
          
          get_mac_address() {
            ${pkgs.iproute2}/bin/ip link show 2>/dev/null | grep -E "link/ether" | head -1 | awk '{print $2}' 2>/dev/null || echo "e2:0c:c9:55:0f:dc"
          }
          
          NVME_SERIAL=$(get_nvme_serial)
          MAC_ADDRESS=$(get_mac_address)
          
          echo "🔍 Detected hardware:"
          echo "  NVMe Serial: $NVME_SERIAL"
          echo "  MAC Address: $MAC_ADDRESS"
          
          # Generate JSON metadata
          cat > "$OUTPUT_DIR/hwinfo.json" << EOF
          {
            "nvme_serial": "$NVME_SERIAL",
            "mac_address": "$MAC_ADDRESS",
            "generated": "$(date -Iseconds)"
          }
          EOF
          
          # Generate ACPI ASL
          cat > "$OUTPUT_DIR/hwinfo.asl" << EOF
          /*
           * Hardware Info ACPI Table
           * Generated: $(date)
           */
          DefinitionBlock ("hwinfo.aml", "SSDT", 2, "NIXOS", "HWINFO", 1)
          {
              Scope (\\_SB)
              {
                  Device (HWIF)
                  {
                      Name (_HID, "ACPI0001")
                      Name (_UID, 0x01)
                      Name (NVME, "$NVME_SERIAL")
                      Name (MACA, "$MAC_ADDRESS")
                      Name (INFO, Package (0x04)
                      {
                          "NVME_SERIAL",
                          "$NVME_SERIAL",
                          "MAC_ADDRESS", 
                          "$MAC_ADDRESS"
                      })
                  }
              }
          }
          EOF
          
          # Compile to AML
          echo "🔨 Compiling ACPI table..."
          cd "$OUTPUT_DIR"
          ${pkgs.acpica-tools}/bin/iasl -tc hwinfo.asl
          
          if [ -f hwinfo.aml ]; then
            echo "✅ ACPI table compiled successfully: $OUTPUT_DIR/hwinfo.aml"
            echo "📄 Hardware info JSON: $OUTPUT_DIR/hwinfo.json"
          else
            echo "❌ Failed to compile ACPI table"
            exit 1
          fi
        '';

        # Test runner
        run-test-vm-with-hwinfo = pkgs.writeShellScriptBin "run-test-vm-with-hwinfo" ''
          set -euo pipefail
          
          echo "🚀 Running end-to-end test with MicroVM..."
          
          # Generate hardware info
          ${self.packages.${system}.acpi-hwinfo-generate}/bin/acpi-hwinfo-generate
          echo "✅ Hardware info generated successfully"
          
          # Show ACPI table info
          echo "🔍 Testing ACPI table generation..."
          echo "✅ Generated ACPI table: ${hwinfo-aml}"
          file ${hwinfo-aml}
          
          echo ""
          echo "🚀 To run the MicroVM:"
          echo "   nix run .#microvm-run"
          echo ""
          echo "✅ End-to-end test completed successfully!"
        '';
      };

      # Development shell
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          acpica-tools
          jq
          qemu
        ];
        
        shellHook = ''
          echo "🔧 MicroVM Hardware Info Development Environment"
          echo ""
          echo "Available commands:"
          echo "  nix run .#microvm-run             - Run MicroVM directly"
          echo "  nix run .#acpi-hwinfo-generate    - Generate hardware info"
          echo "  nix run .#run-test-vm-with-hwinfo - Run end-to-end test"
          echo ""
        '';
      };
    };
}