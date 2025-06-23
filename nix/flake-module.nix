{ inputs, ... }:
{
  imports = [
    inputs.devshell.flakeModule
  ];

  perSystem = { config, self', inputs', pkgs, system, ... }: {
    devshells.default = {
      name = "qemu-acpi-hwinfo";
      motd = ''
        🔧 Welcome to qemu-acpi-hwinfo development environment
        
        Available commands:
        • test-vm         - Run test VM with host hardware info
        • generate-hwinfo - Generate ACPI hardware info table  
        • read-hwinfo     - Read hardware info from ACPI (in VM only)
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
        
        # Add our packages to the shell
        self'.packages.generate-hwinfo
        self'.packages.read-hwinfo
        self'.packages.test-vm
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