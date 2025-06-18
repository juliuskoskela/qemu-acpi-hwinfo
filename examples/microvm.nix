# Example MicroVM configuration with ACPI hardware info
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

  # Enable ACPI hardware info for MicroVM
  virtualisation.acpi-hwinfo = {
    enable = true;
    enableMicrovm = true;
    hostHwinfoPath = "/var/lib/acpi-hwinfo/hwinfo.aml";

    # MicroVM-specific flags for ACPI table injection
    microvmFlags = [
      "--acpi-table"
      "/var/lib/acpi-hwinfo/hwinfo.aml"
    ];

    # Additional virtiofs shares for hardware info
    microvmShares = [{
      source = "/var/lib/acpi-hwinfo";
      mountPoint = "/var/lib/acpi-hwinfo";
      tag = "hwinfo";
      proto = "virtiofs";
    }];
  };

  # MicroVM configuration
  microvm = {
    vcpu = 4;
    mem = 4096;

    # Add a disk
    volumes = [{
      image = "disk.qcow2";
      mountPoint = "/";
      size = 8192; # 8GB
    }];

    # Network configuration
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
  };

  # System configuration
  system.stateVersion = "24.05";

  # Services
  services = {
    openssh = {
      enable = true;
      settings.PermitRootLogin = "yes";
    };
  };

  # Add more packages as needed
  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
    git
  ];
}
