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
        • {green}test-microvm-with-hwinfo{reset} - Complete MicroVM test (working)
        • {green}run-test-vm-with-hwinfo{reset} - Build and run NixOS test VM with hardware info
        
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
            # Try multiple methods to detect NVMe serial
            if command -v nvme >/dev/null 2>&1; then
              NVME_SERIAL=$(nvme list 2>/dev/null | awk 'NR>1 && !/^-+/ {print $2; exit}' || echo "")
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
            echo "   run-test-vm-with-hwinfo  - Build and run NixOS test VM with hardware info"
            echo "   run-test-microvm         - Run MicroVM with ACPI hwinfo (sudo)"
            echo
            echo "💡 For NixOS systems, enable the acpi-hwinfo module:"
            echo "   services.acpi-hwinfo.enable = true;"
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

        {
          name = "run-test-vm-with-hwinfo";
          help = "Build and run NixOS test VM with hardware info";
          command = ''
            echo "🚀 Building and running NixOS test VM with hardware info..."
            echo "This will:"
            echo "  1. Generate hardware info and ACPI table"
            echo "  2. Build NixOS test VM"
            echo "  3. Run VM with ACPI table injected"
            echo
            
            # First run the microvm test to generate the ACPI table
            echo "📋 Step 1: Generating ACPI table..."
            if nix --extra-experimental-features "nix-command flakes" run .#test-microvm-with-hwinfo; then
              echo "✅ ACPI table generation completed"
            else
              echo "❌ Failed to generate ACPI table"
              exit 1
            fi
            
            # Check for ACPI table in multiple locations
            ACPI_TABLE=""
            if [ -f ./test-hwinfo.aml ]; then
              ACPI_TABLE="$(pwd)/test-hwinfo.aml"
            elif [ -f /tmp/qemu-acpi-hwinfo-test.aml ]; then
              cp /tmp/qemu-acpi-hwinfo-test.aml ./test-hwinfo.aml
              ACPI_TABLE="$(pwd)/test-hwinfo.aml"
            fi
            
            if [ -n "$ACPI_TABLE" ]; then
              echo
              echo "📦 Step 2: Building NixOS test VM..."
              if nix --extra-experimental-features "nix-command flakes" build .#nixosConfigurations.test-vm.config.system.build.vm; then
                echo
                echo "🚀 Step 3: Running VM with ACPI hardware info..."
                echo "VM will boot with injected hardware info ACPI table"
                echo "Use 'read-hwinfo' command inside VM to test hardware detection"
                echo
                ./result/bin/run-*-vm -acpitable file="$ACPI_TABLE"
              else
                echo "❌ Failed to build NixOS test VM"
                exit 1
              fi
            else
              echo "❌ Failed to find generated ACPI table"
              exit 1
            fi
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
