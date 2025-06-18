{ inputs, ... }:
{
  imports = [
    inputs.devshell.flakeModule
  ];

  perSystem = { config, self', inputs', pkgs, system, ... }: {
    devshells.default = {
      name = "qemu-acpi-hwinfo";
      motd = ''
        {202}🔧 Welcome to qemu-acpi-hwinfo development environment{reset}
        
        Available commands:
        • {green}acpi-hwinfo{reset} - Read hardware info from current machine
        • {green}nix build{reset} - Build the hwinfo package
        • {green}nix run{reset} - Generate hwinfo for current machine
        
        $(type -p menu &>/dev/null && menu)
      '';

      packages = with pkgs; [
        # ACPI and hardware tools
        acpica-tools
        nvme-cli
        iproute2
        util-linux

        # QEMU and virtualization
        qemu

        # Development tools
        jq
        curl

        # Nix tools
        nixpkgs-fmt
        nil
      ];

      commands = [
        {
          name = "acpi-hwinfo";
          help = "Read hardware info and show runtime status";
          command = ''
            echo "🔍 ACPI Hardware Info Status"
            echo "=========================="
            echo
            
            # Check runtime hwinfo
            HWINFO_DIR="/var/lib/acpi-hwinfo"
            if [ -d "$HWINFO_DIR" ]; then
              echo "📁 Runtime hwinfo directory exists: $HWINFO_DIR"
              if [ -f "$HWINFO_DIR/hwinfo.json" ]; then
                echo "📄 Runtime hardware info:"
                ${pkgs.jq}/bin/jq . "$HWINFO_DIR/hwinfo.json" 2>/dev/null || cat "$HWINFO_DIR/hwinfo.json"
                echo
              else
                echo "❌ No runtime hwinfo.json found"
              fi
            else
              echo "❌ Runtime hwinfo directory not found: $HWINFO_DIR"
              echo "💡 Enable the acpi-hwinfo NixOS module to create it"
              echo
            fi
            
            echo "💻 Current machine hardware detection:"
            echo
            
            # Detect NVMe serial
            NVME_SERIAL=""
            if command -v nvme >/dev/null 2>&1; then
              NVME_SERIAL=$(nvme list 2>/dev/null | awk 'NR>1 {print $2; exit}' || echo "")
            fi
            if [ -z "$NVME_SERIAL" ] && [ -f /sys/class/nvme/nvme0/serial ]; then
              NVME_SERIAL=$(cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "")
            fi
            if [ -z "$NVME_SERIAL" ]; then
              NVME_SERIAL="not detected"
            fi
            
            # Detect MAC address
            MAC_ADDRESS=""
            if command -v ip >/dev/null 2>&1; then
              MAC_ADDRESS=$(ip link show | awk '/ether/ {print $2; exit}' || echo "")
            fi
            if [ -z "$MAC_ADDRESS" ]; then
              MAC_ADDRESS="not detected"
            fi
            
            echo "NVMe Serial: $NVME_SERIAL"
            echo "MAC Address: $MAC_ADDRESS"
            echo
            echo "🛠️  Available commands:"
            echo "   hwinfo-status           - Show detailed hwinfo status"
            echo "   acpi-hwinfo-generate    - Generate hardware info"
            echo "   acpi-hwinfo-show        - Show current hardware info"
            echo "   qemu-with-hwinfo        - Start QEMU with runtime hwinfo"
            echo "   run-test-vm-with-hwinfo - Run test VM with hardware info"
            echo "   create-nixos-vm         - Create a simple NixOS VM for testing"
            echo
            echo "💡 For NixOS systems, enable the acpi-hwinfo module:"
            echo "   services.acpi-hwinfo.enable = true;"
          '';
        }
        {
          name = "acpi-hwinfo-generate";
          help = "Generate hardware info";
          command = ''
            echo "🧪 Generating hardware info..."
            nix --extra-experimental-features "nix-command flakes" run .#acpi-hwinfo-generate
          '';
        }
        {
          name = "acpi-hwinfo-show";
          help = "Show current hardware info";
          command = ''
            echo "📊 Showing hardware info..."
            nix --extra-experimental-features "nix-command flakes" run .#acpi-hwinfo-show
          '';
        }
        {
          name = "hwinfo-status";
          help = "Show detailed hwinfo status";
          command = ''
            echo "🔍 Checking hwinfo status..."
            nix --extra-experimental-features "nix-command flakes" run .#hwinfo-status
          '';
        }
        {
          name = "qemu-with-hwinfo";
          help = "Start QEMU with runtime hardware info";
          command = ''
            echo "🚀 Starting QEMU with runtime hardware info..."
            nix --extra-experimental-features "nix-command flakes" run .#qemu-with-hwinfo -- "$@"
          '';
        }
        {
          name = "run-test-vm-with-hwinfo";
          help = "Run test VM with hardware info";
          command = ''
            echo "🚀 Running test VM with hardware info..."
            nix --extra-experimental-features "nix-command flakes" run .#run-test-vm-with-hwinfo
          '';
        }
        {
          name = "create-nixos-vm";
          help = "Create a simple NixOS VM for testing";
          command = ''
            echo "🔨 Creating NixOS VM image..."
            echo "This will create a minimal NixOS VM with our guest module enabled."
            echo
            
            # Create a temporary configuration
            cat > vm-config.nix <<EOF
{ config, pkgs, ... }:
{
  imports = [ <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix> ];
  
  # Enable our guest module
  services.acpi-hwinfo = {
    enable = true;
    guestTools = true;
  };
  
  # Basic VM configuration
  virtualisation = {
    memorySize = 2048;
    diskSize = 4096;
    graphics = false;
  };
  
  # Auto-login for testing
  services.getty.autologinUser = "root";
  
  # Test packages
  environment.systemPackages = with pkgs; [
    jq
    acpica-tools
    vim
    htop
  ];
  
  system.stateVersion = "24.05";
}
EOF
            
            echo "📝 Building VM with configuration..."
            nix-build '<nixpkgs/nixos>' -A vm -I nixos-config=./vm-config.nix -o nixos-vm
            
            echo "✅ VM created! You can now run:"
            echo "   run-test-vm-with-hwinfo nixos-vm/nixos.qcow2"
            echo
            echo "Or manually with:"
            echo "   ./nixos-vm/bin/run-nixos-vm"
          '';
        }
      ];

      env = [
        {
          name = "QEMU_ACPI_HWINFO_DEV";
          value = "1";
        }
      ];
    };
  };
}
