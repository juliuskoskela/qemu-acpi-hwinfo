{ inputs, ... }:
{
  flake = {
    nixosModules = {
      # Host module for generating hardware info on the host system
      acpi-hwinfo-host = { config, lib, pkgs, ... }: (import ./host.nix { inherit config lib pkgs inputs; });

      # Guest module for VMs to use hardware info
      acpi-hwinfo-guest = import ./guest.nix;

      # Combined module (includes both host and guest functionality)
      acpi-hwinfo = { config, lib, pkgs, ... }: {
        imports = [
          (import ./host.nix { inherit config lib pkgs inputs; })
          ./guest.nix
        ];
      };

      # Legacy alias
      default = { config, lib, pkgs, ... }: (import ./host.nix { inherit config lib pkgs inputs; });
    };
  };
}
