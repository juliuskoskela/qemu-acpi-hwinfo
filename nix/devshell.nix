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
        
        Quick start:
        • {green}acpi-hwinfo{reset} - Show hardware info and available commands
        • {green}run-test-microvm{reset} - Run MicroVM with ACPI hardware info (sudo)
        
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
            echo "   test-microvm-with-hwinfo - Complete MicroVM test (working)"
            echo "   run-test-microvm      - Run MicroVM with ACPI hwinfo (sudo)"
            echo
            echo "💡 For NixOS systems, enable the acpi-hwinfo module:"
            echo "   services.acpi-hwinfo.enable = true;"
          '';
        }
        {
          name = "create-test-hwinfo";
          help = "Create test hardware info files";
          command = ''
            echo "🧪 Creating test hardware info..."
            nix --extra-experimental-features "nix-command flakes" run .#create-test-hwinfo
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
          name = "integration-test";
          help = "Run integration tests";
          command = ''
            echo "🔬 Running integration tests..."
            nix --extra-experimental-features "nix-command flakes" run .#integration-test
          '';
        }
        {
          name = "run-test-vm";
          help = "Build and run test VM";
          command = ''
            echo "🚀 Building and running test VM..."
            nix --extra-experimental-features "nix-command flakes" run .#run-test-vm
          '';
        }
        {
          name = "run-test-vm-with-hwinfo";
          help = "Run test VM with qemu-with-hwinfo";
          command = ''
            echo "🚀 Running test VM with hardware info..."
            nix --extra-experimental-features "nix-command flakes" run .#run-test-vm-with-hwinfo
          '';
        }
        {
          name = "run-automated-vm-test";
          help = "Run automated VM test (runs test and exits)";
          command = ''
            echo "🔬 Running automated VM test..."
            nix --extra-experimental-features "nix-command flakes" run .#run-automated-vm-test
          '';
        }
        {
          name = "test-microvm-with-hwinfo";
          help = "Complete MicroVM test (working)";
          command = ''
            echo "🧪 Running complete MicroVM test..."
            nix --extra-experimental-features "nix-command flakes" run .#test-microvm-with-hwinfo
          '';
        }
        {
          name = "run-test-microvm";
          help = "Run MicroVM with ACPI hardware info (requires sudo)";
          command = ''
            echo "🚀 Running MicroVM with ACPI hardware info..."
            echo "⚠️  This command requires sudo privileges"
            sudo env PATH="$PATH" nix --extra-experimental-features "nix-command flakes" run .#run-test-microvm
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
