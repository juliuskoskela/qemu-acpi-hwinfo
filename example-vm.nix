# Example VM configuration using the ACPI hardware info flake
{ self, nixpkgs, microvm }:

let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};

  # Generate hardware info with custom values
  hwinfo = self.lib.generateHwInfo {
    inherit system;
    nvmeSerial = "EXAMPLE_NVME_SERIAL_123";
    macAddress = "00:11:22:33:44:55";
  };

in
{
  imports = [
    microvm.nixosModules.microvm
    self.nixosModules.guest
  ];

  # Enable the guest hardware info reader
  services.acpi-hwinfo-guest.enable = true;

  # MicroVM configuration
  microvm = {
    # Basic VM settings
    vcpu = 2;
    mem = 2048;

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

    # QEMU-specific configuration with ACPI table
    qemu = {
      extraArgs = [
        "-acpitable"
        "file=${hwinfo}/hwinfo.aml"
      ];
    };
  };

  # System configuration
  system.stateVersion = "24.05";

  # Auto-login as root for testing
  services.getty.autologinUser = "root";

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
  ];
}
