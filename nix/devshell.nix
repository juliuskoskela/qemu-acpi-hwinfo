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

        # Virtualization tools
        # (MicroVM dependencies handled by flake inputs)

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
            echo "   run-test-microvm        - Run end-to-end test with MicroVM"
            echo "   run-test-vm-with-hwinfo - Alias for run-test-microvm"
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
          name = "run-test-microvm";
          help = "Run end-to-end test with MicroVM";
          command = ''
            echo "🚀 Running end-to-end test with MicroVM..."
            nix --extra-experimental-features "nix-command flakes" run .#run-test-microvm
          '';
        }
        {
          name = "run-test-vm-with-hwinfo";
          help = "Alias for run-test-microvm";
          command = ''
            echo "🚀 Running end-to-end test with MicroVM..."
            nix --extra-experimental-features "nix-command flakes" run .#run-test-vm-with-hwinfo
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
