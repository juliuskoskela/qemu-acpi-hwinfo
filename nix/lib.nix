{ inputs, ... }:
{
  flake = {
    lib = {
      # Function to generate hardware info with custom values
      generateHwInfo = { system, nvmeSerial ? null, macAddress ? null }:
        inputs.self.packages.${system}.generateHwInfo {
          inherit nvmeSerial macAddress;
        };

      # Function to create a MicroVM configuration with hardware info
      mkMicroVMWithHwInfo = { system, nvmeSerial ? null, macAddress ? null, ... }@args:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          hwinfo = inputs.self.lib.generateHwInfo {
            inherit system nvmeSerial macAddress;
          };
        in {
          imports = [
            inputs.microvm.nixosModules.microvm
            inputs.self.nixosModules.guest
          ];

          services.acpi-hwinfo-guest.enable = true;

          microvm = {
            enable = true;

            qemu = {
              extraArgs = [
                "-acpitable"
                "file=${hwinfo}/hwinfo.aml"
              ];
            };

            # Default VM configuration
            vcpu = 2;
            mem = 2048;

            interfaces = [{
              type = "user";
              id = "vm-net";
              mac = "02:00:00:00:00:01";
            }];

            shares = [{
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              tag = "ro-store";
              proto = "virtiofs";
            }];
          };

          # Basic system configuration
          system.stateVersion = "24.05";

          # Enable guest services
          services.getty.autologinUser = "root";

          # Add some basic packages
          environment.systemPackages = with pkgs; [
            vim
            htop
            curl
          ];
        };
    };
  };
}