{
  description = "QEMU ACPI hardware info embedding system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, nixpkgs, microvm, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      
      perSystem = { pkgs, system, ... }: {
        packages = {
          # Generate hardware info and create ACPI table
          generate-hwinfo = pkgs.writeShellApplication {
            name = "generate-hwinfo";
            runtimeInputs = with pkgs; [ nvme-cli iproute2 acpica-tools coreutils ];
            text = ''
            set -euo pipefail
            
            HWINFO_DIR="''${1:-/var/lib/acpi-hwinfo}"
            mkdir -p "$HWINFO_DIR"
            
            # Detect NVMe serial
            NVME_SERIAL="no-nvme-detected"
            if command -v nvme >/dev/null 2>&1; then
              for nvme_dev in /dev/nvme*n1; do
                if [ -e "$nvme_dev" ]; then
                  NVME_SERIAL=$(nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "")
                  [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ] && break
                fi
              done
            fi
            
            # Detect MAC address
            MAC_ADDRESS=$(ip link show 2>/dev/null | awk '/ether/ {print $2; exit}' || echo "00:00:00:00:00:00")
            
            # Generate ASL file
            cat >"$HWINFO_DIR/hwinfo.asl" <<EOF
            DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
            {
                Scope (\_SB)
                {
                    Device (HWIN)
                    {
                        Name (_HID, "ACPI0001")
                        Name (_UID, 0x00)
                        Method (GHWI, 0, NotSerialized)
                        {
                            Return (Package (0x04)
                            {
                                "NVME_SERIAL", "$NVME_SERIAL", 
                                "MAC_ADDRESS", "$MAC_ADDRESS"
                            })
                        }
                        Method (_STA, 0, NotSerialized) { Return (0x0F) }
                    }
                }
            }
            EOF
            
            # Compile to AML
            cd "$HWINFO_DIR" && iasl hwinfo.asl >/dev/null 2>&1
            echo "Generated ACPI hardware info in $HWINFO_DIR"
            '';
          };

          # Read hardware info from ACPI in guest
          read-hwinfo = pkgs.writeShellApplication {
            name = "read-hwinfo";
            runtimeInputs = with pkgs; [ binutils coreutils ];
            text = ''
            set -euo pipefail
            
            ACPI_DEVICE="/sys/bus/acpi/devices/ACPI0001:00"
            [ ! -d "$ACPI_DEVICE" ] && { echo "ACPI device not found"; exit 1; }
            
            # Extract hardware info from ACPI tables
            for table in /sys/firmware/acpi/tables/SSDT*; do
              if strings "$table" 2>/dev/null | grep -q "HWINFO"; then
                strings "$table" | grep -A1 -E "(NVME_SERIAL|MAC_ADDRESS)" | grep -v -E "(NVME_SERIAL|MAC_ADDRESS)" | head -2
                break
              fi
            done
            '';
          };


        };

        # Enhanced dev shell with test scripts
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ 
            nvme-cli 
            acpica-tools 
            qemu
            git
            vim
            htop
            curl
            iproute2
            netcat
            binutils
            hexdump
            file
          ];
          
          shellHook = ''
            echo "🚀 QEMU ACPI Hardware Info Development Environment"
            echo "Available test commands:"
            echo "  ./run-test-vm-with-hwinfo  - Run end-to-end test with VM"
            echo "  ./test-build.sh            - Test building hardware info"
            echo "  ./test-guest-read.sh       - Test guest reading functionality"
            echo ""
            echo "Development tools available:"
            echo "  iasl, nvme, qemu-system-x86_64"
            echo ""
          '';
        };
      };

      flake = {
        nixosModules.default = ./modules;
        
        # Example NixOS configurations for testing
        nixosConfigurations = {
          test-vm = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            modules = [
              ./modules
              ({ pkgs, modulesPath, ... }: {
                # Import QEMU guest profile
                imports = [ 
                  (modulesPath + "/profiles/qemu-guest.nix")
                  (modulesPath + "/virtualisation/qemu-vm.nix")
                ];
                
                # Enable the ACPI hardware info guest module
                acpi-hwinfo.guest.enable = true;
                
                # Basic VM configuration
                system.stateVersion = "24.05";
                
                # VM-specific configuration
                virtualisation = {
                  memorySize = 1024;
                  cores = 2;
                  qemu.options = [ "-nographic" ];
                };
                
                # File systems
                fileSystems."/" = {
                  device = "/dev/disk/by-label/nixos";
                  fsType = "ext4";
                };
                
                # Boot configuration
                boot.loader.grub = {
                  enable = true;
                  device = "/dev/vda";
                };
                
                # Enable SSH for testing
                services.openssh = {
                  enable = true;
                  settings.PermitRootLogin = "yes";
                  settings.PasswordAuthentication = true;
                };
                
                # Set root password for testing
                users.users.root.password = "test";
                
                # Auto-login on console
                services.getty.autologinUser = "root";
                
                # Basic packages
                environment.systemPackages = with pkgs; [
                  vim
                  htop
                  curl
                  file
                  hexdump
                  binutils
                ];
                
                # Network configuration
                networking = {
                  hostName = "hwinfo-test-vm";
                  dhcpcd.enable = true;
                };
                
                # Enable QEMU guest agent
                services.qemuGuest.enable = true;
              })
            ];
          };
        };
      };
    };
}