# Example MicroVM configuration with ACPI hardware info
{ self, nixpkgs, microvm }:

let
  system = "x86_64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
in

self.lib.mkMicroVMWithHwInfo {
  inherit system;

  # Optional: Override hardware info
  # nvmeSerial = "CUSTOM_NVME_SERIAL";
  # macAddress = "00:11:22:33:44:55";

  # Additional VM configuration
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
  };

  # Additional system configuration
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