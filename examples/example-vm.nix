# Example VM configuration using the ACPI hardware info flake
{ self, nixpkgs, microvm }:

let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
in
{
  imports = [
    microvm.nixosModules.microvm
    self.nixosModules.acpi-hwinfo-guest
  ];

  # Enable the guest hardware info reader
  virtualisation.acpi-hwinfo = {
    enable = true;
    enableMicrovm = true;
    hostHwinfoPath = "/var/lib/acpi-hwinfo/hwinfo.aml";
  };

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
    # (automatically configured by acpi-hwinfo-guest module)
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
