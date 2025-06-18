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
            
            # Import shared hardware detection functions
            ${inputs.self.lib.hardwareDetectionScript pkgs}
            
            # Use shared detection functions
            NVME_SERIAL=$(detect_nvme_serial)
            MAC_ADDRESS=$(detect_mac_address)
            
            echo "NVMe Serial: $NVME_SERIAL"
            echo "MAC Address: $MAC_ADDRESS"
            echo
            echo "🛠️  Available commands:"
            echo "   hwinfo-status         - Show detailed hwinfo status"
            echo "   create-test-hwinfo    - Create test hwinfo files"
            echo "   qemu-with-hwinfo      - Start QEMU with runtime hwinfo"
            echo "   integration-test      - Run integration tests"
            echo "   run-test-vm           - Build and run test VM"
            echo "   run-test-vm-with-hwinfo - Run test VM with hardware info"
            echo "   run-automated-vm-test - Run automated VM test (auto-exit)"
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
