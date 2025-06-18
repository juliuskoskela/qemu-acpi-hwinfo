{ inputs, ... }:
{
  flake = {
    nixosModules = {
      # Host module for generating hardware info on the host system
      acpi-hwinfo-host = import ./host.nix;

      # Guest module for VMs to use hardware info
      acpi-hwinfo-guest = import ./guest.nix;

      # Combined module (includes both host and guest functionality)
      acpi-hwinfo = { config, lib, ... }: {
        imports = [
          ./host.nix
          ./guest.nix
        ];
      };

      # Legacy alias
      default = import ./host.nix;
    };
  };
}
