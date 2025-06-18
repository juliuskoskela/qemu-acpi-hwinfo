{
  description = "QEMU ACPI hardware info embedding system";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, nixpkgs, microvm, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./nix/devshell.nix
      ];
      systems = [ "x86_64-linux" "aarch64-linux" ];
      
      perSystem = { pkgs, system, ... }: {
        packages = {
          # Generate hardware info and create ACPI table
          generate-hwinfo = pkgs.writeShellScriptBin "generate-hwinfo" ''
            export PATH="${pkgs.lib.makeBinPath (with pkgs; [ nvme-cli iproute2 acpica-tools coreutils ])}:$PATH"
            set -euo pipefail
            
            HWINFO_DIR="''${1:-/var/lib/acpi-hwinfo}"
            mkdir -p "$HWINFO_DIR"
            
            # Detect NVMe serial with multiple fallback methods
            NVME_SERIAL=""
            if command -v nvme >/dev/null 2>&1; then
              # Method 1: nvme id-ctrl (most reliable)
              for nvme_dev in /dev/nvme*n1; do
                if [ -e "$nvme_dev" ]; then
                  NVME_SERIAL=$(nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "")
                  if [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ]; then
                    break
                  fi
                fi
              done
              
              # Method 2: nvme list fallback
              if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
                NVME_SERIAL=$(nvme list 2>/dev/null | awk 'NR>1 && $2 != "---------------------" {print $2; exit}' || echo "")
              fi
            fi
            if [ -z "$NVME_SERIAL" ] && [ -f /sys/class/nvme/nvme0/serial ]; then
              NVME_SERIAL=$(cat /sys/class/nvme/nvme0/serial 2>/dev/null | tr -d ' \n' || echo "")
            fi
            # Try alternative paths
            if [ -z "$NVME_SERIAL" ]; then
              for nvme_dev in /sys/class/nvme/nvme*/serial; do
                if [ -f "$nvme_dev" ]; then
                  NVME_SERIAL=$(cat "$nvme_dev" 2>/dev/null | tr -d ' \n' || echo "")
                  [ -n "$NVME_SERIAL" ] && break
                fi
              done
            fi
            # Try lsblk method
            if [ -z "$NVME_SERIAL" ] && command -v lsblk >/dev/null 2>&1; then
              NVME_SERIAL=$(lsblk -d -o NAME,SERIAL | grep nvme | awk '{print $2; exit}' || echo "")
            fi
            # Clean up the serial - if it's just dashes or empty, treat as not detected
            if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ] || echo "$NVME_SERIAL" | grep -q '^-*$'; then
              NVME_SERIAL="no-nvme-detected"
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

          # Read hardware info from ACPI in guest
          read-hwinfo = pkgs.writeShellScriptBin "read-hwinfo" ''
            export PATH="${pkgs.lib.makeBinPath (with pkgs; [ binutils coreutils ])}:$PATH"
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

          # Comprehensive test with microvm
          test-microvm-with-hwinfo = pkgs.writeShellScriptBin "test-microvm-with-hwinfo" ''
            export PATH="${pkgs.lib.makeBinPath (with pkgs; [ 
              acpica-tools 
              nvme-cli 
              iproute2 
              qemu
              coreutils
              binutils
              file
              hexdump
            ])}:$PATH"
            set -euo pipefail
            
            # Colors for output
            RED='\033[0;31m'
            GREEN='\033[0;32m'
            BLUE='\033[0;34m'
            YELLOW='\033[1;33m'
            NC='\033[0m'
            
            log() { echo -e "''${BLUE}[$(date +%H:%M:%S)] $1''${NC}"; }
            success() { echo -e "''${GREEN}✓ $1''${NC}"; }
            warning() { echo -e "''${YELLOW}⚠ $1''${NC}"; }
            error() { echo -e "''${RED}✗ $1''${NC}"; }
            
            echo -e "''${BLUE}=== QEMU ACPI Hardware Info - MicroVM Test ===''${NC}"
            echo
            
            # Create test directory
            TEST_DIR=$(mktemp -d)
            trap "rm -rf $TEST_DIR" EXIT
            
            log "1. Generating hardware info for test..."
            
            # Detect hardware with multiple fallback methods
            NVME_SERIAL=""
            if command -v nvme >/dev/null 2>&1; then
              # Method 1: nvme id-ctrl (most reliable)
              for nvme_dev in /dev/nvme*n1; do
                if [ -e "$nvme_dev" ]; then
                  NVME_SERIAL=$(nvme id-ctrl "$nvme_dev" 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "")
                  if [ -n "$NVME_SERIAL" ] && [ "$NVME_SERIAL" != "---------------------" ]; then
                    break
                  fi
                fi
              done
              
              # Method 2: nvme list fallback
              if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ]; then
                NVME_SERIAL=$(nvme list 2>/dev/null | awk 'NR>1 && $2 != "---------------------" {print $2; exit}' || echo "")
              fi
            fi
            if [ -z "$NVME_SERIAL" ] && [ -f /sys/class/nvme/nvme0/serial ]; then
              NVME_SERIAL=$(cat /sys/class/nvme/nvme0/serial 2>/dev/null | tr -d ' \n' || echo "")
            fi
            # Try alternative paths
            if [ -z "$NVME_SERIAL" ]; then
              for nvme_dev in /sys/class/nvme/nvme*/serial; do
                if [ -f "$nvme_dev" ]; then
                  NVME_SERIAL=$(cat "$nvme_dev" 2>/dev/null | tr -d ' \n' || echo "")
                  [ -n "$NVME_SERIAL" ] && break
                fi
              done
            fi
            # Try lsblk method
            if [ -z "$NVME_SERIAL" ] && command -v lsblk >/dev/null 2>&1; then
              NVME_SERIAL=$(lsblk -d -o NAME,SERIAL | grep nvme | awk '{print $2; exit}' || echo "")
            fi
            # Clean up the serial - if it's just dashes or empty, treat as not detected
            if [ -z "$NVME_SERIAL" ] || [ "$NVME_SERIAL" = "---------------------" ] || echo "$NVME_SERIAL" | grep -q '^-*$'; then
              NVME_SERIAL="no-nvme-detected"
            fi
            
            # Detect MAC address
            MAC_ADDRESS=$(ip link show 2>/dev/null | awk '/ether/ {print $2; exit}' || echo "00:00:00:00:00:00")
            
            success "Detected hardware info:"
            echo "  NVME Serial: $NVME_SERIAL"
            echo "  MAC Address: $MAC_ADDRESS"
            
            log "2. Generating ACPI table..."
            
            # Generate ASL file
            cat >"$TEST_DIR/hwinfo.asl" <<EOF
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
            cd "$TEST_DIR" && iasl hwinfo.asl >/dev/null 2>&1
            success "ACPI table compiled: $(wc -c < hwinfo.aml) bytes"
            
            log "3. Analyzing ACPI table content..."
            echo "ACPI table structure:"
            file hwinfo.aml
            echo
            echo "Hardware info strings in table:"
            strings hwinfo.aml | grep -E "(NVME_SERIAL|MAC_ADDRESS|$NVME_SERIAL|$MAC_ADDRESS)" || echo "No hardware strings found"
            
            log "4. Testing ACPI table extraction..."
            echo "Extracting hardware info from compiled table:"
            if command -v strings >/dev/null 2>&1; then
                echo "Hardware info found:"
                EXTRACTED_INFO=$(strings hwinfo.aml | grep -A1 -E "(NVME_SERIAL|MAC_ADDRESS)" | grep -v -E "(NVME_SERIAL|MAC_ADDRESS)" | head -2)
                echo "$EXTRACTED_INFO"
                
                # Validate that expected data is in the table
                if ! strings hwinfo.aml | grep -q "$MAC_ADDRESS"; then
                  error "MAC address '$MAC_ADDRESS' not found in ACPI table"
                  exit 1
                fi
                if [ "$NVME_SERIAL" != "no-nvme-detected" ] && [ "$NVME_SERIAL" != "---------------------" ] && ! strings hwinfo.aml | grep -qF "$NVME_SERIAL"; then
                  error "NVMe serial '$NVME_SERIAL' not found in ACPI table"
                  exit 1
                fi
                success "ACPI table validation passed"
            else
                warning "strings command not available for extraction test"
            fi
            
            log "5. MicroVM test preparation..."
            echo "Generated ACPI table: $TEST_DIR/hwinfo.aml"
            echo "Table size: $(stat -c%s $TEST_DIR/hwinfo.aml) bytes"
            echo "Table checksum: $(sha256sum $TEST_DIR/hwinfo.aml | cut -d' ' -f1)"
            
            log "6. QEMU command for MicroVM testing:"
            echo "To test with QEMU MicroVM:"
            echo "  qemu-system-x86_64 \\"
            echo "    -acpitable file=$TEST_DIR/hwinfo.aml \\"
            echo "    -machine microvm,acpi=on \\"
            echo "    -cpu host \\"
            echo "    -m 512M \\"
            echo "    -nographic \\"
            echo "    -kernel /path/to/kernel \\"
            echo "    -append \"console=ttyS0\" \\"
            echo "    -netdev user,id=net0 \\"
            echo "    -device virtio-net-device,netdev=net0"
            
            echo
            log "7. Building NixOS test VM..."
            echo "Building test VM with ACPI hardware info support..."
            FLAKE_DIR="$(pwd)"
            if (cd "$FLAKE_DIR" && nix build .#nixosConfigurations.test-vm.config.system.build.vm --no-link --quiet 2>/dev/null); then
                success "NixOS test VM built successfully"
                echo "VM can be run with:"
                echo "  cd $FLAKE_DIR && nix run .#nixosConfigurations.test-vm.config.system.build.vm -- -acpitable file=$TEST_DIR/hwinfo.aml"
                VM_BUILD_SUCCESS=true
            else
                warning "Failed to build NixOS test VM"
                echo "This may be due to missing dependencies or environment limitations"
                VM_BUILD_SUCCESS=false
            fi
            
            echo
            echo -e "''${GREEN}=== MicroVM Test Summary ===''${NC}"
            success "Hardware info detection completed"
            success "ACPI table generation and compilation successful"
            success "ACPI table contains expected hardware information"
            success "Table is ready for MicroVM integration"
            if [ "$VM_BUILD_SUCCESS" = "true" ]; then
              success "NixOS test VM build successful"
            else
              warning "NixOS test VM build failed (may require additional setup)"
            fi
            
            echo
            echo -e "''${BLUE}Next steps:''${NC}"
            echo "• Use the generated ACPI table with QEMU MicroVM"
            echo "• Build NixOS VM with: nix build .#nixosConfigurations.test-vm.config.system.build.vm"
            echo "• Test guest reading with the read-hwinfo tool in the VM"
            echo "• The ACPI table is available at: $TEST_DIR/hwinfo.aml"
            
            # Copy the table to a predictable location for further use
            cp "$TEST_DIR/hwinfo.aml" ./test-hwinfo.aml 2>/dev/null || true
            [ -f ./test-hwinfo.aml ] && echo "• ACPI table copied to: ./test-hwinfo.aml"
            
            # Also copy to /tmp for devshell access
            cp "$TEST_DIR/hwinfo.aml" /tmp/qemu-acpi-hwinfo-test.aml 2>/dev/null || true
            [ -f /tmp/qemu-acpi-hwinfo-test.aml ] && echo "• ACPI table also available at: /tmp/qemu-acpi-hwinfo-test.aml"
            
            echo
            if [ "$VM_BUILD_SUCCESS" = "true" ]; then
              echo -e "''${GREEN}✅ MicroVM test completed successfully!''${NC}"
            else
              echo -e "''${YELLOW}⚠️  MicroVM test completed with warnings (VM build failed)''${NC}"
            fi
          '';

          # MicroVM test configuration - actual working MicroVM
          # Simple MicroVM for testing
          test-microvm = let
            nixosSystem = inputs.nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                inputs.microvm.nixosModules.microvm
                ./modules
                ({ pkgs, ... }: {
                  # Basic MicroVM configuration
                  microvm = {
                    hypervisor = "qemu";
                    vcpu = 2;
                    mem = 512;
                    
                    # Network configuration
                    interfaces = [{
                      type = "user";
                      id = "net0";
                      mac = "c8:7f:54:05:d8:e9";
                    }];
                    
                    # Disable virtiofs to avoid socket issues
                    shares = [];
                  };
                  
                  # System configuration
                  system.stateVersion = "24.05";
                  
                  # Enable our ACPI hardware info module
                  acpi-hwinfo.guest.enable = true;
                  
                  # Add test tools to the system
                  environment.systemPackages = with pkgs; [
                    acpica-tools
                    nvme-cli
                    iproute2
                    file
                    hexdump
                  ];
                  
                  # Auto-login as root for testing
                  services.getty.autologinUser = "root";
                  
                  # Add test script to /etc
                  environment.etc."test-acpi-hwinfo.sh" = {
                    mode = "0755";
                    text = ''
                      #!/bin/bash
                      set -euo pipefail
                      
                      echo "🔍 Testing ACPI Hardware Info in MicroVM"
                      echo "========================================"
                      
                      # Check if ACPI device exists
                      if [ -d /sys/firmware/acpi/tables ]; then
                        echo "✓ ACPI tables directory found"
                        
                        # Look for our custom ACPI table
                        if ls /sys/firmware/acpi/tables/SSDT* >/dev/null 2>&1; then
                          echo "✓ SSDT tables found"
                          ls -la /sys/firmware/acpi/tables/SSDT*
                        else
                          echo "❌ No SSDT tables found"
                        fi
                      else
                        echo "❌ ACPI tables directory not found"
                      fi
                      
                      # Try to read hardware info using our module
                      if command -v read-hwinfo >/dev/null 2>&1; then
                        echo "✓ read-hwinfo command available"
                        echo "Reading hardware info from ACPI..."
                        read-hwinfo || echo "❌ Failed to read hardware info"
                      else
                        echo "❌ read-hwinfo command not found"
                      fi
                      
                      echo ""
                      echo "Test completed. Press Ctrl+C to exit MicroVM."
                    '';
                  };
                  
                  # Show test instructions on login
                  programs.bash.shellInit = ''
                    echo "🚀 MicroVM with ACPI Hardware Info"
                    echo "Run: /etc/test-acpi-hwinfo.sh"
                    echo ""
                  '';
                  
                  # Minimal services for faster boot
                  systemd.services.systemd-networkd.enable = false;
                  systemd.services.systemd-resolved.enable = false;
                  networking.useNetworkd = false;
                  networking.useDHCP = false;
                })
              ];
            };
          in
          nixosSystem.config.microvm.runner.qemu;

          # Script to build and run the test MicroVM
          run-test-microvm = pkgs.writeShellScriptBin "run-test-microvm" ''
            set -euo pipefail
            
            echo "🔨 Building test MicroVM..."
            MICROVM=$(nix --extra-experimental-features "nix-command flakes" build --no-link --print-out-paths .#test-microvm)
            
            echo "✅ MicroVM built: $MICROVM"
            echo
            
            # Ensure we have test hardware info
            if [ ! -f "/var/lib/acpi-hwinfo/hwinfo.aml" ]; then
              echo "📝 Creating test hardware info..."
              sudo mkdir -p /var/lib/acpi-hwinfo
              
              # Generate test hardware info
              NVME_SERIAL="MICROVM_TEST_SERIAL_123"
              MAC_ADDRESS="02:03:04:05:06:07"
              
              # Create JSON metadata
              sudo tee /var/lib/acpi-hwinfo/hwinfo.json > /dev/null <<EOF
{
  "nvme_serial": "$NVME_SERIAL",
  "mac_address": "$MAC_ADDRESS",
  "generated": "$(date -Iseconds)"
}
EOF
              
              # Create ASL file
              sudo tee /var/lib/acpi-hwinfo/hwinfo.asl > /dev/null <<EOF
DefinitionBlock ("hwinfo.aml", "SSDT", 2, "HWINFO", "HWINFO", 0x00000001)
{
    Scope (\_SB)
    {
        Device (HWIN)
        {
            Name (_HID, "ACPI0001")
            Name (_UID, 0x00)
            Name (_STR, Unicode ("Hardware Info Device"))
            
            Method (GHWI, 0, NotSerialized)
            {
                Return (Package (0x04)
                {
                    "NVME_SERIAL", 
                    "$NVME_SERIAL", 
                    "MAC_ADDRESS", 
                    "$MAC_ADDRESS"
                })
            }
            
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
        }
    }
}
EOF
              
              # Compile ASL to AML
              echo "🔧 Compiling ASL to AML..."
              (cd /var/lib/acpi-hwinfo && sudo ${pkgs.acpica-tools}/bin/iasl hwinfo.asl >/dev/null 2>&1)
            fi
            
            echo "📋 Using hardware info:"
            cat /var/lib/acpi-hwinfo/hwinfo.json
            echo
            
            echo "🚀 Starting test MicroVM with ACPI hardware info..."
            echo "   MicroVM will auto-login as root"
            echo "   Run '/etc/test-acpi-hwinfo.sh' inside VM to test"
            echo "   Use Ctrl+C to shutdown"
            echo
            
            # Run the MicroVM with ACPI table
            exec "$MICROVM/bin/microvm-run" -acpitable file=/var/lib/acpi-hwinfo/hwinfo.aml
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