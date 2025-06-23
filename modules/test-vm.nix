{ pkgs, modulesPath, ... }:

{
  # Import QEMU guest profile
  imports = [ 
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];
  
  # Enable the ACPI hardware info guest module
  acpi-hwinfo.guest.enable = true;
  
  # Basic VM configuration
  system.stateVersion = "24.05";
  
  # VM-specific configuration
  virtualisation = {
    memorySize = 1024;
    cores = 2;
    qemu.options = [ "-nographic" ];
  };
  
  # File systems
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  
  # Boot configuration
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };
  
  # Enable SSH for testing
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
    settings.PasswordAuthentication = true;
  };
  
  # Set root password for testing
  users.users.root.password = "test";
  
  # Auto-login on console
  services.getty.autologinUser = "root";
  
  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    htop
    curl
    file
    hexdump
    binutils
  ];
  
  # Network configuration
  networking = {
    hostName = "hwinfo-test-vm";
    dhcpcd.enable = true;
  };
  
  # Enable QEMU guest agent
  services.qemuGuest.enable = true;
}