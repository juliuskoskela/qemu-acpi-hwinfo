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
          help = "Read hardware info from the current development machine";
          command = ''
            echo "🔍 Reading hardware info from current machine..."
            echo
            
            # Try to read from generated hwinfo if available
            if [ -f "./result/hwinfo.json" ]; then
              echo "📄 Found generated hwinfo.json:"
              ${pkgs.jq}/bin/jq . ./result/hwinfo.json
              echo
            fi
            
            # Read current machine hardware info
            echo "💻 Current machine hardware info:"
            echo
            
            # NVMe Serial
            echo -n "NVMe Serial: "
            if command -v nvme >/dev/null 2>&1 && [ -e /dev/nvme0n1 ]; then
              nvme id-ctrl /dev/nvme0n1 2>/dev/null | grep '^sn' | awk '{print $3}' || echo "UNKNOWN"
            elif [ -f "/sys/class/nvme/nvme0/serial" ]; then
              cat /sys/class/nvme/nvme0/serial 2>/dev/null || echo "UNKNOWN"
            else
              echo "UNKNOWN (no NVMe device found)"
            fi
            
            # MAC Address
            echo -n "MAC Address: "
            ip link show 2>/dev/null | grep -E "link/ether" | head -1 | awk '{print $2}' 2>/dev/null || echo "00:00:00:00:00:00"
            
            echo
            echo "💡 To generate hwinfo package with current values:"
            echo "   nix build"
            echo
            echo "💡 To generate hwinfo with custom values:"
            echo "   nix build .#packages.x86_64-linux.generateHwInfo --override-input nvmeSerial \"CUSTOM_SERIAL\""
          '';
        }
        {
          name = "build-hwinfo";
          help = "Build hwinfo package for current machine";
          command = ''
            echo "🔨 Building hwinfo package..."
            nix --extra-experimental-features "nix-command flakes" build .#hwinfo
            echo "✅ Built hwinfo package at ./result"
            echo
            echo "📄 Generated files:"
            ls -la ./result/
            echo
            if [ -f "./result/hwinfo.json" ]; then
              echo "📋 Hardware info:"
              ${pkgs.jq}/bin/jq . ./result/hwinfo.json
            fi
          '';
        }
        {
          name = "test-vm";
          help = "Test the hwinfo in a microVM";
          command = ''
            echo "🚀 Testing hwinfo in microVM..."
            echo "This will build and run a test VM with the generated hwinfo"
            echo "Note: MicroVM functionality requires additional setup"
            echo "Use the example-vm.nix or microvm.nix files for VM configuration"
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